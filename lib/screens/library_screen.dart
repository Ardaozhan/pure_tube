import 'package:flutter/material.dart';
import '../database/library_repository.dart';

/// Accountless Local Library Screen for PureTube v3.0.
/// Features Subscriptions, Custom Playlists, and Watch History with OLED styling.
class LibraryScreen extends StatefulWidget {
  final Function(String videoId)? onVideoTap;
  final Function(String channelId)? onChannelTap;

  const LibraryScreen({
    super.key,
    this.onVideoTap,
    this.onChannelTap,
  });

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final LibraryRepository _repo = LibraryRepository.instance;

  List<SubscriptionModel> _subscriptions = [];
  List<PlaylistModel> _playlists = [];
  List<HistoryModel> _history = [];

  bool _isLoadingSubs = true;
  bool _isLoadingPlaylists = true;
  bool _isLoadingHistory = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _refreshAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _refreshAll() async {
    await Future.wait([
      _loadSubscriptions(),
      _loadPlaylists(),
      _loadHistory(),
    ]);
  }

  Future<void> _loadSubscriptions() async {
    final subs = await _repo.getSubscriptions();
    if (mounted) {
      setState(() {
        _subscriptions = subs;
        _isLoadingSubs = false;
      });
    }
  }

  Future<void> _loadPlaylists() async {
    final pls = await _repo.getPlaylists();
    if (mounted) {
      setState(() {
        _playlists = pls;
        _isLoadingPlaylists = false;
      });
    }
  }

  Future<void> _loadHistory() async {
    final hist = await _repo.getHistory(limit: 100);
    if (mounted) {
      setState(() {
        _history = hist;
        _isLoadingHistory = false;
      });
    }
  }

  void _handleVideoTap(String videoId) {
    if (widget.onVideoTap != null) {
      widget.onVideoTap!(videoId);
    } else {
      Navigator.pop(context, videoId);
    }
  }

  void _handleChannelTap(String channelId) {
    if (widget.onChannelTap != null) {
      widget.onChannelTap!(channelId);
    } else {
      Navigator.pop(context, channelId);
    }
  }

  // ==========================================
  // PLAYLIST CREATION DIALOG
  // ==========================================

