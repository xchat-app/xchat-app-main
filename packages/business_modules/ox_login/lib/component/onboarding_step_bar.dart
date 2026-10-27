import 'package:flutter/material.dart';
import 'package:ox_common/component.dart';
import 'package:ox_common/utils/adapt.dart';
import 'package:ox_localizable/ox_localizable.dart';

enum OnboardingStep { profile, circle, members, subscribe }

/// The bar across the top of the circle setup pages.
///
/// A new account walks all four steps, starting with its name. An account
/// that already exists and is adding a circle starts at the circle's name, so
/// it sees three: [includesProfile] false.
class OnboardingStepBar extends StatelessWidget {
  const OnboardingStepBar({
    super.key,
    required this.current,
    this.includesProfile = true,
  });

  final OnboardingStep current;
  final bool includesProfile;

  static String _label(OnboardingStep step) {
    switch (step) {
      case OnboardingStep.profile:
        return Localized.text('ox_login.step_you');
      case OnboardingStep.circle:
        return Localized.text('ox_login.step_circle');
      case OnboardingStep.members:
        return Localized.text('ox_login.step_members');
      case OnboardingStep.subscribe:
        return Localized.text('ox_login.step_subscribe');
    }
  }

  @override
  Widget build(BuildContext context) {
    final steps = OnboardingStep.values
        .where((s) => includesProfile || s != OnboardingStep.profile)
        .toList();
    final currentIndex = steps.indexOf(current);
    final activeColor = ColorToken.xChat.of(context);
    final idleColor = ColorToken.onSurfaceVariant.of(context).withValues(alpha: 0.3);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < steps.length; i++) ...[
          if (i > 0) SizedBox(width: 6.px),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 3.px,
                  decoration: BoxDecoration(
                    color: i <= currentIndex ? activeColor : idleColor,
                    borderRadius: BorderRadius.circular(2.px),
                  ),
                ),
                SizedBox(height: 10.px),
                CLText.labelSmall(
                  _label(steps[i]).toUpperCase(),
                  colorToken: i == currentIndex
                      ? ColorToken.onSurface
                      : ColorToken.onSurfaceVariant,
                  isBold: i == currentIndex,
                  maxLines: 1,
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
