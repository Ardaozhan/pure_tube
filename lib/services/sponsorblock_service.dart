import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Model representing a skipped segment from SponsorBlock v2 API
class SponsorSegment {
  final String category;
  final double startTime;
  final double endTime;
  final String uuid;

  const SponsorSegment({
    required this.category,
    required this.startTime,
    required this.endTime,
    required this.uuid,
  });

  /// Duration of this segment in seconds
  double get duration => (endTime > startTime) ? (endTime - startTime) : 0.0;

  /// Check whether a given timestamp (in seconds) falls within this segment
  bool contains(double seconds) =>
      seconds >= startTime && seconds < (endTime - 0.25);

  /// Human-friendly localized category title
  String get categoryTitle {
    switch (category) {
      case 'sponsor':
        return 'Sponsor';
      case 'intro':
      case 'intermission':
        return 'İntro / Ara';
      case 'outro':
        return 'Kapanış / Jenerik';
      case 'selfpromo':
        return 'Kişisel Tanıtım';
      case 'interaction':
        return 'Abone Ol / Beğen';
      case 'music_offtopic':
        return 'Konu Dışı Müzik';
      case 'preview':
        return 'Önizleme / Fragman';
      default:
        return category;
    }
  }

  /// Hex color code representing the category for seekbar overlay rendering
  String get categoryColor {
    switch (category) {
      case 'sponsor':
        return '#00d66c'; // Emerald green
      case 'intro':
      case 'intermission':
        return '#00e5ff'; // Cyan
      case 'outro':
        return '#3d5afe'; // Indigo
      case 'selfpromo':
        return '#ffeb3b'; // Amber / Yellow
      case 'interaction':
        return '#e040fb'; // Neon purple / Magenta
      case 'music_offtopic':
        return '#ff9100'; // Orange
      case 'preview':
        return '#00b0ff'; // Light Blue
      default:
        return '#00d66c';
    }
  }

  factory SponsorSegment.fromJson(Map<String, dynamic> json) {
    double start = 0.0;
    double end = 0.0;

    // SponsorBlock API returns segment as [start, end]
    if (json['segment'] is List && (json['segment'] as List).length >= 2) {
      final list = json['segment'] as List;
      start = (list[0] as num).toDouble();
      end = (list[1] as num).toDouble();
    } else {
      start = (json['startTime'] as num?)?.toDouble() ?? 0.0;
      end = (json['endTime'] as num?)?.toDouble() ?? 0.0;
    }

    final category = json['category'] as String? ?? 'sponsor';
    final uuid = json['UUID'] as String? ?? json['uuid'] as String? ?? '';

    return SponsorSegment(
      category: category,
      startTime: start,
      endTime: end,
      uuid: uuid,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'category': category,
      'startTime': startTime,
      'endTime': endTime,
      'UUID': uuid,
      'categoryTitle': categoryTitle,
      'categoryColor': categoryColor,
    };
  }

  @override
  String toString() =>
      'SponsorSegment($category: ${startTime.toStringAsFixed(1)}s -> ${endTime.toStringAsFixed(1)}s, uuid: $uuid)';
}

/// Cache wrapper containing timestamp for SponsorBlock entries
class _CachedSponsorEntry {
  final List<SponsorSegment> segments;
  final DateTime cachedAt;

  const _CachedSponsorEntry({
    required this.segments,
    required this.cachedAt,
  });

  bool get isExpired =>
      DateTime.now().difference(cachedAt) > const Duration(minutes: 15);
}

/// SponsorBlock v2 API Client with caching and seekbar utilities
class SponsorBlockService {
  SponsorBlockService._();
  static final SponsorBlockService instance = SponsorBlockService._();

  static const String _baseUrl = 'https://sponsor.ajay.app/api/skipSegments';
  static const List<String> defaultCategories = [
    'sponsor',
    'intro',
    'outro',
    'selfpromo',
    'interaction',
    'music_offtopic',
  ];

  static final Map<String, _CachedSponsorEntry> _cache =
      <String, _CachedSponsorEntry>{};

  /// Fetch skip segments for a given video ID.
  /// Result is cached in memory with a 15-minute TTL.
  Future<List<SponsorSegment>> fetchSegments(
    String videoId, {
    List<String>? categories,
    bool forceRefresh = false,
  }) async {
    final trimmedId = videoId.trim();
    if (trimmedId.isEmpty) return const [];

    if (!forceRefresh) {
      final cached = _cache[trimmedId];
      if (cached != null && !cached.isExpired) {
        return cached.segments;
      }
    }

    final catList = categories ?? defaultCategories;
    final encodedCategories = Uri.encodeComponent(jsonEncode(catList));
    final uri = Uri.parse('$_baseUrl?videoID=$trimmedId&categories=$encodedCategories');

    try {
      final response = await http.get(uri).timeout(
            const Duration(seconds: 8),
          );

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is List) {
          final segments = decoded
              .whereType<Map<String, dynamic>>()
              .map((item) => SponsorSegment.fromJson(item))
              .toList();

          // Sort sequentially by startTime
          segments.sort((a, b) => a.startTime.compareTo(b.startTime));

          _cache[trimmedId] = _CachedSponsorEntry(
            segments: segments,
            cachedAt: DateTime.now(),
          );
          return segments;
        }
      } else if (response.statusCode == 404) {
        // 404 is the expected response when a video has no sponsor submissions
        _cache[trimmedId] = _CachedSponsorEntry(
          segments: const [],
          cachedAt: DateTime.now(),
        );
        return const [];
      } else {
        debugPrint(
          '[SponsorBlock] Status ${response.statusCode} for video $trimmedId',
        );
      }
    } catch (e, stack) {
      debugPrint('[SponsorBlock] Fetch error for $trimmedId: $e');
      debugPrint('$stack');
    }

    // Fallback to stale cache if present
    final stale = _cache[trimmedId];
    if (stale != null) {
      return stale.segments;
    }

    return const [];
  }

  /// Check if the given time in seconds falls within any segment
  SponsorSegment? findActiveSegment(
    List<SponsorSegment> segments,
    double currentTimeSec,
  ) {
    for (final seg in segments) {
      if (seg.contains(currentTimeSec)) {
        return seg;
      }
    }
    return null;
  }

  /// Get cached segments if present and valid
  List<SponsorSegment>? getCachedSegments(String videoId) {
    final cached = _cache[videoId.trim()];
    if (cached != null && !cached.isExpired) {
      return cached.segments;
    }
    return null;
  }

  /// Clear all or expired cached segments
  void clearCache({bool onlyExpired = false}) {
    if (onlyExpired) {
      _cache.removeWhere((_, entry) => entry.isExpired);
    } else {
      _cache.clear();
    }
  }
}
