import 'dart:async';
import 'package:flutter/material.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:volume_controller/volume_controller.dart';

enum GestureIndicatorType { brightness, volume, seek }

class GestureOverlay extends StatefulWidget {
  final Widget child;
  final bool enabled;
  final Function(int seconds)? onSeek;

  const GestureOverlay({
    super.key,
    required this.child,
    this.enabled = true,
    this.onSeek,
  });

  @override
  State<GestureOverlay> createState() => _GestureOverlayState();
}

class _GestureOverlayState extends State<GestureOverlay> {
  double? _currentVolume;
  double? _currentBrightness;

  GestureIndicatorType? _activeIndicator;
  double _indicatorValue = 0.0;
  String _indicatorText = '';
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    _initValues();
  }

  Future<void> _initValues() async {
    try {
      _currentBrightness = await ScreenBrightness.instance.application;
    } catch (_) {
      _currentBrightness = 0.5;
    }

    try {
      _currentVolume = await VolumeController.instance.getVolume();
      VolumeController.instance.addListener((vol) {
        _currentVolume = vol;
      });
    } catch (_) {
      _currentVolume = 0.5;
    }
  }

  void _showIndicator(GestureIndicatorType type, double value, String text) {
    _hideTimer?.cancel();
    setState(() {
      _activeIndicator = type;
      _indicatorValue = value.clamp(0.0, 1.0);
      _indicatorText = text;
    });

    _hideTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) {
        setState(() {
          _activeIndicator = null;
        });
      }
    });
  }

  void _handleVerticalDragUpdate(DragUpdateDetails details, BoxConstraints constraints) {
    if (!widget.enabled) return;

    final screenWidth = constraints.maxWidth;
    final screenHeight = constraints.maxHeight;
    final delta = -details.primaryDelta! / screenHeight; // Invert delta: upward drag increases

    final isLeft = details.globalPosition.dx < screenWidth / 2;

    if (isLeft) {
      // Left side: Brightness
      double newBrightness = (_currentBrightness ?? 0.5) + delta;
      newBrightness = newBrightness.clamp(0.0, 1.0);
      _currentBrightness = newBrightness;
      try {
        ScreenBrightness.instance.setApplicationScreenBrightness(newBrightness);
      } catch (_) {}
      _showIndicator(
        GestureIndicatorType.brightness,
        newBrightness,
        '${(newBrightness * 100).round()}%',
      );
    } else {
      // Right side: Volume
      double newVolume = (_currentVolume ?? 0.5) + delta;
      newVolume = newVolume.clamp(0.0, 1.0);
      _currentVolume = newVolume;
      try {
        VolumeController.instance.setVolume(newVolume);
      } catch (_) {}
      _showIndicator(
        GestureIndicatorType.volume,
        newVolume,
        '${(newVolume * 100).round()}%',
      );
    }
  }

  double _accumulatedSeekSeconds = 0.0;

  void _handleHorizontalDragStart(DragStartDetails details) {
    if (!widget.enabled) return;
    _accumulatedSeekSeconds = 0.0;
  }

  void _handleHorizontalDragUpdate(DragUpdateDetails details, BoxConstraints constraints) {
    if (!widget.enabled) return;
    final screenWidth = constraints.maxWidth;
    if (screenWidth <= 0) return;
    final delta = details.primaryDelta ?? 0.0;
    // Map horizontal movement across the screen to ~90 seconds of video seeking
    final deltaSec = (delta / screenWidth) * 90.0;
    _accumulatedSeekSeconds += deltaSec;

    final rounded = _accumulatedSeekSeconds.round();
    final sign = rounded > 0 ? '+' : '';
    _showIndicator(
      GestureIndicatorType.seek,
      0.5,
      '$sign$rounded sn',
    );
  }

  void _handleHorizontalDragEnd(DragEndDetails details) {
    if (!widget.enabled || widget.onSeek == null) return;
    final rounded = _accumulatedSeekSeconds.round();
    if (rounded.abs() >= 1) {
      widget.onSeek!(rounded);
    }
  }

  void _handleDoubleTapDown(TapDownDetails details, BoxConstraints constraints) {
    if (!widget.enabled || widget.onSeek == null) return;
    final screenWidth = constraints.maxWidth;
    final isLeft = details.globalPosition.dx < screenWidth / 2;

    if (isLeft) {
      widget.onSeek!(-10);
      _showIndicator(GestureIndicatorType.seek, 0.3, '-10 sn');
    } else {
      widget.onSeek!(10);
      _showIndicator(GestureIndicatorType.seek, 0.7, '+10 sn');
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    VolumeController.instance.removeListener();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          children: [
            widget.child,
            // Transparent gesture detection overlay on top of video when enabled
            if (widget.enabled)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onVerticalDragUpdate: (details) => _handleVerticalDragUpdate(details, constraints),
                  onHorizontalDragStart: _handleHorizontalDragStart,
                  onHorizontalDragUpdate: (details) => _handleHorizontalDragUpdate(details, constraints),
                  onHorizontalDragEnd: _handleHorizontalDragEnd,
                  onDoubleTapDown: (details) => _handleDoubleTapDown(details, constraints),
                ),
              ),
            // Floating HUD Indicator
            if (_activeIndicator != null)
              Center(
                child: AnimatedOpacity(
                  opacity: _activeIndicator != null ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white24, width: 1),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _activeIndicator == GestureIndicatorType.brightness
                              ? (_indicatorValue > 0.5 ? Icons.brightness_high : Icons.brightness_low)
                              : _activeIndicator == GestureIndicatorType.volume
                                  ? (_indicatorValue == 0 ? Icons.volume_off : Icons.volume_up)
                                  : (_indicatorText.startsWith('-') ? Icons.fast_rewind : Icons.fast_forward),
                          color: Colors.white,
                          size: 38,
                        ),
                        const SizedBox(height: 8),
                        if (_activeIndicator != GestureIndicatorType.seek)
                          SizedBox(
                            width: 100,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: _indicatorValue,
                                backgroundColor: Colors.white24,
                                valueColor: const AlwaysStoppedAnimation<Color>(Colors.redAccent),
                                minHeight: 6,
                              ),
                            ),
                          ),
                        const SizedBox(height: 6),
                        Text(
                          _indicatorText,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
