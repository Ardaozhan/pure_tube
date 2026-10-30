import 'package:flutter_test/flutter_test.dart';
import 'package:pure_tube/services/ryd_service.dart';
import 'package:pure_tube/services/sponsorblock_service.dart';

void main() {
  group('RydVotes model tests', () {
    test('Correctly parses API json and computes metrics', () {
      final json = {
        'id': 'dQw4w9WgXcQ',
        'likes': 15200000,
        'dislikes': 380000,
        'rating': 4.88,
        'viewCount': 1400000000,
      };

      final votes = RydVotes.fromJson(json);

      expect(votes.videoId, 'dQw4w9WgXcQ');
      expect(votes.likes, 15200000);
      expect(votes.dislikes, 380000);
      expect(votes.formattedLikes, '15.2M');
      expect(votes.formattedDislikes, '380K');
      expect(votes.rating, 4.88);
      expect(votes.viewCount, 1400000000);
      expect(votes.likePercentage, closeTo(97.56, 0.1));

      final map = votes.toMap();
      expect(map['formattedLikes'], '15.2M');
      expect(map['formattedDislikes'], '380K');
    });

    test('Handles zero votes and edge formatting', () {
      final json = {
        'id': 'zeroVotes',
        'likes': 0,
        'dislikes': 0,
      };
      final votes = RydVotes.fromJson(json);
      expect(votes.likePercentage, 0.0);
      expect(votes.formattedLikes, '0');
      expect(votes.formattedDislikes, '0');
    });
  });

  group('SponsorSegment model tests', () {
    test('Correctly parses standard API segment array format', () {
      final json = {
        'category': 'sponsor',
        'segment': [45.5, 95.0],
        'UUID': 'uuid-12345',
      };

      final seg = SponsorSegment.fromJson(json);
      expect(seg.category, 'sponsor');
      expect(seg.startTime, 45.5);
      expect(seg.endTime, 95.0);
      expect(seg.duration, 49.5);
      expect(seg.uuid, 'uuid-12345');
      expect(seg.categoryTitle, 'Sponsor');
      expect(seg.categoryColor, '#00d66c');
      expect(seg.contains(50.0), isTrue);
      expect(seg.contains(30.0), isFalse);
      expect(seg.contains(96.0), isFalse);
    });

    test('Helper findActiveSegment correctly locates active segment', () {
      final segments = [
        const SponsorSegment(
          category: 'intro',
          startTime: 0.0,
          endTime: 15.0,
          uuid: 'intro-1',
        ),
        const SponsorSegment(
          category: 'sponsor',
          startTime: 120.0,
          endTime: 180.0,
          uuid: 'spons-1',
        ),
      ];

      final active = SponsorBlockService.instance.findActiveSegment(segments, 130.0);
      expect(active, isNotNull);
      expect(active!.category, 'sponsor');

      final none = SponsorBlockService.instance.findActiveSegment(segments, 50.0);
      expect(none, isNull);
    });
  });
}
