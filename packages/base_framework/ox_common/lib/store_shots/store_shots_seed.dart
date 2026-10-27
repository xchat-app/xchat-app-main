// Store screenshot mode: the made-up family the Play screenshots show.
//
// tool/store_shots/capture.sh pushes tool/store_shots/content/<lang>.json onto
// the device; nothing here is bundled into the app. Everything is written
// straight into the local databases, the way demo_review_seed.dart does it,
// and nothing is ever sent anywhere. See store_shots_flag.dart.

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:chatcore/chat-core.dart';
import 'package:flutter/foundation.dart';
import 'package:ox_common/login/login_manager.dart';
import 'package:ox_common/login/login_models.dart';
import 'package:ox_common/model/chat_session_model_isar.dart';
import 'package:ox_common/model/chat_type.dart';
import 'package:ox_common/utils/key_backup_state.dart';
import 'package:ox_localizable/ox_localizable.dart';
import 'package:path_provider/path_provider.dart';

/// Made up for the screenshots. It never reaches a relay, so it is nobody's.
const String _kPrivkey = 'ef5bef122afd18de6a0e1dcfa6ce7316ebb1d32f60902d89ada1ee66bc50d3b1';

/// A paid circle is one on the private relay host; the tenant does not exist.
const String _kRelayUrl = 'wss://relay.xchat.chat/storeshots';

/// The person ids in the content files mean the account itself by this one.
const String _kMe = 'me';

/// Member limits of the plans on sale (capacity_selection_page.dart).
const List<int> _kPlanSizes = [2, 6, 50];

/// One language's example content: `tool/store_shots/content/<lang>.json`.
class StoreShotsContent {
  StoreShotsContent.fromJson(Map<String, dynamic> json)
      : lang = json['lang'] as String,
        circle = json['circle'] as String,
        me = json['me'] as String,
        people = (json['people'] as Map<String, dynamic>).cast<String, String>(),
        groupName = json['group']['name'] as String,
        groupMembers = (json['group']['members'] as List).cast<String>(),
        groupMessages = (json['group']['messages'] as List).cast<Map<String, dynamic>>(),
        chats = (json['chats'] as List).cast<Map<String, dynamic>>(),
        call = json['call'] as String;

  /// App i18n code: en, fa, ar, fr, es, ru, zh, pt.
  final String lang;
  final String circle;
  final String me;

  /// Person id → display name.
  final Map<String, String> people;
  final String groupName;
  final List<String> groupMembers;

  /// {from, at, text}, oldest first.
  final List<Map<String, dynamic>> groupMessages;

  /// {with, at, text, unread?}, newest first.
  final List<Map<String, dynamic>> chats;

  /// Person id of the incoming call.
  final String call;
}

/// The files capture.sh and the app pass each other, in the app's external
/// files dir, which adb can write to and the app can read.
class StoreShotsFiles {
  StoreShotsFiles._();

  static Future<Directory> _dir() async {
    final base = await getExternalStorageDirectory();
    if (base == null) throw StateError('store shots: no external storage');
    return Directory('${base.path}/store-shots').create(recursive: true);
  }

  /// Waits for capture.sh to push content.json. The app creates the folder
  /// first, so that it owns it.
  static Future<StoreShotsContent> readContent() async {
    final file = File('${(await _dir()).path}/content.json');
    while (!await file.exists()) {
      await Future.delayed(const Duration(milliseconds: 300));
    }
    return StoreShotsContent.fromJson(jsonDecode(await file.readAsString()));
  }

  /// Tells capture.sh that [screen] is on screen, and waits until it has
  /// taken the picture and deleted the marker.
  static Future<void> ready(String screen) async {
    final marker = File('${(await _dir()).path}/ready-$screen');
    await marker.writeAsString(screen);
    while (await marker.exists()) {
      await Future.delayed(const Duration(milliseconds: 200));
    }
  }

  static Future<void> done() async {
    await File('${(await _dir()).path}/done').writeAsString('done');
  }
}

/// The account, circle, people and chats, planted before the first frame.
class StoreShotsSeed {
  StoreShotsSeed._(this.groupSession, this.pubkeys);

  /// The family group, as the chat list holds it.
  final ChatSessionModelISAR groupSession;

  /// Person id → pubkey, [_kMe] included.
  final Map<String, String> pubkeys;

