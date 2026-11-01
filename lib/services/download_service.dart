import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// Pure Dart ID3v2.3 Metadata Tagger.
/// Writes standard ID3v2.3 tags (TIT2 title, TPE1 artist, TALB album,
/// USLT lyrics, APIC cover art) to MP3 and audio streams without external native dependencies.
class Id3v2Tagger {
  /// Encodes an integer into a 4-byte 28-bit syncsafe integer.
  static List<int> _encodeSyncsafe(int value) {
    return [
      (value >> 21) & 0x7F,
      (value >> 14) & 0x7F,
      (value >> 7) & 0x7F,
      value & 0x7F,
    ];
  }

  /// Decodes a 4-byte syncsafe integer from a byte list at the given offset.
  static int _decodeSyncsafe(List<int> bytes, int offset) {
    return ((bytes[offset] & 0x7F) << 21) |
        ((bytes[offset + 1] & 0x7F) << 14) |
        ((bytes[offset + 2] & 0x7F) << 7) |
        (bytes[offset + 3] & 0x7F);
  }

  /// Encodes an integer into a 4-byte 32-bit big-endian integer.
  static List<int> _encodeUint32BigEndian(int value) {
    return [
      (value >> 24) & 0xFF,
      (value >> 16) & 0xFF,
      (value >> 8) & 0xFF,
      value & 0xFF,
    ];
  }

  /// Builds a text frame (TIT2, TPE1, TALB) using UTF-16 with Byte Order Mark (LE).
  static List<int> buildTextFrame(String frameId, String text) {
    final frameData = <int>[];
    // 0x01 = UTF-16 encoding with BOM
    frameData.add(0x01);
    // BOM UTF-16 LE: 0xFF, 0xFE
    frameData.add(0xFF);
    frameData.add(0xFE);
    for (final unit in text.codeUnits) {
      frameData.add(unit & 0xFF);
      frameData.add((unit >> 8) & 0xFF);
    }

    final header = <int>[];
    header.addAll(ascii.encode(frameId)); // 4 bytes Frame ID
    header.addAll(_encodeUint32BigEndian(frameData.length)); // 4 bytes Size
    header.addAll([0x00, 0x00]); // 2 bytes Flags

    return [...header, ...frameData];
  }

  /// Builds an unsynchronised lyrics frame (USLT).
  static List<int> buildLyricsFrame(String lyrics, {String lang = 'eng'}) {
    final frameData = <int>[];
    // 0x01 = UTF-16 with BOM
    frameData.add(0x01);
    // 3 bytes ISO-639-2 language code
    final normalizedLang = (lang.length >= 3 ? lang.substring(0, 3) : 'eng').toLowerCase();
    frameData.addAll(ascii.encode(normalizedLang));
    // Content descriptor (empty string in UTF-16 with BOM and double-null terminator)
    frameData.addAll([0xFF, 0xFE, 0x00, 0x00]);
    // Lyrics text with BOM
    frameData.addAll([0xFF, 0xFE]);
    for (final unit in lyrics.codeUnits) {
      frameData.add(unit & 0xFF);
      frameData.add((unit >> 8) & 0xFF);
    }

    final header = <int>[];
    header.addAll(ascii.encode('USLT'));
    header.addAll(_encodeUint32BigEndian(frameData.length));
    header.addAll([0x00, 0x00]);

    return [...header, ...frameData];
  }

  /// Builds an attached picture frame (APIC) for album cover art.
  static List<int> buildPictureFrame(List<int> imageBytes, {String mimeType = 'image/jpeg'}) {
    final frameData = <int>[];
    // 0x00 = ISO-8859-1 for MIME and description
    frameData.add(0x00);
    // MIME type null-terminated ASCII
    frameData.addAll(ascii.encode(mimeType));
    frameData.add(0x00);
    // Picture type: 0x03 = Front Cover
    frameData.add(0x03);
    // Description null-terminated
    frameData.add(0x00);
    // Image binary data
    frameData.addAll(imageBytes);

    final header = <int>[];
    header.addAll(ascii.encode('APIC'));
    header.addAll(_encodeUint32BigEndian(frameData.length));
    header.addAll([0x00, 0x00]);

    return [...header, ...frameData];
  }

