import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Represents a single line of synchronized lyrics with a timestamp in milliseconds.
class LyricLine {
  final int timestampMs;
  final String text;

  const LyricLine({
    required this.timestampMs,
    required this.text,
  });

  @override
  String toString() => 'LyricLine($timestampMs ms: "$text")';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LyricLine &&
          runtimeType == other.runtimeType &&
          timestampMs == other.timestampMs &&
          text == other.text;

  @override
  int get hashCode => timestampMs.hashCode ^ text.hashCode;
}

/// Service that interacts with the LRCLIB public API to fetch and parse synchronized lyrics.
class LyricsService {
  static final LyricsService _instance = LyricsService._internal();
  factory LyricsService() => _instance;
  LyricsService._internal();

  static const String _baseUrl = 'https://lrclib.net/api';
  static const Map<String, String> _headers = {
    'User-Agent': 'PureTube v3.0 (https://github.com/puretube/puretube)',
    'Accept': 'application/json',
  };

  /// In-memory cache keyed by normalized query strings.
  final Map<String, List<LyricLine>> _cache = {};

  /// Pre-compiled regex for parsing LRC timestamps like [01:23.45] or [01:23.456]
  static final RegExp _timestampRegex = RegExp(r'\[(\d{1,2}):(\d{2})(?:\.(\d{1,3}))?\]');

  /// Pre-compiled regex for LRC non-timestamp metadata tags like [length:...], [ar:...], [ti:...]
  static final RegExp _metadataTagRegex = RegExp(r'\[[a-zA-Z]+:[^\]]*\]');

  /// Fetches synchronized lyrics for the given song.
  ///
  /// Checks the memory cache first. If not found, attempts an exact match
  /// via `/api/get`, and falls back to `/api/search` if necessary.
  Future<List<LyricLine>?> getLyrics({
    required String trackName,
    String? artistName,
    int? durationSeconds,
  }) async {
    final cleanInfo = cleanMetadata(trackName: trackName, artistName: artistName);
    final finalTrack = cleanInfo.track;
    final finalArtist = cleanInfo.artist;

    final cacheKey = _buildCacheKey(finalTrack, finalArtist, durationSeconds);
    if (_cache.containsKey(cacheKey)) {
      debugPrint('[LyricsService] Cache hit for "$cacheKey"');
      return _cache[cacheKey];
    }

    try {
      // 1. Try exact get if artist name is available
      if (finalArtist != null && finalArtist.isNotEmpty) {
        final exactLyrics = await _fetchExact(
          trackName: finalTrack,
          artistName: finalArtist,
          durationSeconds: durationSeconds,
        );
        if (exactLyrics != null && exactLyrics.isNotEmpty) {
          _cache[cacheKey] = exactLyrics;
          return exactLyrics;
        }
      }

      // 2. Try search API fallback with combined query or track name
      final searchQuery = finalArtist != null && finalArtist.isNotEmpty
          ? '$finalArtist $finalTrack'
          : finalTrack;

      final searchLyrics = await _searchFallback(
        query: searchQuery,
        trackName: finalTrack,
        artistName: finalArtist,
        durationSeconds: durationSeconds,
      );

      if (searchLyrics != null && searchLyrics.isNotEmpty) {
        _cache[cacheKey] = searchLyrics;
        return searchLyrics;
      }
    } catch (e, stack) {
      debugPrint('[LyricsService] Error fetching lyrics: $e\n$stack');
    }

    return null;
  }

  /// Attempts exact fetch from `GET /api/get`
  Future<List<LyricLine>?> _fetchExact({
    required String trackName,
    required String artistName,
    int? durationSeconds,
  }) async {
    final queryParams = <String, String>{
      'track_name': trackName,
      'artist_name': artistName,
    };
    if (durationSeconds != null && durationSeconds > 0) {
      queryParams['duration'] = durationSeconds.toString();
    }

    final uri = Uri.parse('$_baseUrl/get').replace(queryParameters: queryParams);
    final response = await http
        .get(uri, headers: _headers)
        .timeout(const Duration(seconds: 8));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final syncedLyrics = data['syncedLyrics'] as String?;
      if (syncedLyrics != null && syncedLyrics.trim().isNotEmpty) {
        return parseLrc(syncedLyrics);
      }
    } else if (response.statusCode != 404) {
      debugPrint('[LyricsService] _fetchExact returned ${response.statusCode}: ${response.body}');
    }