  static Future<StoreShotsSeed> plant(StoreShotsContent content) async {
    await _useLanguage(content.lang);

    final manager = LoginManager.instance;
    if (!await manager.loginWithPrivateKey(_kPrivkey)) {
      throw StateError('store shots: login failed');
    }
    final account = manager.currentState.account!;
    final myPubkey = account.pubkey;

    // Straight into the account, not addCircle: that asks the server about it.
    final circle = Circle(
      name: content.circle,
      relayUrl: _kRelayUrl,
      ownerPubkey: myPubkey,
      category: CircleCategory.paid,
    );
    await manager.updatedCircles([circle]);
    final failure = await manager.switchToCircle(circle);
    if (failure != null) throw StateError('store shots: ${failure.message}');

    final pubkeys = <String, String>{_kMe: myPubkey};
    for (final id in content.people.keys) {
      pubkeys[id] = _fakeKey('person/$id');
    }
    String nameOf(String id) => id == _kMe ? content.me : content.people[id] ?? id;

    final now = DateTime.now();
    final nowSec = now.millisecondsSinceEpoch ~/ 1000;
    final times = _Times(now);
    final isar = DBISAR.sharedInstance.isar;

    // People. A lastUpdatedTime keeps the profile sync from asking for them.
    final me = Account.sharedInstance.me!;
    final groupId = _fakeKey('group');
    me
      ..name = content.me
      ..lastUpdatedTime = nowSec
      ..groupsList = [groupId];
    final users = <UserDBISAR>[me];
    for (final id in content.people.keys) {
      final pubkey = pubkeys[id]!;
      users.add(UserDBISAR(pubKey: pubkey)
        ..name = nameOf(id)
        ..lastUpdatedTime = nowSec
        ..updateEncodedPubkey(pubkey));
    }

    // The family group, with the account in it and on its group list, which
    // is what lets the chat page show the input bar.
    final group = GroupDBISAR(
      groupId: groupId,
      owner: myPubkey,
      name: content.groupName,
      members: [myPubkey, ...content.groupMembers.map((id) => pubkeys[id]!)],
      updateTime: nowSec,
    );

    final messages = <MessageDBISAR>[];
    for (var i = 0; i < content.groupMessages.length; i++) {
      final line = content.groupMessages[i];
      final from = line['from'] as String;
      final text = line['text'] as String;
      messages.add(_message(
        id: 'group/$i',
        sender: pubkeys[from]!,
        receiver: '',
        groupId: groupId,
        text: text,
        // Seconds apart, so two lines in the same minute keep their order.
        createTime: times.resolve(line['at'] as String).millisecondsSinceEpoch ~/ 1000 + i,
        chatType: ChatType.chatGroup,
      ));
    }

    // The chat list builds a group preview as "Sender: text".
    final last = content.groupMessages.last;
    final lastFrom = last['from'] as String;
    final lastSender = lastFrom == _kMe ? Localized.text('ox_chat.you') : nameOf(lastFrom);
    final lastMs = messages.last.createTime * 1000;
    final groupSession = ChatSessionModelISAR(
      chatId: groupId,
      chatName: content.groupName,
      sender: pubkeys[lastFrom]!,
      groupId: groupId,
      content: '$lastSender: ${last['text']}',
      createTime: lastMs,
      lastActivityTime: lastMs,
      chatType: ChatType.chatGroup,
      isSingleChat: false,
      alwaysTop: true,
    );

    final sessions = <ChatSessionModelISAR>[groupSession];
    for (var i = 0; i < content.chats.length; i++) {
      final chat = content.chats[i];
      final pubkey = pubkeys[chat['with'] as String]!;
      final text = chat['text'] as String;
      final unread = (chat['unread'] as int?) ?? 0;
      final at = times.resolve(chat['at'] as String);
      messages.add(_message(
        id: 'chat/$i',
        sender: pubkey,
        receiver: myPubkey,
        groupId: '',
        text: text,
        createTime: at.millisecondsSinceEpoch ~/ 1000,
        chatType: ChatType.chatSingle,
        read: unread == 0,
      ));
      sessions.add(ChatSessionModelISAR(
        chatId: pubkey,
        chatName: nameOf(chat['with'] as String),
        sender: pubkey,
        receiver: pubkey,
        content: text,
        unreadCount: unread,
        createTime: at.millisecondsSinceEpoch,
        lastActivityTime: at.millisecondsSinceEpoch,
        chatType: ChatType.chatSingle,
        isSingleChat: true,
      ));
    }

    await isar.writeAsync((isar) {
      for (final user in users) {
        if (user.id == 0) user.id = isar.userDBISARs.autoIncrement();
      }
      isar.userDBISARs.putAll(users);
      group.id = isar.groupDBISARs.autoIncrement();
      isar.groupDBISARs.put(group);
      for (final message in messages) {
        message.id = isar.messageDBISARs.autoIncrement();
      }
      isar.messageDBISARs.putAll(messages);
      for (final session in sessions) {
        session.id = isar.chatSessionModelISARs.autoIncrement();
      }
      isar.chatSessionModelISARs.putAll(sessions);
    });

    for (final user in users) {
      Account.sharedInstance.updateOrCreateUserNotifier(user.pubKey, user);
    }
    Groups.sharedInstance.updateOrCreateGroupNotifier(groupId, group);
    Groups.sharedInstance.updateOrCreateMyGroupNotifier(groupId, group);

    // What the relay login would have wired up: the header avatar and name.
    LoginUserNotifier.instance.updateUserSource(Account.sharedInstance.getUserNotifier(myPubkey));

    // No "save your account key" banner over the chat list.
    await KeyBackupState.markBackedUp(myPubkey);

    // The plan, as the server would report it: everyone in, renewing in a month.
    final memberIds = [_kMe, ...content.people.keys];
    manager.updateCircleTenantInfo(TenantInfo(
      tenantId: 'storeshots',
      name: content.circle,
      maxMembers: _kPlanSizes.firstWhere((size) => size >= memberIds.length,
          orElse: () => _kPlanSizes.last),
      currentMembers: memberIds.length,
      expiresAt: nowSec + const Duration(days: 30).inSeconds,
      tenantAdminPubkey: myPubkey,
      status: 'active',
      members: [
        for (final id in memberIds)
          TenantMember(pubkey: pubkeys[id]!, role: id == _kMe ? 'admin' : 'member'),
      ],
    ));

    debugPrint('[StoreShots] planted ${content.lang}: ${users.length} people, '
        '${messages.length} messages, ${sessions.length} chats');
    return StoreShotsSeed._(groupSession, pubkeys);
  }