  /// Constructs the complete ID3v2.3 tag byte array.
  static List<int> buildId3Tag({
    required String title,
    String? artist,
    String? album,
    String? lyrics,
    List<int>? coverImageBytes,
    String mimeType = 'image/jpeg',
  }) {
    final frames = <int>[];

    // 1. TIT2 - Title
    if (title.isNotEmpty) {
      frames.addAll(buildTextFrame('TIT2', title));
    }
    // 2. TPE1 - Lead Artist / Channel
    if (artist != null && artist.isNotEmpty) {
      frames.addAll(buildTextFrame('TPE1', artist));
    }
    // 3. TALB - Album
    if (album != null && album.isNotEmpty) {
      frames.addAll(buildTextFrame('TALB', album));
    }
    // 4. USLT - Lyrics
    if (lyrics != null && lyrics.isNotEmpty) {
      frames.addAll(buildLyricsFrame(lyrics));
    }
    // 5. APIC - Cover Art
    if (coverImageBytes != null && coverImageBytes.isNotEmpty) {
      frames.addAll(buildPictureFrame(coverImageBytes, mimeType: mimeType));
    }

    final tagHeader = <int>[];
    tagHeader.addAll(ascii.encode('ID3')); // 3 bytes Identifier
    tagHeader.add(0x03); // Major version (ID3v2.3)
    tagHeader.add(0x00); // Revision
    tagHeader.add(0x00); // Flags
    tagHeader.addAll(_encodeSyncsafe(frames.length)); // 4 bytes Syncsafe Tag Size

    return [...tagHeader, ...frames];
  }

  /// Injects ID3v2.3 tags directly into an audio file.
  static Future<void> tagFile({
    required File file,
    required String title,
    String? artist,
    String? album,
    String? lyrics,
    List<int>? coverImageBytes,
  }) async {
    if (!await file.exists()) return;

    // Do not prepend ID3v2 headers to WebM, M4A or MP4 containers
    final filePathLower = file.path.toLowerCase();
    if (!filePathLower.endsWith('.mp3')) {
      debugPrint('[Id3v2Tagger] Skipping ID3v2 tag: file is not an MP3 container ($filePathLower)');
      return;
    }

    final isPng = coverImageBytes != null &&
        coverImageBytes.length > 8 &&
        coverImageBytes[0] == 0x89 &&
        coverImageBytes[1] == 0x50;

    final tagBytes = buildId3Tag(
      title: title,
      artist: artist,
      album: album,
      lyrics: lyrics,
      coverImageBytes: coverImageBytes,
      mimeType: isPng ? 'image/png' : 'image/jpeg',
    );

    final rawBytes = await file.readAsBytes();
    int audioOffset = 0;

    // Check if file already begins with an ID3 tag
    if (rawBytes.length >= 10 &&
        rawBytes[0] == 0x49 && // 'I'
        rawBytes[1] == 0x44 && // 'D'
        rawBytes[2] == 0x33) { // '3'
      final existingSize = _decodeSyncsafe(rawBytes, 6);
      audioOffset = 10 + existingSize;
      if (audioOffset > rawBytes.length) {
        audioOffset = 0; // Fallback if corrupt
      }
    }

    IOSink? sink;
    try {
      sink = file.openWrite();
      sink.add(tagBytes);
      if (audioOffset > 0) {
        sink.add(rawBytes.sublist(audioOffset));
      } else {
        sink.add(rawBytes);
      }
      await sink.flush();
    } finally {
      await sink?.close();
    }
  }

  /// Downloads cover art from thumbnail URL and tags the audio file.
  static Future<void> tagFileWithThumbnailUrl({
    required File file,
    required String title,
    String? artist,
    String? album,
    String? lyrics,
    String? thumbnailUrl,
  }) async {
    if (!file.path.toLowerCase().endsWith('.mp3')) return;
    List<int>? coverBytes;
    if (thumbnailUrl != null && thumbnailUrl.isNotEmpty) {
      try {
        final resp = await http.get(Uri.parse(thumbnailUrl)).timeout(const Duration(seconds: 8));
        if (resp.statusCode == 200) {
          coverBytes = resp.bodyBytes;
        }
      } catch (e) {
        debugPrint('[Id3v2Tagger] Failed to download thumbnail for cover art: $e');
      }
    }

    await tagFile(
      file: file,
      title: title,
      artist: artist,
      album: album,
      lyrics: lyrics,
      coverImageBytes: coverBytes,
    );
  }
}

/// Download options with stream specifications and rich metadata.
class DownloadOption {
  final String title;
  final String qualityLabel;
  final String format;
  final int sizeInBytes;
  final StreamInfo streamInfo;
  final bool isAudioOnly;
  final String? videoId;
  final String? author;
  final String? thumbnailUrl;
  final String? lyrics;

  DownloadOption({
    required this.title,
    required this.qualityLabel,
    required this.format,
    required this.sizeInBytes,
    required this.streamInfo,
    required this.isAudioOnly,
    this.videoId,
    this.author,
    this.thumbnailUrl,
    this.lyrics,
  });

  String get formattedSize {
    if (sizeInBytes <= 0) return '';
    final mb = sizeInBytes / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
  }
}

/// Details of a video and all available stream quality options.
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

