import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Model representing Return YouTube Dislike (RYD) statistics for a video.
class RydVotes {
  final String videoId;
  final int likes;
  final int dislikes;
  final double rating;
  final int viewCount;
  final String formattedLikes;
  final String formattedDislikes;
  final double likePercentage;

  const RydVotes({
    required this.videoId,
    required this.likes,
    required this.dislikes,
    required this.rating,
    required this.viewCount,
    required this.formattedLikes,
    required this.formattedDislikes,
    required this.likePercentage,
  });

  /// Factory constructor to parse raw API response
  factory RydVotes.fromJson(Map<String, dynamic> json, {String? defaultVideoId}) {
    final videoId = (json['id'] as String?) ?? defaultVideoId ?? '';
    final likes = (json['likes'] as num?)?.toInt() ?? 0;
    final dislikes = (json['dislikes'] as num?)?.toInt() ?? 0;
    final rating = (json['rating'] as num?)?.toDouble() ?? 0.0;
    final viewCount = (json['viewCount'] as num?)?.toInt() ?? 0;

    final totalVotes = likes + dislikes;
    final likePercentage = totalVotes > 0
        ? (likes / totalVotes) * 100.0
        : (likes > 0 ? 100.0 : 0.0);

    return RydVotes(
      videoId: videoId,
      likes: likes,
      dislikes: dislikes,
      rating: rating,
      viewCount: viewCount,
      formattedLikes: _formatNumber(likes),
      formattedDislikes: _formatNumber(dislikes),
      likePercentage: likePercentage,
    );
  }

  /// Convert to Map for JSON serialization or Flutter-JS bridge transmission
  Map<String, dynamic> toMap() {
    return {
      'videoId': videoId,
      'likes': likes,
      'dislikes': dislikes,
      'rating': rating,
      'viewCount': viewCount,
      'formattedLikes': formattedLikes,
      'formattedDislikes': formattedDislikes,
      'likePercentage': likePercentage,
    };
  }

  /// Compact metric formatter: 1.2M, 45.6K, 950
  static String _formatNumber(int number) {
    if (number >= 1000000000) {
      final value = (number / 1000000000).toStringAsFixed(1);
      return '${value.endsWith('.0') ? value.substring(0, value.length - 2) : value}B';
    }
    if (number >= 1000000) {
      final value = (number / 1000000).toStringAsFixed(1);
      return '${value.endsWith('.0') ? value.substring(0, value.length - 2) : value}M';
    }
    if (number >= 1000) {
      final value = (number / 1000).toStringAsFixed(1);
      return '${value.endsWith('.0') ? value.substring(0, value.length - 2) : value}K';
    }
    return number.toString();
  }

  @override
  String toString() =>
      'RydVotes(id: $videoId, likes: $likes ($formattedLikes), dislikes: $dislikes ($formattedDislikes), ratio: ${likePercentage.toStringAsFixed(1)}%)';
}

/// Cache wrapper containing timestamp for 10-minute TTL expiry
class _CachedRydEntry {
  final RydVotes votes;
  final DateTime cachedAt;

  const _CachedRydEntry({
    required this.votes,
    required this.cachedAt,
  });

  bool get isExpired =>
      DateTime.now().difference(cachedAt) > const Duration(minutes: 10);
}

/// Return YouTube Dislike (RYD) API Service with 10-minute caching
class RydService {
  RydService._();
  static final RydService instance = RydService._();

  static const String _baseUrl = 'https://returnyoutubedislikeapi.com/votes';
  static final Map<String, _CachedRydEntry> _cache = <String, _CachedRydEntry>{};

  /// Fetch votes for a YouTube video.
  /// Uses in-memory cache with 10-minute TTL unless [forceRefresh] is true.
  Future<RydVotes?> fetchVotes(
    String videoId, {
    bool forceRefresh = false,
  }) async {
    final trimmedId = videoId.trim();
    if (trimmedId.isEmpty) return null;

    if (!forceRefresh) {
      final cached = _cache[trimmedId];
      if (cached != null && !cached.isExpired) {
        return cached.votes;
      }
    }

    try {
      final uri = Uri.parse('$_baseUrl?videoId=$trimmedId');
      final response = await http.get(uri).timeout(
            const Duration(seconds: 8),
          );

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          final votes = RydVotes.fromJson(decoded, defaultVideoId: trimmedId);
          _cache[trimmedId] = _CachedRydEntry(
            votes: votes,
            cachedAt: DateTime.now(),
          );
          return votes;
        }
      } else if (response.statusCode == 404) {
        debugPrint('[RydService] Video not found or no votes recorded: $trimmedId');
      } else {
        debugPrint(
          '[RydService] API request failed with status: ${response.statusCode} for $trimmedId',
        );
      }
    } catch (e, stack) {
      debugPrint('[RydService] Error fetching votes for $trimmedId: $e');
      debugPrint('$stack');
    }

    // If fetch failed but we have stale cache, return stale cache as fallback
    final stale = _cache[trimmedId];
    if (stale != null) {
      return stale.votes;
    }

    return null;
  }

  /// Get cached votes without making network request
  RydVotes? getCachedVotes(String videoId) {
    final cached = _cache[videoId.trim()];
    if (cached != null && !cached.isExpired) {
      return cached.votes;
    }
    return null;
  }

  /// Clear expired entries or all cache
  void clearCache({bool onlyExpired = false}) {
    if (onlyExpired) {
      _cache.removeWhere((_, entry) => entry.isExpired);
    } else {
      _cache.clear();
    }
  }
}
