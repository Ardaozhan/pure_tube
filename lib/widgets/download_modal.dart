import 'package:flutter/material.dart';
import '../services/download_service.dart';

class DownloadModal extends StatefulWidget {
  final String videoId;

  const DownloadModal({super.key, required this.videoId});

  @override
  State<DownloadModal> createState() => _DownloadModalState();
}

class _DownloadModalState extends State<DownloadModal> {
  DownloadVideoDetails? _details;
  bool _isLoading = true;
  String? _errorMessage;

  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  String _downloadStatus = '';

  @override
  void initState() {
    super.initState();
    _fetchDetails();
  }

  Future<void> _fetchDetails() async {
    final details = await DownloadService.fetchVideoDetails(widget.videoId);
    if (mounted) {
      setState(() {
        _isLoading = false;
        if (details != null) {
          _details = details;
        } else {
          _errorMessage = 'Video akış bilgileri alınamadı. Lütfen videonun açık olduğundan emin olun.';
        }
      });
    }
  }

  Future<void> _startDownload(DownloadOption option) async {
    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
      _downloadStatus = 'İndirme başlatılıyor...';
    });

    final file = await DownloadService.downloadStream(
      option: option,
      onProgress: (progress, status) {
        if (mounted) {
          setState(() {
            _downloadProgress = progress;
            _downloadStatus = status;
          });
        }
      },
    );

    if (mounted) {
      if (file != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Dosya Downloads/PureTube klasörüne kaydedildi: ${file.path.split('/').last}'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 4),
          ),
        );
        Navigator.pop(context);
      } else {
        setState(() {
          _isDownloading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E1E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.download_rounded, color: Colors.redAccent, size: 28),
                const SizedBox(width: 10),
                const Text(
                  'Video / Müzik İndir',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white70),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 14),

            if (_isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 36),
                  child: Column(
                    children: [
                      CircularProgressIndicator(color: Colors.redAccent),
                      SizedBox(height: 12),
                      Text('Video kaliteleri ve formatları taranıyor...', style: TextStyle(color: Colors.white70)),
                    ],
                  ),
                ),
              )
            else if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    _errorMessage!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.redAccent, fontSize: 14),
                  ),
                ),
              )
            else if (_isDownloading)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Column(
                  children: [
                    LinearProgressIndicator(
                      value: _downloadProgress > 0 ? _downloadProgress : null,
                      backgroundColor: Colors.white12,
                      valueColor: const AlwaysStoppedAnimation<Color>(Colors.redAccent),
                      minHeight: 8,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _downloadStatus,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              )
            else if (_details != null)
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Video Card Info
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              _details!.thumbnailUrl,
                              width: 110,
                              height: 64,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                width: 110,
                                height: 64,
                                color: Colors.grey[900],
                                child: const Icon(Icons.video_library, color: Colors.white30),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _details!.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _details!.author,
                                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'İndirme Seçenekleri:',
                        style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      const SizedBox(height: 8),

                      // Stream Options
                      ..._details!.options.map((opt) {
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: ListTile(
                            leading: Icon(
                              opt.isAudioOnly ? Icons.music_note_rounded : Icons.video_file_rounded,
                              color: opt.isAudioOnly ? Colors.amberAccent : Colors.redAccent,
                            ),
                            title: Text(
                              opt.qualityLabel,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              'Format: ${opt.format} • ${opt.formattedSize}',
                              style: const TextStyle(color: Colors.white54, fontSize: 12),
                            ),
                            trailing: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.redAccent,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              onPressed: () => _startDownload(opt),
                              icon: const Icon(Icons.download, size: 16),
                              label: const Text('İndir'),
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