    return null;
  }

  /// Searches LRCLIB using `/api/search?q={query}`
  Future<List<LyricLine>?> _searchFallback({
    required String query,
    required String trackName,
    String? artistName,
    int? durationSeconds,
  }) async {
    final uri = Uri.parse('$_baseUrl/search').replace(queryParameters: {'q': query});
    final response = await http
        .get(uri, headers: _headers)
        .timeout(const Duration(seconds: 8));

    if (response.statusCode == 200) {
      final List<dynamic> results = jsonDecode(response.body) as List<dynamic>;
      if (results.isEmpty) return null;

      // Find the best match that has synced lyrics
      Map<String, dynamic>? bestMatch;

      for (final item in results) {
        final map = item as Map<String, dynamic>;
        final synced = map['syncedLyrics'] as String?;
        if (synced != null && synced.trim().isNotEmpty) {
          // If duration is provided, check duration match (within 5 seconds)
          if (durationSeconds != null && durationSeconds > 0) {
            final itemDuration = (map['duration'] as num?)?.toInt();
            if (itemDuration != null && (itemDuration - durationSeconds).abs() <= 5) {
              bestMatch = map;
              break;
            }
          }
          bestMatch ??= map;
        }
      }

      if (bestMatch != null) {
        final syncedLyrics = bestMatch['syncedLyrics'] as String?;
        if (syncedLyrics != null && syncedLyrics.trim().isNotEmpty) {
          return parseLrc(syncedLyrics);
        }
      }
    }

    return null;
  }

  /// Parses an LRC string format into a sorted list of [LyricLine]s.
  /// Handles multi-timestamp lines, e.g. `[00:12.30][00:24.50] Hello world`,
  /// and ignores non-timestamp metadata tags like `[length:03:45]`, `[ar:Artist]`.
  List<LyricLine> parseLrc(String lrcContent) {
    final List<LyricLine> lyricLines = [];
    final lines = lrcContent.split('\n');

    for (final rawLine in lines) {
      final trimmed = rawLine.trim();
      if (trimmed.isEmpty) continue;

      // Ignore pure metadata header lines like [ar:Artist], [ti:Title], [length:03:45]
      if (_metadataTagRegex.hasMatch(trimmed) && !_timestampRegex.hasMatch(trimmed)) {
        continue;
      }

      // Find all timestamps in this line
      final matches = _timestampRegex.allMatches(trimmed).toList();
      if (matches.isEmpty) continue;

      // Extract the lyric text after stripping all timestamps and any inline metadata tags
      final text = trimmed
          .replaceAll(_timestampRegex, '')
          .replaceAll(_metadataTagRegex, '')
          .trim();

      // For every timestamp found on the line, add a LyricLine entry
      for (final match in matches) {
        final minutes = int.tryParse(match.group(1) ?? '0') ?? 0;
        final seconds = int.tryParse(match.group(2) ?? '0') ?? 0;
        final fracStr = match.group(3);

        int millis = 0;
        if (fracStr != null && fracStr.isNotEmpty) {
          final frac = int.tryParse(fracStr) ?? 0;
          if (fracStr.length == 1) {
            millis = frac * 100;
          } else if (fracStr.length == 2) {
            millis = frac * 10;
          } else {
            millis = frac;
          }
        }

        final totalMs = (minutes * 60 + seconds) * 1000 + millis;
        lyricLines.add(LyricLine(timestampMs: totalMs, text: text));
      }
    }

    // Sort chronologically
    lyricLines.sort((a, b) => a.timestampMs.compareTo(b.timestampMs));

    return lyricLines;
  }

  /// Normalizes track title and artist name by stripping common noise from YouTube titles
  /// (e.g. "[Official Video]", "(Lyrics)", "feat. XYZ").
  ({String track, String? artist}) cleanMetadata({
    required String trackName,
    String? artistName,
  }) {
    String track = trackName;
    String? artist = artistName;

    // Check if artist was omitted but title contains "Artist - Song"
    if ((artist == null || artist.isEmpty) && track.contains(' - ')) {
      final parts = track.split(' - ');
      if (parts.length >= 2) {
        artist = parts[0].trim();
        track = parts.sublist(1).join(' - ').trim();
      }
    }

    // Clean common YouTube video title clutter
    // 1. Remove bracketed clutter: (Official Video), [4K], (Lyric Video), etc.
    track = track.replaceAll(
      RegExp(r'\s*[\(\[](?:official\s*(?:music\s*)?video|official\s*audio|lyrics?|lyric\s*video|visualizer|audio|4k|hd|remastered)[\)\]]', caseSensitive: false),
      '',
    );

    // 2. Remove balanced bracketed featuring: (feat. Drake), [ft. Drake], (featuring XYZ)
    track = track.replaceAll(
      RegExp(r'\s*[\(\[]\s*\b(?:ft|feat|featuring)\b\.?[^\)\]]*[\)\]]', caseSensitive: false),
      '',
    );

    // 3. Remove standalone featuring with word boundaries: "feat. Drake", "ft. Artist"
    track = track.replaceAll(
      RegExp(r'\s*\b(?:ft|feat|featuring)\b\.?\s+[^\(\[\-]+', caseSensitive: false),
      '',
    );

    track = track.trim();

    if (artist != null) {
      artist = artist
          .replaceAll(RegExp(r'\s*-\s*Topic$', caseSensitive: false), '')
          .replaceAll(RegExp(r'\s*VEVO$', caseSensitive: false), '')
          .replaceAll(RegExp(r'\s*[\(\[]\s*\b(?:ft|feat|featuring)\b\.?[^\)\]]*[\)\]]', caseSensitive: false), '')
          .replaceAll(RegExp(r'\s*\b(?:ft|feat|featuring)\b\.?\s+[^\(\[\-]+', caseSensitive: false), '')
          .trim();
    }

    return (track: track.isEmpty ? trackName : track, artist: artist);
  }

  String _buildCacheKey(String track, String? artist, int? duration) {
    return '${track.toLowerCase().trim()}_${(artist ?? "").toLowerCase().trim()}_${duration ?? 0}';
  }

  /// Clears the in-memory lyrics cache.
  void clearCache() {
    _cache.clear();
  }
}
