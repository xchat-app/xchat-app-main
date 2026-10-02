import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:ox_call/ox_call.dart';
import 'package:ox_call/src/models/call_session.dart';
import 'package:ox_call/src/services/call_service.dart';
import 'package:ox_call/src/utils/call_logger.dart';
import 'widgets/call_page_controller.dart';
import 'widgets/call_top_bar.dart';
import 'widgets/call_content_area.dart';
import 'widgets/call_control_bar.dart';

/// Main call page that displays during an active call.
///
/// This page is a pure UI container that:
/// - Doesn't care whether it's a voice or video call
/// - Doesn't handle any business logic directly
/// - Delegates all state management to [CallPageController]
/// - Composes [CallTopBar], [CallContentArea], and [CallControlBar]
class CallPage extends StatefulWidget {
  final CallSession session;

  const CallPage({
    super.key,
    required this.session,
  });

  @override
  State<CallPage> createState() => _CallPageState();
}

class _CallPageState extends State<CallPage> {
  late final CallPageController _controller;

  @override
  void initState() {
    super.initState();
    _controller = CallPageController(widget.session, context);
    _controller.hasPopped$.addListener(_onHasPopped);
    _setKeepScreenOn(true);

    // For incoming calls: check permission after first frame is rendered
    if (widget.session.isIncoming) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _controller.checkPermissionAndGetLocalStreamForIncoming();
        }
      });
    }
  }

  void _onHasPopped() {
    if (_controller.hasPopped$.value && mounted) {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          Navigator.of(context).pop();
        }
      });
    }
  }

  /// Nobody touches the screen during a video call, so Android's screen
  /// timeout blanked it mid-call and it looked as if the call had dropped.
  /// Voice calls are left alone: that phone is held to the ear.
  void _setKeepScreenOn(bool on) {
    if (!widget.session.isVideo) return;
    (on ? WakelockPlus.enable() : WakelockPlus.disable()).catchError((Object e) {
      CallLogger.warning('Failed to ${on ? 'keep the screen on' : 'release the screen'}', e);
    });
  }

  void _onMinimize() {
    // TODO: Implement minimize to PiP
  }

  @override
  void dispose() {
    _controller.hasPopped$.removeListener(_onHasPopped);
    _setKeepScreenOn(false);
    _controller.dispose();
    // Notify CallService that call page is dismissed
    CallService.instance.notifyCallPageDismissed();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ValueListenableBuilder<bool>(
        valueListenable: _controller.isControlsVisible$,
        builder: (context, isControlsVisible, _) {
          return Stack(
            children: [
              // Content area (voice/video)
              Positioned.fill(
                child: CallContentArea(controller: _controller),
              ),

              // Top bar (with fade animation for video calls)
              AnimatedPositioned(
                duration: const Duration(milliseconds: 200),
                top: isControlsVisible ? 0 : -100,
                left: 0,
                right: 0,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: isControlsVisible ? 1.0 : 0.0,
                  child: CallTopBar(
                    controller: _controller,
                    onMinimize: _onMinimize,
                  ),
                ),
              ),

              // Control bar (with fade animation for video calls)
              AnimatedPositioned(
                duration: const Duration(milliseconds: 200),
                bottom: isControlsVisible ? 0 : -200,
                left: 0,
                right: 0,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: isControlsVisible ? 1.0 : 0.0,
                  child: CallControlBar(controller: _controller),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}