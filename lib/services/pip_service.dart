import 'package:flutter/services.dart';

class PipService {
  static const MethodChannel _channel = MethodChannel('com.puretube/pip');
  static Function(bool isInPip)? onPipModeChanged;

  static void initialize() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onPipChanged') {
        final isInPip = call.arguments as bool? ?? false;
        onPipModeChanged?.call(isInPip);
      }
    });
  }

  static Future<bool> isPipSupported() async {
    try {
      final supported = await _channel.invokeMethod<bool>('isPipSupported');
      return supported ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> enterPip() async {
    try {
      final res = await _channel.invokeMethod<bool>('enterPip');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> setAutoPip(bool enabled) async {
    try {
      await _channel.invokeMethod('setAutoPip', {'enabled': enabled});
    } catch (_) {}
  }
}
