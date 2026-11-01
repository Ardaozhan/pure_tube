import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

class UpdateInfo {
  final String version;
  final String tagName;
  final String releaseTitle;
  final String releaseNotes;
  final String apkUrl;
  final int apkSize;
  final DateTime? publishedAt;

  UpdateInfo({
    required this.version,
    required this.tagName,
    required this.releaseTitle,
    required this.releaseNotes,
    required this.apkUrl,
    required this.apkSize,
    this.publishedAt,
  });

  String get formattedSize {
    if (apkSize <= 0) return '';
    final mb = apkSize / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
  }
}

class UpdateService {
  // Mevcut uygulama sürümü
  static const String currentVersion = '3.0.2';
  static const int currentBuildNumber = 7;

  static const String repoOwner = 'Ardaozhan';
  static const String repoName = 'pure_tube';

  /// GitHub Releases API üzerinden en son sürümü kontrol eder
  static Future<UpdateInfo?> checkForUpdate() async {
    try {
      final url = Uri.parse(
        'https://api.github.com/repos/$repoOwner/$repoName/releases/latest',
      );

      final response = await http.get(
        url,
        headers: {
          'Accept': 'application/vnd.github.v3+json',
          'User-Agent': 'PureTube-App',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        debugPrint('[UpdateService] GitHub API status: ${response.statusCode}');
        return null;
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      final tagName = (data['tag_name'] as String? ?? '').trim();
      final cleanRemoteVersion = tagName.replaceAll(RegExp(r'^[vV]'), '');

      if (cleanRemoteVersion.isEmpty) return null;

      // Sürüm karşılaştırması (Örn: 1.0.1 > 1.0.0)
      if (!_isRemoteVersionNewer(cleanRemoteVersion, currentVersion)) {
        debugPrint('[UpdateService] Uygulama güncel ($currentVersion >= $cleanRemoteVersion)');
        return null;
      }

      // APK Asset'ini bul
      final assets = data['assets'] as List<dynamic>? ?? [];
      String? apkDownloadUrl;
      int apkSize = 0;

      for (final asset in assets) {
        final name = (asset['name'] as String? ?? '').toLowerCase();
        if (name.endsWith('.apk')) {
          apkDownloadUrl = asset['browser_download_url'] as String?;
          apkSize = (asset['size'] as num? ?? 0).toInt();
          break;
        }
      }

      if (apkDownloadUrl == null || apkDownloadUrl.isEmpty) {
        debugPrint('[UpdateService] Release bulundu fakat APK asset bulunamadı.');
        return null;
      }

      return UpdateInfo(
        version: cleanRemoteVersion,
        tagName: tagName,
        releaseTitle: data['name'] as String? ?? 'PureTube $tagName',
        releaseNotes: data['body'] as String? ?? 'Performans ve hata iyileştirmeleri.',
        apkUrl: apkDownloadUrl,
        apkSize: apkSize,
        publishedAt: data['published_at'] != null ? DateTime.tryParse(data['published_at']) : null,
      );
    } catch (e) {
      debugPrint('[UpdateService] Güncelleme kontrol hatası: $e');
      return null;
    }
  }

  /// Semver karşılaştırma
  static bool _isRemoteVersionNewer(String remote, String current) {
    try {
      final remoteParts = remote.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      final currentParts = current.split('.').map((e) => int.tryParse(e) ?? 0).toList();

      for (int i = 0; i < 3; i++) {
        final r = i < remoteParts.length ? remoteParts[i] : 0;
        final c = i < currentParts.length ? currentParts[i] : 0;
        if (r > c) return true;
        if (r < c) return false;
      }
      return false;
    } catch (_) {
      return remote != current;
    }
  }

  /// APK dosyasını indirir ve Android Paket Yükleyicisini tetikler
  static Future<bool> downloadAndInstall({
    required String apkUrl,
    required Function(double progress, String status) onProgress,
  }) async {
    final client = http.Client();
    IOSink? sink;
    try {
      final tempDir = await getTemporaryDirectory();
      final filePath = '${tempDir.path}/puretube_update.apk';
      final file = File(filePath);

      if (await file.exists()) {
        await file.delete();
      }

      onProgress(0.01, 'Başlanıyor...');

      final request = http.Request('GET', Uri.parse(apkUrl));
      request.headers['User-Agent'] = 'PureTube-App';
      final response = await client.send(request);

      if (response.statusCode != 200) {
        onProgress(0.0, 'İndirme sunucu hatası: ${response.statusCode}');
        return false;
      }

      final totalBytes = response.contentLength ?? 0;
      int receivedBytes = 0;
      sink = file.openWrite();

      await for (final chunk in response.stream) {
        sink.add(chunk);
        receivedBytes += chunk.length;

        if (totalBytes > 0) {
          final progress = (receivedBytes / totalBytes).clamp(0.0, 1.0);
          final mbReceived = (receivedBytes / (1024 * 1024)).toStringAsFixed(1);
          final mbTotal = (totalBytes / (1024 * 1024)).toStringAsFixed(1);
          onProgress(progress, '%${(progress * 100).toStringAsFixed(0)} ($mbReceived MB / $mbTotal MB)');
        } else {
          final mbReceived = (receivedBytes / (1024 * 1024)).toStringAsFixed(1);
          onProgress(0.5, '$mbReceived MB indirildi...');
        }
      }

      await sink.flush();
      await sink.close();
      sink = null;

      onProgress(1.0, 'İndirme tamamlandı! Kuruluma geçiliyor...');

      // Android Paket Yükleyiciyi aç
      final result = await OpenFilex.open(
        filePath,
        type: 'application/vnd.android.package-archive',
      );

      debugPrint('[UpdateService] OpenFilex result: ${result.type} - ${result.message}');
      return true;
    } catch (e) {
      debugPrint('[UpdateService] İndirme/kurulum hatası: $e');
      onProgress(0.0, 'Hata oluştu: $e');
      return false;
    } finally {
      await sink?.close();
      client.close();
    }
  }

  /// Uygulama açıldığında sessizce kontrol eder, güncelleme varsa diyaloğu açar
  static Future<void> checkOnStartup(BuildContext context) async {
    // 3 saniye gecikmeyle açılış takılmasını önle
    await Future.delayed(const Duration(seconds: 3));
    if (!context.mounted) return;

    final update = await checkForUpdate();
    if (update != null && context.mounted) {
      showUpdateDialog(context, update);
    }
  }

  /// Manuel veya otomatik güncelleme denetimi
  static Future<void> check(BuildContext context, {bool isManual = false}) async {
    final update = await checkForUpdate();
    if (!context.mounted) return;
    if (update != null) {
      showUpdateDialog(context, update);
    } else if (isManual) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🎉 Tebrikler! PureTube en güncel sürümde.'),
          duration: Duration(seconds: 2),
          backgroundColor: Color(0xFF2E7D32),
        ),
      );
    }
  }

  /// Güncelleme Diyaloğu
  static void showUpdateDialog(BuildContext context, UpdateInfo update) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _UpdateDialogWidget(update: update),
    );
  }
}

