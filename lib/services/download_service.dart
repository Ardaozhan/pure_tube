import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class DownloadOption {
  final String title;
  final String qualityLabel;
  final String format;
  final int sizeInBytes;
  final StreamInfo streamInfo;
  final bool isAudioOnly;

  DownloadOption({
    required this.title,
    required this.qualityLabel,
    required this.format,
    required this.sizeInBytes,
    required this.streamInfo,
    required this.isAudioOnly,
  });

  String get formattedSize {
    if (sizeInBytes <= 0) return '';
    final mb = sizeInBytes / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
  }
}

class DownloadVideoDetails {
  final String id;
  final String title;
  final String author;
  final Duration? duration;
  final String thumbnailUrl;
  final List<DownloadOption> options;

  DownloadVideoDetails({
    required this.id,
    required this.title,
    required this.author,
    required this.duration,
    required this.thumbnailUrl,
    required this.options,
  });
}

class DownloadService {
  static final YoutubeExplode _yt = YoutubeExplode();

  /// Fetches video info and available quality stream options
  static Future<DownloadVideoDetails?> fetchVideoDetails(String videoId) async {
    try {
      final video = await _yt.videos.get(videoId);
      final manifest = await _yt.videos.streamsClient.getManifest(videoId);

      final List<DownloadOption> options = [];

      // 1. Muxed Video Streams (Video + Audio combined - Best for direct mobile playback)
      final muxedStreams = manifest.muxed.sortByVideoQuality();
      for (final stream in muxedStreams) {
        options.add(
          DownloadOption(
            title: video.title,
            qualityLabel: stream.qualityLabel,
            format: stream.container.name.toUpperCase(),
            sizeInBytes: stream.size.totalBytes,
            streamInfo: stream,
            isAudioOnly: false,
          ),
        );
      }

      // 2. High Quality Audio Streams
      final audioStreams = manifest.audioOnly.sortByBitrate();
      if (audioStreams.isNotEmpty) {
        final bestAudio = audioStreams.last;
        options.add(
          DownloadOption(
            title: video.title,
            qualityLabel: '${bestAudio.bitrate.kiloBitsPerSecond.round()} kbps (Müzik)',
            format: bestAudio.container.name.toUpperCase(),
            sizeInBytes: bestAudio.size.totalBytes,
            streamInfo: bestAudio,
            isAudioOnly: true,
          ),
        );
      }

      return DownloadVideoDetails(
        id: video.id.value,
        title: video.title,
        author: video.author,
        duration: video.duration,
        thumbnailUrl: video.thumbnails.highResUrl,
        options: options,
      );
    } catch (e) {
      debugPrint('[DownloadService] Error fetching details: $e');
      return null;
    }
  }

  /// Downloads selected stream to device storage
  static Future<File?> downloadStream({
    required DownloadOption option,
    required Function(double progress, String status) onProgress,
  }) async {
    try {
      // Permission check
      if (Platform.isAndroid) {
        await [
          Permission.storage,
          Permission.videos,
          Permission.audio,
        ].request();
      }

      // Determine destination directory
      Directory? baseDir;
      if (Platform.isAndroid) {
        final downloadDir = Directory('/storage/emulated/0/Download/PureTube');
        if (!await downloadDir.exists()) {
          try {
            await downloadDir.create(recursive: true);
            baseDir = downloadDir;
          } catch (_) {}
        } else {
          baseDir = downloadDir;
        }
      }

      baseDir ??= await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();

      // Clean file name
      final cleanTitle = option.title
          .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
          .trim();
      final ext = option.streamInfo.container.name;
      final filePath = '${baseDir.path}/${cleanTitle}_${option.qualityLabel}.$ext';
      final file = File(filePath);

      if (await file.exists()) {
        await file.delete();
      }

      final stream = _yt.videos.streamsClient.get(option.streamInfo);
      final output = file.openWrite();

      int received = 0;
      final total = option.sizeInBytes;

      await for (final data in stream) {
        received += data.length;
        output.add(data);
        if (total > 0) {
          final progress = (received / total).clamp(0.0, 1.0);
          onProgress(progress, '${(progress * 100).toStringAsFixed(0)}% (${(received / (1024 * 1024)).toStringAsFixed(1)} MB)');
        } else {
          onProgress(0.5, '${(received / (1024 * 1024)).toStringAsFixed(1)} MB');
        }
      }

      await output.flush();
      await output.close();

      onProgress(1.0, 'İndirme tamamlandı: $filePath');
      return file;
    } catch (e) {
      debugPrint('[DownloadService] Download error: $e');
      onProgress(0.0, 'İndirme hatası: $e');
      return null;
    }
  }
}
