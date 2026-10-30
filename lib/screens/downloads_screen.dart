import 'dart:io';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

class DownloadedMediaItem {
  final File file;
  final String name;
  final String extension;
  final int sizeInBytes;
  final DateTime lastModified;
  final bool isVideo;

  DownloadedMediaItem({
    required this.file,
    required this.name,
    required this.extension,
    required this.sizeInBytes,
    required this.lastModified,
    required this.isVideo,
  });

  String get formattedSize {
    final mb = sizeInBytes / (1024 * 1024);
    if (mb >= 1) {
      return '${mb.toStringAsFixed(1)} MB';
    }
    final kb = sizeInBytes / 1024;
    return '${kb.toStringAsFixed(0)} KB';
  }

  String get formattedDate {
    return '${lastModified.day.toString().padLeft(2, '0')}.${lastModified.month.toString().padLeft(2, '0')}.${lastModified.year}  ${lastModified.hour.toString().padLeft(2, '0')}:${lastModified.minute.toString().padLeft(2, '0')}';
  }
}

class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});

  @override
  State<DownloadsScreen> createState() => DownloadsScreenState();
}

class DownloadsScreenState extends State<DownloadsScreen> {
  List<DownloadedMediaItem> _items = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    refreshList();
  }

  Future<void> refreshList() async {
    setState(() => _isLoading = true);
    final List<DownloadedMediaItem> loaded = [];

    final List<Directory> searchDirs = [];

    if (Platform.isAndroid) {
      searchDirs.add(Directory('/storage/emulated/0/Download/PureTube'));
    }

    try {
      final extDir = await getExternalStorageDirectory();
      if (extDir != null) searchDirs.add(extDir);
      final docDir = await getApplicationDocumentsDirectory();
      searchDirs.add(docDir);
    } catch (_) {}

    for (final dir in searchDirs) {
      if (await dir.exists()) {
        try {
          final entities = dir.listSync();
          for (final entity in entities) {
            if (entity is File) {
              final path = entity.path.toLowerCase();
              final isVideo = path.endsWith('.mp4') || path.endsWith('.webm') || path.endsWith('.mkv');
              final isAudio = path.endsWith('.m4a') || path.endsWith('.mp3') || path.endsWith('.opus') || path.endsWith('.aac');

              if (isVideo || isAudio) {
                final stat = entity.statSync();
                final rawName = entity.uri.pathSegments.last;
                loaded.add(
                  DownloadedMediaItem(
                    file: entity,
                    name: rawName,
                    extension: rawName.split('.').last.toUpperCase(),
                    sizeInBytes: stat.size,
                    lastModified: stat.modified,
                    isVideo: isVideo,
                  ),
                );
              }
            }
          }
        } catch (_) {}
      }
    }

    // Sort newest first
    loaded.sort((a, b) => b.lastModified.compareTo(a.lastModified));

    if (mounted) {
      setState(() {
        _items = loaded;
        _isLoading = false;
      });
    }
  }

  Future<void> _playMedia(DownloadedMediaItem item) async {
    try {
      final result = await OpenFilex.open(item.file.path);
      if (result.type != ResultType.done && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Dosya açılamadı: ${result.message}'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<void> _deleteMedia(DownloadedMediaItem item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF222222),
        title: const Text('Dosyayı Sil', style: TextStyle(color: Colors.white)),
        content: Text(
          'Bu dosyayı silmek istediğinizden emin misiniz?\n\n${item.name}',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sil', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await item.file.delete();
        await refreshList();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Dosya silindi.'), backgroundColor: Colors.black87),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Silme hatası: $e'), backgroundColor: Colors.redAccent),
          );
        }
      }
    }
  }

  int get _totalSizeBytes => _items.fold(0, (acc, item) => acc + item.sizeInBytes);

  String get _formattedTotalSize {
    final mb = _totalSizeBytes / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      body: SafeArea(
        child: Column(
          children: [
            // Header Stats Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: Color(0xFF161616),
                border: Border(bottom: BorderSide(color: Colors.white10, width: 1)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.download_done_rounded, color: Colors.redAccent, size: 24),
                  const SizedBox(width: 10),
                  Text(
                    'İndirilenler (${_items.length})',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  if (_items.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _formattedTotalSize,
                        style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded, color: Colors.white70, size: 22),
                    onPressed: refreshList,
                  ),
                ],
              ),
            ),

            // Content List
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: Colors.redAccent))
                  : _items.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.folder_open_rounded, size: 72, color: Colors.white.withValues(alpha: 0.2)),
                                const SizedBox(height: 16),
                                const Text(
                                  'Henüz indirilmiş içerik yok',
                                  style: TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'YouTube veya YT Music sekmelerindeki İndir butonuna basarak video ve müzikleri telefonunuza kaydedebilirsiniz.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.white38, fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                        )
                      : RefreshIndicator(
                          color: Colors.redAccent,
                          backgroundColor: const Color(0xFF222222),
                          onRefresh: refreshList,
                          child: ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                            itemCount: _items.length,
                            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                            itemBuilder: (context, index) {
                              final item = _items[index];
                              return Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1A1A1A),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                                ),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                  leading: Container(
                                    width: 46,
                                    height: 46,
                                    decoration: BoxDecoration(
                                      color: item.isVideo
                                          ? Colors.redAccent.withValues(alpha: 0.15)
                                          : Colors.amberAccent.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Icon(
                                      item.isVideo ? Icons.movie_outlined : Icons.music_note_rounded,
                                      color: item.isVideo ? Colors.redAccent : Colors.amberAccent,
                                      size: 26,
                                    ),
                                  ),
                                  title: Text(
                                    item.name,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  subtitle: Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withValues(alpha: 0.08),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            item.extension,
                                            style: const TextStyle(
                                              color: Colors.white70,
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          item.formattedSize,
                                          style: const TextStyle(color: Colors.white54, fontSize: 12),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          item.formattedDate,
                                          style: const TextStyle(color: Colors.white38, fontSize: 11),
                                        ),
                                      ],
                                    ),
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.play_circle_fill_rounded, color: Colors.redAccent, size: 36),
                                        onPressed: () => _playMedia(item),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline_rounded, color: Colors.white38, size: 20),
                                        onPressed: () => _deleteMedia(item),
                                      ),
                                    ],
                                  ),
                                  onTap: () => _playMedia(item),
                                ),
                              );
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
