import 'package:sqflite/sqflite.dart';
import 'app_database.dart';

/// Represents a subscribed YouTube channel stored in SQLite.
class SubscriptionModel {
  final int? id;
  final String channelId;
  final String channelName;
  final String? avatarUrl;
  final String? subscriberCount;
  final int createdAt;

  SubscriptionModel({
    this.id,
    required this.channelId,
    required this.channelName,
    this.avatarUrl,
    this.subscriberCount,
    required this.createdAt,
  });

  factory SubscriptionModel.fromMap(Map<String, dynamic> map) {
    return SubscriptionModel(
      id: map['id'] as int?,
      channelId: map['channel_id'] as String,
      channelName: map['channel_name'] as String? ?? 'Bilinmeyen Kanal',
      avatarUrl: map['avatar_url'] as String?,
      subscriberCount: map['subscriber_count'] as String?,
      createdAt: map['created_at'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'channel_id': channelId,
      'channel_name': channelName,
      'avatar_url': avatarUrl,
      'subscriber_count': subscriberCount,
      'created_at': createdAt,
    };
  }
}

/// Represents a user-created local playlist.
class PlaylistModel {
  final int? id;
  final String title;
  final String? description;
  final int createdAt;
  final int itemCount;
  final String? previewThumbnail;

  PlaylistModel({
    this.id,
    required this.title,
    this.description,
    required this.createdAt,
    this.itemCount = 0,
    this.previewThumbnail,
  });

  factory PlaylistModel.fromMap(
    Map<String, dynamic> map, {
    int itemCount = 0,
    String? previewThumbnail,
  }) {
    return PlaylistModel(
      id: map['id'] as int?,
      title: map['title'] as String? ?? 'İsimsiz Liste',
      description: map['description'] as String?,
      createdAt: map['created_at'] as int? ?? 0,
      itemCount: itemCount,
      previewThumbnail: previewThumbnail,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'title': title,
      'description': description,
      'created_at': createdAt,
    };
  }
}

/// Represents an item/video inside a custom playlist.
class PlaylistItemModel {
  final int? id;
  final int playlistId;
  final String videoId;
  final String title;
  final String? author;
  final String? thumbnailUrl;
  final int? durationMs;
  final int addedAt;

  PlaylistItemModel({
    this.id,
    required this.playlistId,
    required this.videoId,
    required this.title,
    this.author,
    this.thumbnailUrl,
    this.durationMs,
    required this.addedAt,
  });