  Future<void> _showCreatePlaylistDialog() async {
    final titleController = TextEditingController();
    final descController = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.playlist_add_rounded, color: Colors.redAccent, size: 26),
              SizedBox(width: 10),
              Text(
                'Yeni Çalma Listesi',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Liste Başlığı',
                  labelStyle: const TextStyle(color: Colors.white60),
                  filled: true,
                  fillColor: const Color(0xFF141414),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descController,
                style: const TextStyle(color: Colors.white),
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'Açıklama (İsteğe bağlı)',
                  labelStyle: const TextStyle(color: Colors.white60),
                  filled: true,
                  fillColor: const Color(0xFF141414),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('İptal', style: TextStyle(color: Colors.white60)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () async {
                final title = titleController.text.trim();
                if (title.isNotEmpty) {
                  await _repo.createPlaylist(
                    title: title,
                    description: descController.text.trim().isEmpty ? null : descController.text.trim(),
                  );
                  if (ctx.mounted) Navigator.pop(ctx);
                  await _loadPlaylists();
                }
              },
              child: const Text('Oluştur'),
            ),
          ],
        );
      },
    );
  }

  // ==========================================
  // PLAYLIST DETAILS BOTTOM SHEET
  // ==========================================

  void _showPlaylistDetails(PlaylistModel playlist) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (bottomSheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return FutureBuilder<List<PlaylistItemModel>>(
              future: _repo.getPlaylistVideos(playlist.id!),
              builder: (context, snapshot) {
                final videos = snapshot.data ?? [];
                return Container(
                  height: MediaQuery.of(context).size.height * 0.75,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: const BoxDecoration(
                    color: Color(0xFF141414),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                    border: Border(top: BorderSide(color: Colors.white12, width: 0.8)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  playlist.title,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (playlist.description != null && playlist.description!.isNotEmpty)
                                  Text(
                                    playlist.description!,
                                    style: const TextStyle(color: Colors.white60, fontSize: 13),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                Text(
                                  '${videos.length} video',
                                  style: const TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline_rounded, color: Colors.white60),
                            tooltip: 'Listeyi Sil',
                            onPressed: () async {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (c) => AlertDialog(
                                  backgroundColor: const Color(0xFF222222),
                                  title: const Text('Listeyi Sil', style: TextStyle(color: Colors.white)),
                                  content: Text('"${playlist.title}" listesini silmek istediğinize emin misiniz?', style: const TextStyle(color: Colors.white70)),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('İptal', style: TextStyle(color: Colors.white60))),
                                    TextButton(
                                      onPressed: () => Navigator.pop(c, true),
                                      child: const Text('Sil', style: TextStyle(color: Colors.redAccent)),
                                    ),
                                  ],
                                ),
                              );

                              if (confirm == true) {
                                await _repo.deletePlaylist(playlist.id!);
                                if (bottomSheetContext.mounted) {
                                  Navigator.pop(bottomSheetContext);
                                }
                                await _loadPlaylists();
                              }
                            },
                          ),
                        ],
                      ),
                      const Divider(color: Colors.white12, height: 20),
                      Expanded(
                        child: videos.isEmpty
                            ? const Center(
                                child: Text(
                                  'Bu listede henüz video yok.',
                                  style: TextStyle(color: Colors.white38, fontSize: 14),
                                ),
                              )
                            : ListView.builder(
                                itemCount: videos.length,
                                itemBuilder: (context, idx) {
                                  final item = videos[idx];
                                  return ListTile(
                                    contentPadding: const EdgeInsets.symmetric(vertical: 4),
                                    leading: ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: SizedBox(
                                        width: 80,
                                        height: 48,
                                        child: (item.thumbnailUrl != null && item.thumbnailUrl!.isNotEmpty)
                                            ? Image.network(
                                                item.thumbnailUrl!,
                                                fit: BoxFit.cover,
                                                errorBuilder: (_, __, ___) => Container(
                                                  color: Colors.black26,
                                                  child: const Icon(Icons.play_arrow_rounded, color: Colors.white38),
                                                ),
                                              )
                                            : Container(
                                                color: Colors.black26,
                                                child: const Icon(Icons.play_arrow_rounded, color: Colors.white38),
                                              ),
                                      ),
                                    ),
                                    title: Text(
                                      item.title,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                                    ),
                                    subtitle: Text(
                                      item.author ?? 'YouTube',
                                      style: const TextStyle(color: Colors.white54, fontSize: 11),
                                    ),
                                    trailing: IconButton(
                                      icon: const Icon(Icons.remove_circle_outline_rounded, color: Colors.white38, size: 20),
                                      onPressed: () async {
                                        if (item.id != null) {
                                          await _repo.removePlaylistItemById(item.id!);
                                          setSheetState(() {});
                                          await _loadPlaylists();
                                        }
                                      },
                                    ),
                                    onTap: () {
                                      Navigator.pop(bottomSheetContext);
                                      _handleVideoTap(item.videoId);
                                    },
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  // ==========================================
  // ADD VIDEO TO PLAYLIST DIALOG
  // ==========================================

  Future<void> _showAddToPlaylistDialog(HistoryModel video) async {
    final playlists = await _repo.getPlaylists();
    if (!mounted) return;

    if (playlists.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Kayıtlı çalma listeniz yok. Önce bir liste oluşturun.'),
          action: SnackBarAction(
            label: 'Oluştur',
            textColor: Colors.redAccent,
            onPressed: _showCreatePlaylistDialog,
          ),
          backgroundColor: const Color(0xFF222222),
        ),
      );
      return;
    }

    await showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Çalma Listesine Ekle', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: playlists.length,
              itemBuilder: (itemCtx, idx) {
                final pl = playlists[idx];
                return ListTile(
                  leading: const Icon(Icons.playlist_add_rounded, color: Colors.redAccent),
                  title: Text(pl.title, style: const TextStyle(color: Colors.white)),
                  subtitle: Text('${pl.itemCount} video', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                  onTap: () async {
                    await _repo.addVideoToPlaylist(
                      playlistId: pl.id!,
                      videoId: video.videoId,
                      title: video.title,
                      author: video.author,
                      thumbnailUrl: video.thumbnailUrl,
                      durationMs: video.durationMs,
                    );
                    if (!ctx.mounted) return;
                    Navigator.pop(ctx);
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('"${video.title}" -> "${pl.title}" listesine eklendi'),
                        backgroundColor: Colors.green,
                      ),
                    );
                    _loadPlaylists();
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Kapat', style: TextStyle(color: Colors.white60)),
            ),
          ],
        );
      },
    );
  }

  // ==========================================
  // CONFIRM CLEAR HISTORY
  // ==========================================

  Future<void> _confirmClearHistory() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF222222),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.delete_sweep_rounded, color: Colors.redAccent),
            SizedBox(width: 8),
            Text('Geçmişi Temizle', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: const Text(
          'Tüm izleme geçmişiniz silinecektir. Bu işlem geri alınamaz.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Vazgeç', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Temizle'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _repo.clearHistory();
      await _loadHistory();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('İzleme geçmişi temizlendi'),
            backgroundColor: Color(0xFF333333),
          ),
        );
      }
    }
  }

  // ==========================================
  // BUILD SCREEN UI
  // ==========================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Row(
          children: [
            Icon(Icons.video_library_rounded, color: Colors.redAccent, size: 24),
            SizedBox(width: 8),
            Text(
              'Kütüphane',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 19),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Yenile',
            icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
            onPressed: _refreshAll,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.white12, width: 0.8)),
            ),
            child: TabBar(
              controller: _tabController,
              indicatorColor: Colors.redAccent,
              indicatorWeight: 3,
              indicatorSize: TabBarIndicatorSize.tab,
              labelColor: Colors.redAccent,
              unselectedLabelColor: Colors.white60,
              labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
              unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.normal, fontSize: 13.5),
              tabs: const [
                Tab(
                  icon: Icon(Icons.subscriptions_rounded, size: 20),
                  text: 'Abonelikler',
                ),
                Tab(
                  icon: Icon(Icons.playlist_play_rounded, size: 22),
                  text: 'Çalma Listeleri',
                ),
                Tab(
                  icon: Icon(Icons.history_rounded, size: 20),
                  text: 'İzleme Geçmişi',
                ),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildSubscriptionsTab(),
          _buildPlaylistsTab(),
          _buildHistoryTab(),
        ],
      ),
    );
  }

  // ==========================================
  // TAB 1: SUBSCRIPTIONS
  // ==========================================

  Widget _buildSubscriptionsTab() {
    if (_isLoadingSubs) {
      return const Center(child: CircularProgressIndicator(color: Colors.redAccent));
    }

    if (_subscriptions.isEmpty) {
      return _buildEmptyState(
        icon: Icons.subscriptions_outlined,
        title: 'Henüz abone olduğunuz kanal yok',
        subtitle: 'YouTube videolarını izlerken kanallara abone olarak güncellemeleri buradan takip edebilirsiniz.',
      );
    }

    return RefreshIndicator(
      color: Colors.redAccent,
      backgroundColor: const Color(0xFF1E1E1E),
      onRefresh: _loadSubscriptions,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        itemCount: _subscriptions.length,
        separatorBuilder: (_, __) => const Divider(color: Colors.white10, height: 1),
        itemBuilder: (subContext, index) {
          final sub = _subscriptions[index];
          return ListTile(
            contentPadding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            leading: CircleAvatar(
              radius: 24,
              backgroundColor: const Color(0xFF262626),
              backgroundImage: (sub.avatarUrl != null && sub.avatarUrl!.isNotEmpty)
                  ? NetworkImage(sub.avatarUrl!)
                  : null,
              child: (sub.avatarUrl == null || sub.avatarUrl!.isEmpty)
                  ? const Icon(Icons.person, color: Colors.white60, size: 26)
                  : null,
            ),
            title: Text(
              sub.channelName,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: (sub.subscriberCount != null && sub.subscriberCount!.isNotEmpty)
                ? Text(
                    sub.subscriberCount!,
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  )
                : null,
            trailing: OutlinedButton(
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.white24, width: 0.8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                minimumSize: const Size(60, 32),
              ),
              onPressed: () async {
                await _repo.removeSubscription(sub.channelId);
                await _loadSubscriptions();
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('${sub.channelName} aboneliği kaldırıldı'),
                    backgroundColor: const Color(0xFF333333),
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
              child: const Text(
                'Abonelikten Çık',
                style: TextStyle(color: Colors.white70, fontSize: 11.5),
              ),
            ),
            onTap: () => _handleChannelTap(sub.channelId),
          );
        },
      ),
    );
  }

  // ==========================================
  // TAB 2: PLAYLISTS
  // ==========================================

  Widget _buildPlaylistsTab() {
    if (_isLoadingPlaylists) {
      return const Center(child: CircularProgressIndicator(color: Colors.redAccent));
    }

    return Column(
      children: [
        // Top Action Bar
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Çalma Listelerim (${_playlists.length})',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Yeni Liste', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                onPressed: _showCreatePlaylistDialog,
              ),
            ],
          ),
        ),
        const Divider(color: Colors.white12, height: 1),
        Expanded(
          child: _playlists.isEmpty
              ? _buildEmptyState(
                  icon: Icons.playlist_add_rounded,
                  title: 'Çalma listesi bulunamadı',
                  subtitle: 'Videoları ve müzikleri kategorize etmek için sağ üstteki butondan yeni bir liste oluşturun.',
                )
              : RefreshIndicator(
                  color: Colors.redAccent,
                  backgroundColor: const Color(0xFF1E1E1E),
                  onRefresh: _loadPlaylists,
                  child: GridView.builder(
                    padding: const EdgeInsets.all(16),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 0.9,
                    ),
                    itemCount: _playlists.length,
                    itemBuilder: (context, index) {
                      final pl = _playlists[index];
                      return GestureDetector(
                        onTap: () => _showPlaylistDetails(pl),
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF141414),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white10, width: 0.8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Playlist Thumbnail Preview
                              ClipRRect(
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                                child: AspectRatio(
                                  aspectRatio: 16 / 9,
                                  child: Container(
                                    color: const Color(0xFF222222),
                                    child: (pl.previewThumbnail != null && pl.previewThumbnail!.isNotEmpty)
                                        ? Image.network(
                                            pl.previewThumbnail!,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) => const Center(
                                              child: Icon(Icons.queue_music_rounded, color: Colors.white30, size: 36),
                                            ),
                                          )
                                        : const Center(
                                            child: Icon(Icons.queue_music_rounded, color: Colors.white30, size: 36),
                                          ),
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(10),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      pl.title,
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      '${pl.itemCount} video',
                                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  // ==========================================
  // TAB 3: WATCH HISTORY
  // ==========================================

  Widget _buildHistoryTab() {
    if (_isLoadingHistory) {
      return const Center(child: CircularProgressIndicator(color: Colors.redAccent));
    }

    if (_history.isEmpty) {
      return _buildEmptyState(
        icon: Icons.history_toggle_off_rounded,
        title: 'İzleme geçmişiniz temiz',
        subtitle: 'İzlediğiniz videolar ve dinlediğiniz müzikler kaldığınız süre bilgisiyle burada kaydedilir.',
      );
    }

    return Column(
      children: [
        // History Header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Son İzlenenler (${_history.length})',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
              ),
              TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: Colors.redAccent,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                ),
                icon: const Icon(Icons.delete_sweep_rounded, size: 18),
                label: const Text('Temizle', style: TextStyle(fontSize: 12.5)),
                onPressed: _confirmClearHistory,
              ),
            ],
          ),
        ),
        const Divider(color: Colors.white12, height: 1),
        Expanded(
          child: RefreshIndicator(
            color: Colors.redAccent,
            backgroundColor: const Color(0xFF1E1E1E),
            onRefresh: _loadHistory,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              itemCount: _history.length,
              separatorBuilder: (_, __) => const Divider(color: Colors.white10, height: 1),
              itemBuilder: (context, index) {
                final item = _history[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => _handleVideoTap(item.videoId),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Thumbnail with Progress Bar & Duration
                        Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: SizedBox(
                                width: 120,
                                height: 68,
                                child: (item.thumbnailUrl != null && item.thumbnailUrl!.isNotEmpty)
                                    ? Image.network(
                                        item.thumbnailUrl!,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => Container(
                                          color: const Color(0xFF222222),
                                          child: const Icon(Icons.play_circle_outline, color: Colors.white30),
                                        ),
                                      )
                                    : Container(
                                        color: const Color(0xFF222222),
                                        child: const Icon(Icons.play_circle_outline, color: Colors.white30),
                                      ),
                              ),
                            ),
                            // Duration Pill
                            if (item.formattedDuration.isNotEmpty)
                              Positioned(
                                right: 4,
                                bottom: 6,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: Colors.black87,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    item.formattedDuration,
                                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ),
                            // Watched Progress Bar
                            if (item.progressRatio > 0.0)
                              Positioned(
                                left: 0,
                                right: 0,
                                bottom: 0,
                                child: ClipRRect(
                                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(10)),
                                  child: LinearProgressIndicator(
                                    value: item.progressRatio,
                                    backgroundColor: Colors.white24,
                                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.redAccent),
                                    minHeight: 3,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(width: 12),
                        // Details
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13.5),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                item.author ?? 'YouTube',
                                style: const TextStyle(color: Colors.white54, fontSize: 11.5),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                item.formattedWatchedTime,
                                style: const TextStyle(color: Colors.white38, fontSize: 10.5),
                              ),
                            ],
                          ),
                        ),
                        // Options Menu
                        PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert_rounded, color: Colors.white54, size: 20),
                          color: const Color(0xFF222222),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          onSelected: (value) async {
                            if (value == 'play') {
                              _handleVideoTap(item.videoId);
                            } else if (value == 'add_playlist') {
                              _showAddToPlaylistDialog(item);
                            } else if (value == 'remove') {
                              await _repo.deleteHistoryItem(item.videoId);
                              await _loadHistory();
                            }
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'play',
                              child: Row(
                                children: [
                                  Icon(Icons.play_arrow_rounded, color: Colors.white70, size: 20),
                                  SizedBox(width: 8),
                                  Text('Oynat', style: TextStyle(color: Colors.white)),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'add_playlist',
                              child: Row(
                                children: [
                                  Icon(Icons.playlist_add_rounded, color: Colors.white70, size: 20),
                                  SizedBox(width: 8),
                                  Text('Çalma Listesine Ekle', style: TextStyle(color: Colors.white)),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'remove',
                              child: Row(
                                children: [
                                  Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                                  SizedBox(width: 8),
                                  Text('Geçmişten Kaldır', style: TextStyle(color: Colors.redAccent)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  // ==========================================
  // SHARED EMPTY STATE
  // ==========================================

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF161616),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white10, width: 1),
              ),
              child: Icon(icon, color: Colors.white38, size: 48),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54, fontSize: 13, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}
