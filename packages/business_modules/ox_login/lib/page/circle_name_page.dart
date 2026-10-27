import 'package:flutter/material.dart';
import 'package:ox_common/component.dart';
import 'package:ox_common/navigator/navigator.dart';
import 'package:ox_common/utils/adapt.dart';
import 'package:ox_common/widgets/common_toast.dart';
import 'package:ox_localizable/ox_localizable.dart';

import '../component/onboarding_step_bar.dart';
import '../controller/onboarding_controller.dart';
import '../utils/circle_entry_helper.dart';
import 'capacity_selection_page.dart';

/// First step of buying a circle: what it is called.
///
/// The name comes before the size and the price on purpose. People are
/// setting up a place for particular people ("Family", "Book club"), and the
/// name is what they see on the invite; the plan is a detail of that.
class CircleNamePage extends StatefulWidget {
  const CircleNamePage({
    super.key,
    this.controller,
    this.groupId,
  });

  /// Set for a new account, which came here from its name. Null for an
  /// account that already exists and is adding a circle.
  final OnboardingController? controller;

  /// Subscription group to buy in, when the caller already knows it.
  final String? groupId;

  @override
  State<CircleNamePage> createState() => _CircleNamePageState();
}

class _CircleNamePageState extends State<CircleNamePage> {
  /// A name the relay and the circle list both show without truncating.
  static const int _maxNameLength = 40;

  final TextEditingController _nameController = TextEditingController();
  bool _isCheckingSlot = false;

  String get _name => _nameController.text.trim();

  @override
  void initState() {
    super.initState();
    _nameController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LoseFocusWrap(
      child: CLScaffold(
        appBar: CLAppBar(),
        body: _buildBody(),
        bottomWidget: _buildContinueButton(),
      ),
    );
  }

  Widget _buildBody() {
    return ListView(
      padding: EdgeInsets.symmetric(
        vertical: 24.px,
        horizontal: CLLayout.horizontalPadding,
      ),
      children: [
        OnboardingStepBar(
          current: OnboardingStep.circle,
          includesProfile: widget.controller != null,
        ),
        SizedBox(height: 28.px),
        CLText.titleLarge(
          Localized.text('ox_login.name_your_circle'),
          colorToken: ColorToken.onSurface,
          isBold: true,
        ),
        SizedBox(height: 8.px),
        CLText.bodyMedium(
          Localized.text('ox_login.name_your_circle_desc'),
          colorToken: ColorToken.onSurfaceVariant,
          maxLines: null,
        ),
        SizedBox(height: 28.px),
        _buildPreview(),
        SizedBox(height: 24.px),
        CLTextField(
          controller: _nameController,
          placeholder: Localized.text('ox_usercenter.circle_name'),
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _onContinue(),
        ),
        SizedBox(height: 16.px),
        _buildSuggestions(),
      ],
    );
  }

  Widget _buildPreview() {
    final shown = _name.isEmpty ? Localized.text('ox_login.my_private_circle') : _name;
    return Container(
      padding: EdgeInsets.all(18.px),
      decoration: BoxDecoration(
        color: ColorToken.cardContainer.of(context),
        borderRadius: BorderRadius.circular(24.px),
      ),
      child: Row(
        children: [
          CircleNameAvatar(name: shown, size: 56.px),
          SizedBox(width: 16.px),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CLText.titleMedium(
                  shown,
                  colorToken: ColorToken.onSurface,
                  isBold: true,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: 4.px),
                CLText.bodySmall(
                  Localized.text('ox_login.private_circle_label'),
                  colorToken: ColorToken.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestions() {
    final suggestions = [
      Localized.text('ox_login.circle_name_family'),
      Localized.text('ox_login.circle_name_friends'),
      Localized.text('ox_login.circle_name_team'),
      Localized.text('ox_login.circle_name_club'),
    ];
    return Wrap(
      spacing: 8.px,
      runSpacing: 8.px,
      children: [
        for (final suggestion in suggestions)
          ActionChip(
            label: Text(suggestion),
            onPressed: () {
              _nameController.text = suggestion;
              _nameController.selection = TextSelection.collapsed(offset: suggestion.length);
            },
          ),
      ],
    );
  }

  Widget _buildContinueButton() {
    return CLButton.filled(
      text: Localized.text('ox_login.connect'),
      onTap: _name.isNotEmpty && !_isCheckingSlot ? _onContinue : null,
      expanded: true,
      height: 50.px,
    );
  }

  Future<void> _onContinue() async {
    if (_name.isEmpty || _isCheckingSlot) return;
    final name = _name.length > _maxNameLength ? _name.substring(0, _maxNameLength).trim() : _name;

    setState(() => _isCheckingSlot = true);
    final groupId = widget.groupId ?? await CircleEntryHelper.getCurrentInactiveGroupId();
    if (!mounted) return;
    setState(() => _isCheckingSlot = false);

    if (groupId == null || groupId.isEmpty) {
      CommonToast.instance.show(context, Localized.text('ox_login.subscription_limit_reached'));
      return;
    }
    OXNavigator.pushPage(
      context,
      (context) => CapacitySelectionPage(
        subscriptionGroupId: groupId,
        circleName: name,
        controller: widget.controller,
      ),
    );
  }
}

/// A circle's initial on the app's gradient: how a circle looks before it
/// has a picture, here and on the pages after it.
class CircleNameAvatar extends StatelessWidget {
  const CircleNameAvatar({super.key, required this.name, required this.size});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? '?' : name.trim().characters.first.toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: CLThemeData.themeGradientOf(context),
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Text(
        initial,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.46,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
