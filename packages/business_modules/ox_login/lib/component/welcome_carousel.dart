import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ox_common/utils/adapt.dart';
import 'package:ox_localizable/ox_localizable.dart';

class _Slide {
  const _Slide(this.image, this.alignment, this.lineKey1, this.lineKey2);

  final String image;
  final Alignment alignment;
  final String lineKey1;
  final String lineKey2;
}

/// The photos and two-line headlines across the top of the welcome page.
///
/// The photos are the website's, grayscale with a light purple tint baked
/// in (so the four read as one set), and fade into [background] at the
/// bottom, where the headline sits. It turns every few seconds unless the
/// system asks for no animation; swiping and the dots work either way.
class WelcomeCarousel extends StatefulWidget {
  const WelcomeCarousel({super.key, required this.background});

  final Color background;

  @override
  State<WelcomeCarousel> createState() => _WelcomeCarouselState();
}

class _WelcomeCarouselState extends State<WelcomeCarousel> {
  static const _slides = [
    _Slide('assets/images/onboarding_slide_1.jpg', Alignment(0.4, -0.4),
        'ox_login.welcome_slide_1_line_1', 'ox_login.welcome_slide_1_line_2'),
    _Slide('assets/images/onboarding_slide_2.jpg', Alignment(0.2, -0.2),
        'ox_login.welcome_slide_2_line_1', 'ox_login.welcome_slide_2_line_2'),
    _Slide('assets/images/onboarding_slide_3.jpg', Alignment(0.0, -0.4),
        'ox_login.welcome_slide_3_line_1', 'ox_login.welcome_slide_3_line_2'),
    _Slide('assets/images/onboarding_slide_4.jpg', Alignment.center,
        'ox_login.welcome_slide_4_line_1', 'ox_login.welcome_slide_4_line_2'),
  ];
  static const _interval = Duration(milliseconds: 3500);

  // Far from zero so the pages run on in both directions.
  static const _firstPage = 1000 * 4;

  final PageController _pageController = PageController(initialPage: _firstPage);
  Timer? _timer;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _restartTimer();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    for (final slide in _slides) {
      precacheImage(AssetImage(slide.image, package: 'ox_login'), context);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  /// Restarted on every page change, so a swipe gets a full interval before
  /// the next automatic turn.
  void _restartTimer() {
    _timer?.cancel();
    _timer = Timer(_interval, () {
      if (!mounted || !_pageController.hasClients) return;
      if (MediaQuery.of(context).disableAnimations) return;
      _pageController.nextPage(
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOut,
      );
    });
  }

  void _goTo(int index) {
    final page = (_pageController.page ?? _firstPage.toDouble()).round();
    _pageController.animateToPage(
      page - page % _slides.length + index,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final background = widget.background;
    return Stack(
      fit: StackFit.expand,
      children: [
        PageView.builder(
          controller: _pageController,
          onPageChanged: (page) {
            setState(() => _index = page % _slides.length);
            _restartTimer();
          },
          itemBuilder: (context, page) {
            final slide = _slides[page % _slides.length];
            return Image.asset(
              slide.image,
              package: 'ox_login',
              fit: BoxFit.cover,
              alignment: slide.alignment,
              gaplessPlayback: true,
            );
          },
        ),
        IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  background.withValues(alpha: 0.25),
                  background.withValues(alpha: 0),
                  background.withValues(alpha: 0),
                  background.withValues(alpha: 0.88),
                  background,
                ],
                stops: const [0, 0.18, 0.48, 0.82, 1],
              ),
            ),
          ),
        ),
        Positioned(
          left: 24.px,
          right: 24.px,
          bottom: 4.px,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Let a swipe that starts on the headline still turn the page.
              IgnorePointer(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 400),
                  layoutBuilder: (current, previous) => Stack(
                    alignment: Alignment.bottomLeft,
                    children: [...previous, if (current != null) current],
                  ),
                  child: _buildHeadline(_slides[_index], key: ValueKey(_index)),
                ),
              ),
              SizedBox(height: 16.px),
              _buildDots(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeadline(_Slide slide, {Key? key}) {
    final style = TextStyle(
      fontSize: 33.px,
      height: 40 / 33,
      fontWeight: FontWeight.w700,
      color: Colors.white,
    );
    return Text.rich(
      TextSpan(
        style: style,
        children: [
          TextSpan(text: Localized.text(slide.lineKey1)),
          const TextSpan(text: '\n'),
          TextSpan(
            text: Localized.text(slide.lineKey2),
            style: const TextStyle(color: Color(0xFFC4B5FD)),
          ),
        ],
      ),
      key: key,
    );
  }

  Widget _buildDots() {
    return Row(
      children: [
        for (int i = 0; i < _slides.length; i++)
          Semantics(
            button: true,
            label: '${i + 1} / ${_slides.length}',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _goTo(i),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 3.px, vertical: 10.px),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: i == _index ? 22.px : 6.px,
                  height: 6.px,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: i == _index ? 1 : 0.35),
                    borderRadius: BorderRadius.circular(3.px),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