class _UpdateDialogWidget extends StatefulWidget {
  final UpdateInfo update;

  const _UpdateDialogWidget({required this.update});

  @override
  State<_UpdateDialogWidget> createState() => _UpdateDialogWidgetState();
}

class _UpdateDialogWidgetState extends State<_UpdateDialogWidget> {
  bool _isDownloading = false;
  double _progress = 0.0;
  String _statusText = '';
  String? _errorMessage;

  Future<void> _startDownload() async {
    setState(() {
      _isDownloading = true;
      _errorMessage = null;
      _statusText = 'İndirme başlatılıyor...';
    });

    final success = await UpdateService.downloadAndInstall(
      apkUrl: widget.update.apkUrl,
      onProgress: (p, s) {
        if (mounted) {
          setState(() {
            _progress = p;
            _statusText = s;
          });
        }
      },
    );

    if (!success && mounted) {
      setState(() {
        _isDownloading = false;
        _errorMessage = _statusText.isNotEmpty ? _statusText : 'İndirme başarısız oldu.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.redAccent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.system_update_rounded, color: Colors.redAccent, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Yeni Sürüm Mevcut!',
                  style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                ),
                Text(
                  'v${UpdateService.currentVersion}  ->  v${widget.update.version}',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.update.formattedSize.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Boyut: ${widget.update.formattedSize}',
                style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),

          // Yenilikler Kartı
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: 140),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white10),
            ),
            child: SingleChildScrollView(
              child: Text(
                widget.update.releaseNotes.trim(),
                style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
              ),
            ),
          ),

          if (_isDownloading) ...[
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: _progress > 0 ? _progress : null,
              backgroundColor: Colors.white10,
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.redAccent),
              minHeight: 6,
              borderRadius: BorderRadius.circular(3),
            ),
            const SizedBox(height: 8),
            Text(
              _statusText,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],

          if (_errorMessage != null) ...[
            const SizedBox(height: 12),
            Text(
              _errorMessage!,
              style: const TextStyle(color: Colors.redAccent, fontSize: 12),
            ),
          ],
        ],
      ),
      actions: [
        if (!_isDownloading)
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Daha Sonra', style: TextStyle(color: Colors.white38)),
          ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.redAccent,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: _isDownloading ? null : _startDownload,
          child: Text(_isDownloading ? 'İndiriliyor...' : 'Şimdi Güncelle'),
        ),
      ],
    );
  }
}
