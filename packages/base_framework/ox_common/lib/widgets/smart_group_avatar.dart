import 'package:flutter/material.dart';
import 'package:chatcore/chat-core.dart';
import 'package:ox_common/utils/adapt.dart';
import 'package:ox_common/widgets/avatar.dart';

/// Smart group avatar widget that efficiently handles member changes
/// and provides performance optimizations for large lists
class SmartGroupAvatar extends StatefulWidget {
  const SmartGroupAvatar({
    super.key,
    this.groupId,
    this.group,
    this.size,
    this.isCircular = true,
    this.isClickable = false,
    this.onTap,
    this.enableCaching = true,
    this.maxDisplayMembers = 9,
  });

  final String? groupId;
  final GroupDBISAR? group;
  final double? size;
  final bool isCircular;
  final bool isClickable;
  final VoidCallback? onTap;
  final bool enableCaching;
  final int maxDisplayMembers;

  @override
  State<SmartGroupAvatar> createState() => _SmartGroupAvatarState();
}

class _SmartGroupAvatarState extends State<SmartGroupAvatar> {
  static const String _defaultGroupImageName = 'icon_group_default.png';

  List<String> _displayedAvatars = [];
  List<String> _allMemberPubkeys = [];
  ValueNotifier<GroupDBISAR>? _groupNotifier;
  
  double get effectiveSize => widget.size ?? 48.px;
  String get groupId => widget.groupId ?? widget.group?.privateGroupId ?? '';

  @override
  void initState() {
    super.initState();
    _initializeGroupListener();
    _loadGroupMembers();
  }

  @override
  void didUpdateWidget(SmartGroupAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // Check if we need to reinitialize
    final oldGroupId = oldWidget.groupId ?? oldWidget.group?.privateGroupId ?? '';
    final newGroupId = widget.groupId ?? widget.group?.privateGroupId ?? '';
    
    if (oldGroupId != newGroupId) {
      _cleanupGroupListener();
      _initializeGroupListener();
      _loadGroupMembers();
    }
  }

  @override
  void dispose() {
    _cleanupGroupListener();
    super.dispose();
  }

  void _initializeGroupListener() {
    if (groupId.isNotEmpty) {
      _groupNotifier = Groups.sharedInstance.getPrivateGroupNotifier(groupId);
      _groupNotifier?.addListener(_onGroupChanged);
    }
  }

  void _cleanupGroupListener() {
    _groupNotifier?.removeListener(_onGroupChanged);
    _groupNotifier = null;
  }

  void _onGroupChanged() {
    _loadGroupMembers();
  }

  Future<void> _loadGroupMembers() async {
    if (groupId.isEmpty) return;

    try {
      final members = await Groups.sharedInstance.getAllGroupMembers(groupId);
      final newMemberPubkeys = members.map((user) => user.pubKey).toList();
      final newAvatarUrls = members
          .map((user) => user.picture ?? '')
          .take(widget.maxDisplayMembers)
          .toList();

      // Check if we need to update the display
      if (_shouldUpdateDisplay(newMemberPubkeys, newAvatarUrls)) {
        setState(() {
          _allMemberPubkeys = newMemberPubkeys;
          _displayedAvatars = newAvatarUrls;
        });
      }
    } catch (e) {
      debugPrint('SmartGroupAvatar: Failed to load group members: $e');
    }
  }

  /// Optimized update logic to avoid unnecessary refreshes
  bool _shouldUpdateDisplay(List<String> newMemberPubkeys, List<String> newAvatarUrls) {
    // Always update if this is the first load
    if (_allMemberPubkeys.isEmpty) return true;

    // Check if the displayed avatars have changed
    if (_displayedAvatars.length != newAvatarUrls.length) return true;
    
    for (int i = 0; i < _displayedAvatars.length; i++) {
      if (_displayedAvatars[i] != newAvatarUrls[i]) return true;
    }

    // If we already have max members displayed, check if any displayed member was removed
    if (_displayedAvatars.length >= widget.maxDisplayMembers) {
      final currentDisplayedPubkeys = _allMemberPubkeys.take(widget.maxDisplayMembers).toList();
      final newDisplayedPubkeys = newMemberPubkeys.take(widget.maxDisplayMembers).toList();
      
      // Only update if someone in the displayed list changed
      if (currentDisplayedPubkeys.length != newDisplayedPubkeys.length) return true;
      
      for (int i = 0; i < currentDisplayedPubkeys.length; i++) {
        if (currentDisplayedPubkeys[i] != newDisplayedPubkeys[i]) return true;
      }
      
      return false; // No need to update if displayed members haven't changed
    }

    // Update the member list for future comparisons
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return _buildAvatarWidget();
  }

  Widget _buildAvatarWidget() {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: widget.isClickable ? widget.onTap : null,
      child: Container(
        width: effectiveSize,
        height: effectiveSize,
        alignment: Alignment.center,
        child: _buildGroupedAvatar(),
      ),
    );
  }

  Widget _buildGroupedAvatar() {
    // Most members never set a picture, and a grid of grey placeholders says
    // nothing; the group's own initials at least tell groups apart.
    if (_displayedAvatars.every((url) => url.isEmpty)) {
      return _buildDefaultAvatar();
    }

    final avatarCount = _displayedAvatars.length;
    double smallSize;

    if (avatarCount <= 2) {
      smallSize = effectiveSize * 0.66;
    } else if (avatarCount <= 4) {
      smallSize = effectiveSize * 0.5;
    } else {
      smallSize = effectiveSize / 3;
    }

    final avatarWidgets = _displayedAvatars
        .map((url) => _buildSingleAvatar(smallSize, url))
        .toList();

    return _buildAvatarLayout(avatarWidgets, avatarCount);
  }

  Widget _buildAvatarLayout(List<Widget> avatarWidgets, int count) {
    if (count == 1) {
      return avatarWidgets[0];
    } else if (count == 2) {
      return Stack(
        children: [
          Positioned(right: 0, top: 0, child: avatarWidgets[1]),
          Positioned(left: 0, bottom: 0, child: avatarWidgets[0]),
        ],
      );
    } else if (count <= 4) {
      return Wrap(
        children: avatarWidgets,
      );
    } else {
      // For 5+ avatars, arrange in a 3x3 grid
      return Wrap(
        children: avatarWidgets.take(9).toList(),
      );
    }
  }

  Widget _buildSingleAvatar(double size, String imageUrl) {
    return OXUserAvatar(
      imageUrl: imageUrl,
      size: size,
      isCircular: widget.isCircular,
    );
  }

  Widget _buildDefaultAvatar() {
    // The chat list passes only the id; without a name there are no initials.
    final groupName = widget.group?.name ?? _groupNotifier?.value.name ?? '';
    final groupId = widget.groupId ?? widget.group?.privateGroupId ?? '';
    return BaseAvatarWidget(
      defaultImageName: _defaultGroupImageName,
      size: effectiveSize,
      imageUrl: '',
      isCircular: widget.isCircular,
      displayName: groupName,
      pubkey: groupId,
    );
  }
} 