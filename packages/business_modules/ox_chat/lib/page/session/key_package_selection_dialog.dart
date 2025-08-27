import 'package:flutter/material.dart';
import 'package:chatcore/chat-core.dart';
import 'package:nostr_core_dart/nostr.dart';
import 'package:ox_common/component.dart';
import 'package:ox_common/utils/adapt.dart';
import 'package:ox_common/widgets/avatar.dart';
import 'package:ox_localizable/ox_localizable.dart';

class KeyPackageSelectionDialog extends StatefulWidget {
  const KeyPackageSelectionDialog({
    super.key,
    required this.pubkey,
    required this.availableKeyPackages,
  });

  final String pubkey;
  final List<KeyPackageEvent> availableKeyPackages;

  /// Static method to show the key package selection dialog
  /// Returns the selected key package string, or null if cancelled
  static Future<String?> show({
    required BuildContext context,
    required String pubkey,
    required List<KeyPackageEvent> availableKeyPackages,
  }) async {
    return await showDialog<String?>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return KeyPackageSelectionDialog(
          pubkey: pubkey,
          availableKeyPackages: availableKeyPackages,
        );
      },
    );
  }

  @override
  State<KeyPackageSelectionDialog> createState() => _KeyPackageSelectionDialogState();
}

class _KeyPackageSelectionDialogState extends State<KeyPackageSelectionDialog> {
  late ValueNotifier<String> selectedKeyPackage$;
  List<SelectedItemModel<String>> data = [];
  UserDBISAR? _userInfo;

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
    
    // Initialize with first key package if only one is available
    final initialKeyPackage = widget.availableKeyPackages.isNotEmpty 
        ? widget.availableKeyPackages.first.encoded_key_package 
        : '';
    
    selectedKeyPackage$ = ValueNotifier<String>(initialKeyPackage);
  }

  Future<void> _loadUserInfo() async {
    final userInfo = await Account.sharedInstance.getUserInfo(widget.pubkey);
    setState(() {
      _userInfo = userInfo;
    });
  }

  String _buildKeyPackageSubtitle(KeyPackageEvent keyPackage) {
    final timestamp = _formatTimestamp(keyPackage.createTime);
    final relayCount = keyPackage.relays.isNotEmpty ? ' • ${keyPackage.relays.length} relays' : '';
    return 'Created: $timestamp$relayCount';
  }

  String _formatTimestamp(int timestamp) {
    final dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.center,
      child: Container(
        width: 320.px,
        decoration: BoxDecoration(
          color: CLScaffold.defaultPageBgColor(context, true),
          borderRadius: BorderRadius.circular(16),
        ),
        padding: EdgeInsets.all(24.px),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            SizedBox(height: 12.px),
            _buildTitle(),
            SizedBox(height: 12.px),
            _buildDescription(),
            SizedBox(height: 12.px),
            _buildKeyPackageList(),
            SizedBox(height: 12.px),
            _buildActionButtons(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        OXUserAvatar(
          user: _userInfo,
          size: 48.px,
        ),
        SizedBox(width: 16.px),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CLText.titleMedium(
                _userInfo?.name ?? _userInfo?.nickName ?? 'Unknown User',
                colorToken: ColorToken.onSurface,
              ),
              SizedBox(height: 4.px),
              CLText.bodySmall(
                '${widget.availableKeyPackages.length} key package${widget.availableKeyPackages.length > 1 ? 's' : ''} available',
                colorToken: ColorToken.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTitle() {
    return CLText.titleMedium(
      Localized.text('ox_chat.select_key_package_title'),
      colorToken: ColorToken.onSurface,
    );
  }

  Widget _buildDescription() {
    // Since all keypackages shown here are not from XChat
    return CLText.bodySmall(
      Localized.text('ox_chat.other_client_keypackages_warning'),
      colorToken: ColorToken.error,
    );
  }

  Widget _buildKeyPackageList() {
    // Create data list for CLSectionListView
    data = widget.availableKeyPackages.map((keyPackage) {
      final clientName = keyPackage.client.isNotEmpty ? keyPackage.client : 'Unknown Client';
      
      return SelectedItemModel<String>(
        title: clientName,
        subtitle: _buildKeyPackageSubtitle(keyPackage),
        value: keyPackage.encoded_key_package,
        selected$: selectedKeyPackage$,
      );
    }).toList();
    
    // If no key packages available, show empty state
    if (data.isEmpty) {
      return Container(
        constraints: BoxConstraints.loose(
          Size(double.infinity, 100.px),
        ),
        child: Center(
          child: CLText.bodyMedium(
            Localized.text('ox_chat.no_keypackages_available'),
            colorToken: ColorToken.onSurfaceVariant,
          ),
        ),
      );
    }
    
    return Container(
      constraints: BoxConstraints.loose(
        Size(double.infinity, 300.px),
      ),
      child: SingleChildScrollView(
        child: CLSectionListView(
          shrinkWrap: true,
          items: [
            SectionListViewItem(
              margin: EdgeInsets.zero,
              data: data,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        Expanded(
          child: CLButton.outlined(
            height: 44.px,
            padding: EdgeInsets.zero,
            onTap: () {
              Navigator.of(context).pop();
            },
            child: CLText.bodyMedium(
              Localized.text('ox_chat.cancel'),
              colorToken: ColorToken.primary,
            ),
          ),
        ),
        SizedBox(width: 12.px),
        Expanded(
          child: CLButton.filled(
            height: 44.px,
            padding: EdgeInsets.zero,
            onTap: selectedKeyPackage$.value.isNotEmpty ? () {
              Navigator.of(context).pop(selectedKeyPackage$.value);
            } : null,
            child: CLText.bodyMedium(
              Localized.text('ox_common.confirm'),
              colorToken: ColorToken.onPrimary,
            ),
          ),
        ),
      ],
    );
  }
} 