/// High-performance Download Service for PureTube.
/// Features multi-threaded chunk downloading with automatic failover to YoutubeExplode streaming,
/// plus automatic ID3v2.3 metadata tagging for audio tracks.
class DownloadService {
  static final YoutubeExplode _yt = YoutubeExplode();

  /// Fetches video details and stream manifests.
  static Future<DownloadVideoDetails?> fetchVideoDetails(String videoId) async {
    try {
      final video = await _yt.videos.get(videoId);
      final manifest = await _yt.videos.streamsClient.getManifest(videoId);

      final List<DownloadOption> options = [];

      // 1. Muxed Video Streams (Video + Audio combined)
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
            videoId: video.id.value,
            author: video.author,
            thumbnailUrl: video.thumbnails.highResUrl,
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
            videoId: video.id.value,
            author: video.author,
            thumbnailUrl: video.thumbnails.highResUrl,
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

  /// Downloads the stream using multi-threaded chunks when possible,
  /// falling back gracefully to single-stream downloading, and tags audio files with ID3v2.3.
  static Future<File?> downloadStream({
    required DownloadOption option,
    required Function(double progress, String status) onProgress,
  }) async {
    try {
      // 1. Storage Permissions Check
      if (Platform.isAndroid) {
        await [
          Permission.storage,
          Permission.videos,
          Permission.audio,
        ].request();
      }

      // 2. Determine Destination Directory
      Directory? baseDir;
      if (Platform.isAndroid) {
        final downloadDir = Directory('/storage/emulated/0/Download/PureTube');
        try {
          if (!await downloadDir.exists()) {
            await downloadDir.create(recursive: true);
          }
          // Validate write permissions under Scoped Storage (Android 11+)
          final testFile = File('${downloadDir.path}/.access_test_${DateTime.now().millisecondsSinceEpoch}');
          await testFile.writeAsString('test');
          if (await testFile.exists()) {
            await testFile.delete();
          }
          baseDir = downloadDir;
        } catch (_) {
          // Android 11+ Scoped Storage restriction without MANAGE_EXTERNAL_STORAGE:
          // Fall back to app-specific external storage where writes always succeed
          baseDir = null;
        }
      }

      baseDir ??= await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();

      // Clean file name
      final cleanTitle = option.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
      final ext = option.streamInfo.container.name;
      final filePath = '${baseDir.path}/${cleanTitle}_${option.qualityLabel}.$ext';
      final file = File(filePath);

      if (await file.exists()) {
        await file.delete();
      }

      bool success = false;

      // 3. Multi-Threaded Chunk Downloading (For files larger than 3MB)
      final totalBytes = option.sizeInBytes;
      if (totalBytes > 3 * 1024 * 1024) {
        try {
          success = await _downloadMultiThreaded(
            url: option.streamInfo.url,
            destinationFile: file,
            totalBytes: totalBytes,
            onProgress: onProgress,
          );
        } catch (chunkErr) {
          debugPrint('[DownloadService] Multi-threaded download exception: $chunkErr. Falling back to resilient stream.');
          success = false;
        }
      }

      // 4. Resilient Fallback via YoutubeExplode Stream Client
      if (!success) {
        onProgress(0.05, 'Bağlantı kuruluyor (Akış İndirme)...');
        await _downloadResilientStream(
          streamInfo: option.streamInfo,
          destinationFile: file,
          totalBytes: totalBytes,
          onProgress: onProgress,
        );
      }

      // 5. Automatic ID3v2.3 Tagging for Audio Tracks (Only for MP3 containers)
      final isMp3Container = ext.toLowerCase() == 'mp3';
      if (option.isAudioOnly && isMp3Container && await file.exists()) {
        onProgress(0.98, 'Müzik etiketleri (ID3v2) ve kapak resmi işleniyor...');
        try {
          await Id3v2Tagger.tagFileWithThumbnailUrl(
            file: file,
            title: option.title,
            artist: option.author ?? 'PureTube Audio',
            album: 'PureTube Müzik',
            thumbnailUrl: option.thumbnailUrl,
            lyrics: option.lyrics,
          );
        } catch (tagErr) {
          debugPrint('[DownloadService] ID3 tagging failed: $tagErr');
        }
      }

      // Verify destination file exists and is not empty
      if (!await file.exists() || await file.length() == 0) {
        try {
          if (await file.exists()) await file.delete();
        } catch (_) {}
        debugPrint('[DownloadService] Download produced an empty or missing file: $filePath');
        onProgress(0.0, 'İndirme tamamlanamadı (boş dosya).');
        return null;
      }

      onProgress(1.0, 'İndirme tamamlandı: $filePath');
      return file;
    } catch (e) {
      debugPrint('[DownloadService] Download error: $e');
      onProgress(0.0, 'İndirme hatası: $e');
      return null;
    }
  }

  /// Downloads the file in parallel chunks using HTTP Range requests.
  static Future<bool> _downloadMultiThreaded({
    required Uri url,
    required File destinationFile,
    required int totalBytes,
    required Function(double progress, String status) onProgress,
  }) async {
    const threadCount = 4;
    final chunkSize = (totalBytes / threadCount).ceil();
    final List<File> partFiles = [];
    final List<int> receivedPerThread = List.filled(threadCount, 0);

    for (int i = 0; i < threadCount; i++) {
      partFiles.add(File('${destinationFile.path}.part$i'));
    }

    try {
      final futures = <Future<bool>>[];

      for (int i = 0; i < threadCount; i++) {
        final start = i * chunkSize;
        final end = (i == threadCount - 1) ? totalBytes - 1 : (start + chunkSize - 1);
        final partFile = partFiles[i];

        futures.add(
          _downloadChunk(
            url: url,
            start: start,
            end: end,
            outputFile: partFile,
            onBytesReceived: (bytesCount) {
              receivedPerThread[i] = bytesCount;
              final totalReceived = receivedPerThread.fold(0, (a, b) => a + b);
              final progress = (totalReceived / totalBytes).clamp(0.0, 0.95);
              final mbReceived = (totalReceived / (1024 * 1024)).toStringAsFixed(1);
              final mbTotal = (totalBytes / (1024 * 1024)).toStringAsFixed(1);
              onProgress(progress, '${(progress * 100).toStringAsFixed(0)}% (Multi-Thread: $mbReceived / $mbTotal MB)');
            },
          ),
        );
      }

      final results = await Future.wait(futures);
      final allSucceeded = results.every((res) => res == true);

      if (!allSucceeded) {
        _cleanupPartFiles(partFiles);
        return false;
      }

      // Merge chunks sequentially into destination file
      onProgress(0.96, 'Parçalar birleştiriliyor...');
      IOSink? outputSink;
      try {
        outputSink = destinationFile.openWrite();
        for (final part in partFiles) {
          await outputSink.addStream(part.openRead());
        }
        await outputSink.flush();
      } finally {
        await outputSink?.close();
      }

      _cleanupPartFiles(partFiles);
      return true;
    } catch (e) {
      debugPrint('[DownloadService] Error in multi-threaded chunk: $e');
      _cleanupPartFiles(partFiles);
      return false;
    }
  }

  /// Downloads an individual HTTP range chunk.
  static Future<bool> _downloadChunk({
    required Uri url,
    required int start,
    required int end,
    required File outputFile,
    required Function(int receivedBytes) onBytesReceived,
  }) async {
    final client = http.Client();
    IOSink? sink;
    try {
      final request = http.Request('GET', url);
      request.headers['Range'] = 'bytes=$start-$end';
      request.headers['User-Agent'] = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36';

      final response = await client.send(request);

      // Status 206 Partial Content is required for range requests
      if (response.statusCode != 206) {
        return false;
      }

      if (await outputFile.exists()) {
        await outputFile.delete();
      }

      sink = outputFile.openWrite();
      int received = 0;

      await for (final data in response.stream) {
        sink.add(data);
        received += data.length;
        onBytesReceived(received);
      }

      await sink.flush();
      return true;
    } catch (_) {
      return false;
    } finally {
      await sink?.close();
      client.close();
    }
  }

  /// Resilient single-stream downloader via YoutubeExplode stream client.
  static Future<void> _downloadResilientStream({
    required StreamInfo streamInfo,
    required File destinationFile,
    required int totalBytes,
    required Function(double progress, String status) onProgress,
  }) async {
    final stream = _yt.videos.streamsClient.get(streamInfo);
    IOSink? output;
    try {
      output = destinationFile.openWrite();
      int received = 0;

      await for (final data in stream) {
        received += data.length;
        output.add(data);
        if (totalBytes > 0) {
          final progress = (received / totalBytes).clamp(0.0, 0.95);
          final mb = (received / (1024 * 1024)).toStringAsFixed(1);
          final totalMb = (totalBytes / (1024 * 1024)).toStringAsFixed(1);
          onProgress(progress, '${(progress * 100).toStringAsFixed(0)}% ($mb / $totalMb MB)');
        } else {
          onProgress(0.5, '${(received / (1024 * 1024)).toStringAsFixed(1)} MB');
        }
      }

      await output.flush();
    } finally {
      await output?.close();
    }
  }

  static void _cleanupPartFiles(List<File> partFiles) {
    for (final file in partFiles) {
      if (file.existsSync()) {
        try {
          file.deleteSync();
        } catch (_) {}
      }
    }
  }
}