  String get formattedDuration {
    if (durationMs == null || durationMs! <= 0) return '';
    final totalSeconds = (durationMs! / 1000).round();
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    final hours = minutes ~/ 60;
    final remainingMinutes = minutes % 60;

    if (hours > 0) {
      return '$hours:${remainingMinutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  factory PlaylistItemModel.fromMap(Map<String, dynamic> map) {
    return PlaylistItemModel(
      id: map['id'] as int?,
      playlistId: map['playlist_id'] as int,
      videoId: map['video_id'] as String,
      title: map['title'] as String? ?? 'Bilinmeyen Video',
      author: map['author'] as String?,
      thumbnailUrl: map['thumbnail_url'] as String?,
      durationMs: map['duration_ms'] as int?,
      addedAt: map['added_at'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'playlist_id': playlistId,
      'video_id': videoId,
      'title': title,
      'author': author,
      'thumbnail_url': thumbnailUrl,
      'duration_ms': durationMs,
      'added_at': addedAt,
    };
  }
}

/// Represents a video in the user's local watch history.
class HistoryModel {
  final int? id;
  final String videoId;
  final String title;
  final String? author;
  final String? thumbnailUrl;
  final int positionMs;
  final int durationMs;
  final int updatedAt;

  HistoryModel({
    this.id,
    required this.videoId,
    required this.title,
    this.author,
    this.thumbnailUrl,
    this.positionMs = 0,
    this.durationMs = 0,
    required this.updatedAt,
  });

  /// Playback progress ratio between 0.0 and 1.0
  double get progressRatio {
    if (durationMs <= 0) return 0.0;
    return (positionMs / durationMs).clamp(0.0, 1.0);
  }

  String get formattedDuration {
    if (durationMs <= 0) return '';
    final totalSeconds = (durationMs / 1000).round();
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    final hours = minutes ~/ 60;
    final remainingMinutes = minutes % 60;

    if (hours > 0) {
      return '$hours:${remainingMinutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  String get formattedWatchedTime {
    final now = DateTime.now();
    final itemTime = DateTime.fromMillisecondsSinceEpoch(updatedAt);
    final difference = now.difference(itemTime);

    if (difference.inMinutes < 1) {
      return 'Az önce';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes} dakika önce';
    } else if (difference.inHours < 24 && now.day == itemTime.day) {
      return '${difference.inHours} saat önce';
    } else if (difference.inDays < 2) {
      return 'Dün';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} gün önce';
    } else {
      return '${itemTime.day.toString().padLeft(2, '0')}.${itemTime.month.toString().padLeft(2, '0')}.${itemTime.year}';
    }
  }

  factory HistoryModel.fromMap(Map<String, dynamic> map) {
    return HistoryModel(
      id: map['id'] as int?,
      videoId: map['video_id'] as String,
      title: map['title'] as String? ?? 'Bilinmeyen Video',
      author: map['author'] as String?,
      thumbnailUrl: map['thumbnail_url'] as String?,
      positionMs: map['position_ms'] as int? ?? 0,
      durationMs: map['duration_ms'] as int? ?? 0,
      updatedAt: map['updated_at'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'video_id': videoId,
      'title': title,
      'author': author,
      'thumbnail_url': thumbnailUrl,
      'position_ms': positionMs,
      'duration_ms': durationMs,
      'updated_at': updatedAt,
    };
  }
}

/// Repository providing asynchronous CRUD operations for PureTube Library:
/// Subscriptions, Playlists, and Watch History.
class LibraryRepository {
  LibraryRepository._();
  static final LibraryRepository instance = LibraryRepository._();
  factory LibraryRepository() => instance;

  final AppDatabase _appDb = AppDatabase.instance;

  // ==========================================
  // SUBSCRIPTIONS
  // ==========================================

  /// Adds a channel to subscriptions or updates existing.
  Future<int> addSubscription({
    required String channelId,
    required String channelName,
    String? avatarUrl,
    String? subscriberCount,
  }) async {
    final db = await _appDb.database;
    return await db.insert(
      'subscriptions',
      {
        'channel_id': channelId,
        'channel_name': channelName,
        'avatar_url': avatarUrl,
        'subscriber_count': subscriberCount,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Removes a channel from subscriptions.
  Future<int> removeSubscription(String channelId) async {
    final db = await _appDb.database;
    return await db.delete(
      'subscriptions',
      where: 'channel_id = ?',
      whereArgs: [channelId],
    );
  }

  /// Checks if a channel is subscribed.
  Future<bool> isSubscribed(String channelId) async {
    final db = await _appDb.database;
    final res = await db.query(
      'subscriptions',
      columns: ['id'],
      where: 'channel_id = ?',
      whereArgs: [channelId],
      limit: 1,
    );
    return res.isNotEmpty;
  }

  /// Retrieves all subscribed channels sorted by most recently added.
  Future<List<SubscriptionModel>> getSubscriptions() async {
    final db = await _appDb.database;
    final res = await db.query(
      'subscriptions',
      orderBy: 'created_at DESC',
    );
    return res.map((e) => SubscriptionModel.fromMap(e)).toList();
  }

  // ==========================================
  // PLAYLISTS
  // ==========================================

  /// Creates a new custom playlist.
  Future<int> createPlaylist({
    required String title,
    String? description,
  }) async {
    final db = await _appDb.database;
    return await db.insert(
      'playlists',
      {
        'title': title.trim(),
        'description': description?.trim(),
        'created_at': DateTime.now().millisecondsSinceEpoch,
      },
    );
  }

  /// Deletes a playlist and its associated items.
  Future<int> deletePlaylist(int playlistId) async {
    final db = await _appDb.database;
    await db.delete(
      'playlist_items',
      where: 'playlist_id = ?',
      whereArgs: [playlistId],
    );
    return await db.delete(
      'playlists',
      where: 'id = ?',
      whereArgs: [playlistId],
    );
  }

  /// Retrieves all playlists with video count and first video thumbnail preview.
  Future<List<PlaylistModel>> getPlaylists() async {
    final db = await _appDb.database;
    final playlistsRaw = await db.query(
      'playlists',
      orderBy: 'created_at DESC',
    );

    final List<PlaylistModel> result = [];
    for (final p in playlistsRaw) {
      final pId = p['id'] as int;
      final items = await db.query(
        'playlist_items',
        columns: ['thumbnail_url'],
        where: 'playlist_id = ?',
        whereArgs: [pId],
        orderBy: 'added_at ASC',
      );
      final count = items.length;
      final firstThumb = items.isNotEmpty ? items.first['thumbnail_url'] as String? : null;

      result.add(
        PlaylistModel.fromMap(
          p,
          itemCount: count,
          previewThumbnail: firstThumb,
        ),
      );
    }
    return result;
  }

  /// Adds a video to a specific playlist.
  Future<int> addVideoToPlaylist({
    required int playlistId,
    required String videoId,
    required String title,
    String? author,
    String? thumbnailUrl,
    int? durationMs,
  }) async {
    final db = await _appDb.database;
    return await db.insert(
      'playlist_items',
      {
        'playlist_id': playlistId,
        'video_id': videoId,
        'title': title,
        'author': author,
        'thumbnail_url': thumbnailUrl,
        'duration_ms': durationMs,
        'added_at': DateTime.now().millisecondsSinceEpoch,
      },
    );
  }

  /// Removes a video from a specific playlist.
  Future<int> removeVideoFromPlaylist({
    required int playlistId,
    required String videoId,
  }) async {
    final db = await _appDb.database;
    return await db.delete(
      'playlist_items',
      where: 'playlist_id = ? AND video_id = ?',
      whereArgs: [playlistId, videoId],
    );
  }

  /// Removes a specific playlist item by its record id.
  Future<int> removePlaylistItemById(int itemId) async {
    final db = await _appDb.database;
    return await db.delete(
      'playlist_items',
      where: 'id = ?',
      whereArgs: [itemId],
    );
  }

  /// Gets all videos in a playlist.
  Future<List<PlaylistItemModel>> getPlaylistVideos(int playlistId) async {
    final db = await _appDb.database;
    final res = await db.query(
      'playlist_items',
      where: 'playlist_id = ?',
      whereArgs: [playlistId],
      orderBy: 'added_at DESC',
    );
    return res.map((e) => PlaylistItemModel.fromMap(e)).toList();
  }

  // ==========================================
  // WATCH HISTORY
  // ==========================================

  /// Records or updates a video in local watch history with playback position.
  Future<void> recordHistory({
    required String videoId,
    required String title,
    String? author,
    String? thumbnailUrl,
    int? positionMs,
    int? durationMs,
  }) async {
    final db = await _appDb.database;
    final now = DateTime.now().millisecondsSinceEpoch;

    await db.insert(
      'history',
      {
        'video_id': videoId,
        'title': title,
        'author': author,
        'thumbnail_url': thumbnailUrl,
        'position_ms': positionMs ?? 0,
        'duration_ms': durationMs ?? 0,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Retrieves recent watch history up to the specified limit.
  Future<List<HistoryModel>> getHistory({int limit = 50}) async {
    final db = await _appDb.database;
    final res = await db.query(
      'history',
      orderBy: 'updated_at DESC',
      limit: limit,
    );
    return res.map((e) => HistoryModel.fromMap(e)).toList();
  }

  /// Clears the entire watch history.
  Future<int> clearHistory() async {
    final db = await _appDb.database;
    return await db.delete('history');
  }

  /// Deletes a single item from watch history by its video ID.
  Future<int> deleteHistoryItem(String videoId) async {
    final db = await _appDb.database;
    return await db.delete(
      'history',
      where: 'video_id = ?',
      whereArgs: [videoId],
    );
  }
}
