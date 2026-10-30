import 'package:flutter/services.dart';

class MediaNotificationService {
  static const MethodChannel _channel = MethodChannel('com.puretube/media');
  static void Function(String source, String action, int? positionMs)? onAction;

  static void initialize() {
    _channel.setMethodCallHandler((call) async {
      final source = (call.arguments is Map) ? (call.arguments['source'] as String? ?? 'youtube') : 'youtube';
      final positionMs = (call.arguments is Map) ? (call.arguments['positionMs'] as num?)?.toInt() : null;
      onAction?.call(source, call.method, positionMs);
    });
  }

  static Future<void> updateMetadata({
    required String source,
    required String title,
    required String artist,
    String? artwork,
    required bool isPlaying,
    required int positionMs,
    required int durationMs,
  }) async {
    try {
      await _channel.invokeMethod('updateMediaMetadata', {
        'source': source,
        'title': title,
        'artist': artist,
        'artwork': artwork ?? '',
        'isPlaying': isPlaying,
        'positionMs': positionMs,
        'durationMs': durationMs,
      });
    } catch (_) {}
  }

  static Future<void> clear({String source = 'all'}) async {
    try {
      await _channel.invokeMethod('clearMediaNotification', {
        'source': source,
      });
    } catch (_) {}
  }
}