  /// Switches the app language before the first frame, so every module's
  /// strings load in it.
  static Future<void> _useLanguage(String lang) async {
    final type = Localized.getLocaleTypeByString(lang);
    if (Localized.getCurrentLanguage() == type) return;
    await Localized.changeLocale(type);
    // changeLocale returns before the module strings have loaded.
    while (Localized.getCurrentLanguage() != type) {
      await Future.delayed(const Duration(milliseconds: 50));
    }
  }

  static MessageDBISAR _message({
    required String id,
    required String sender,
    required String receiver,
    required String groupId,
    required String text,
    required int createTime,
    required int chatType,
    bool read = true,
  }) {
    return MessageDBISAR(
      messageId: _fakeKey('message/$id'),
      sender: sender,
      receiver: receiver,
      groupId: groupId,
      kind: 14,
      tags: '[]',
      content: text,
      createTime: createTime,
      read: read,
      decryptContent: text,
      type: 'text',
      status: 1,
      chatType: chatType,
    );
  }

  /// 64 hex characters, the same for the same [seed] in every run, so each
  /// person keeps their avatar colour across languages. Nothing checks that
  /// they are real keys: they are only ever ids here.
  static String _fakeKey(String seed) {
    var hash = 0x811c9dc5;
    for (final unit in seed.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
    }
    final random = Random(hash);
    return List.generate(32, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }
}

/// The content's times: "HH:mm" is today, "yesterday" is yesterday evening,
/// and a weekday name is that day 2–6 days ago (or another day in that range
/// when it falls outside it), which the chat list shows by name.
class _Times {
  _Times(DateTime now) : _today = DateTime(now.year, now.month, now.day);

  final DateTime _today;

  /// Later entries in the list are older, so each "yesterday" is earlier
  /// than the one before it.
  static const List<Duration> _evening = [
    Duration(hours: 20, minutes: 47),
    Duration(hours: 18, minutes: 12),
    Duration(hours: 16, minutes: 5),
    Duration(hours: 13, minutes: 30),
  ];
  static const List<String> _weekdays = [
    'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday',
  ];

  int _yesterdays = 0;
  int _earlier = 0;

  DateTime resolve(String at) {
    final clock = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(at);
    if (clock != null) {
      return _today.add(Duration(
        hours: int.parse(clock.group(1)!),
        minutes: int.parse(clock.group(2)!),
      ));
    }
    if (at == 'yesterday') {
      final time = _evening[min(_yesterdays++, _evening.length - 1)];
      return _today.subtract(const Duration(days: 1)).add(time);
    }
    final weekday = _weekdays.indexOf(at) + 1;
    var daysBack = weekday == 0 ? 3 : (_today.weekday - weekday) % 7;
    if (daysBack < 2) daysBack += 7;
    if (daysBack > 6) daysBack = 6;
    return _today
        .subtract(Duration(days: daysBack))
        .add(Duration(hours: 19, minutes: 20 - _earlier++));
  }
}
