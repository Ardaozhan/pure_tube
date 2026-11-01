import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_tube/services/lyrics_service.dart';
import 'package:pure_tube/services/download_service.dart';
import 'package:pure_tube/services/audio_dsp_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LyricsService edge-case & metadata tests', () {
    late LyricsService lyricsService;

    setUp(() {
      lyricsService = LyricsService();
    });

    test('cleanMetadata does NOT corrupt words containing ft (After, Shift, Lift, Gift)', () {
      final res1 = lyricsService.cleanMetadata(trackName: 'After The Rain');
      expect(res1.track, 'After The Rain');

      final res2 = lyricsService.cleanMetadata(trackName: 'Night Shift');
      expect(res2.track, 'Night Shift');

      final res3 = lyricsService.cleanMetadata(trackName: 'Lift Me Up');
      expect(res3.track, 'Lift Me Up');

      final res4 = lyricsService.cleanMetadata(trackName: 'Gift of Life');
      expect(res4.track, 'Gift of Life');
    });

    test('cleanMetadata cleanly removes balanced bracketed featuring and official video tags', () {
      final res1 = lyricsService.cleanMetadata(trackName: 'Gods Plan (feat. Drake) (Official Video)');
      expect(res1.track, 'Gods Plan');

      final res2 = lyricsService.cleanMetadata(trackName: 'In The End [ft. Chester Bennington] [4K]');
      expect(res2.track, 'In The End');

      final res3 = lyricsService.cleanMetadata(trackName: 'Starboy (featuring Daft Punk)');
      expect(res3.track, 'Starboy');

      final res4 = lyricsService.cleanMetadata(trackName: 'Sunflower feat. Swae Lee');
      expect(res4.track, 'Sunflower');
    });

    test('cleanMetadata splits "Artist - Title" properly', () {
      final res = lyricsService.cleanMetadata(trackName: 'Queen - Bohemian Rhapsody (Official Music Video)');
      expect(res.artist, 'Queen');
      expect(res.track, 'Bohemian Rhapsody');
    });

    test('cleanMetadata cleanly removes featuring from artist parameter', () {
      final res1 = lyricsService.cleanMetadata(
        trackName: 'Starboy',
        artistName: 'The Weeknd feat. Daft Punk',
      );
      expect(res1.artist, 'The Weeknd');
      expect(res1.track, 'Starboy');

      final res2 = lyricsService.cleanMetadata(
        trackName: 'Fortnight',
        artistName: 'Taylor Swift (feat. Post Malone) - Topic',
      );
      expect(res2.artist, 'Taylor Swift');
      expect(res2.track, 'Fortnight');
    });

    test('parseLrc ignores non-timestamp metadata header tags', () {
      const lrcWithHeaders = '''
[ti:Shape of You]
[ar:Ed Sheeran]
[al:Divide]
[length:03:53]
[offset:0]
[00:10.50]The club isn't the best place to find a lover
[00:15.20]So the bar is where I go
''';

      final parsed = lyricsService.parseLrc(lrcWithHeaders);
      expect(parsed.length, 2);
      expect(parsed[0].timestampMs, 10500);
      expect(parsed[0].text, "The club isn't the best place to find a lover");
      expect(parsed[1].timestampMs, 15200);
      expect(parsed[1].text, "So the bar is where I go");
    });

    test('parseLrc strips inline metadata tags without corrupting lyrics', () {
      const lrcInline = '[00:05.10][ar:Ed Sheeran] Me and my friends at the table doing shots';
      final parsed = lyricsService.parseLrc(lrcInline);
      expect(parsed.length, 1);
      expect(parsed[0].timestampMs, 5100);
      expect(parsed[0].text, 'Me and my friends at the table doing shots');
    });

    test('parseLrc correctly handles multiple timestamps on a single line', () {
      const multiTsLrc = '[00:02.00][00:08.50] Repeated chorus line';
      final parsed = lyricsService.parseLrc(multiTsLrc);
      expect(parsed.length, 2);
      expect(parsed[0].timestampMs, 2000);
      expect(parsed[0].text, 'Repeated chorus line');
      expect(parsed[1].timestampMs, 8500);
      expect(parsed[1].text, 'Repeated chorus line');
    });
  });

  group('Id3v2Tagger container safety tests', () {
    test('tagFile ignores non-MP3 files (e.g. .webm, .mp4)', () async {
      final tempDir = Directory.systemTemp.createTempSync('puretube_id3_test_');
      final webmFile = File('${tempDir.path}/sample.webm');
      final originalBytes = [0x1A, 0x45, 0xDF, 0xA3, 0x01, 0x02]; // EBML header bytes
      await webmFile.writeAsBytes(originalBytes);

      await Id3v2Tagger.tagFile(
        file: webmFile,
        title: 'Test Song',
        artist: 'Test Artist',
      );

      final postBytes = await webmFile.readAsBytes();
      // Must NOT be prepended with ID3 tag ('I', 'D', '3')
      expect(postBytes, equals(originalBytes));
      expect(postBytes[0], 0x1A);
      expect(postBytes[1], 0x45);

      tempDir.deleteSync(recursive: true);
    });

    test('tagFileWithThumbnailUrl safely ignores non-MP3 files without fetching thumbnail', () async {
      final tempDir = Directory.systemTemp.createTempSync('puretube_thumb_test_');
      final mp4File = File('${tempDir.path}/video.mp4');
      await mp4File.writeAsBytes([0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70]);

      await Id3v2Tagger.tagFileWithThumbnailUrl(
        file: mp4File,
        title: 'Video Title',
        thumbnailUrl: 'https://invalid.example.com/nonexistent_image.jpg',
      );

      final bytes = await mp4File.readAsBytes();
      expect(bytes[4], 0x66); // 'f'
      expect(bytes[5], 0x74); // 't'
      tempDir.deleteSync(recursive: true);
    });

    test('buildId3Tag correctly creates standard ID3v2.3 structure', () {
      final tag = Id3v2Tagger.buildId3Tag(
        title: 'Song Title',
        artist: 'Artist Name',
        album: 'Album Name',
      );

      // Verify ID3v2 header
      expect(tag[0], 0x49); // 'I'
      expect(tag[1], 0x44); // 'D'
      expect(tag[2], 0x33); // '3'
      expect(tag[3], 0x03); // ID3v2.3
      expect(tag[4], 0x00); // revision
      expect(tag[5], 0x00); // flags
      expect(tag.length, greaterThan(10));
    });
  });

  group('AudioDspService formatters and presets tests', () {
    test('formatFrequency formats Hz and kHz correctly', () {
      expect(AudioDspService.formatFrequency(60), '60 Hz');
      expect(AudioDspService.formatFrequency(910), '910 Hz');
      expect(AudioDspService.formatFrequency(1000), '1 kHz');
      expect(AudioDspService.formatFrequency(3600), '3.6 kHz');
      expect(AudioDspService.formatFrequency(14000), '14 kHz');
    });

    test('formatGainDb formats millibels to decibels correctly', () {
      expect(AudioDspService.formatGainDb(0), '0 dB');
      expect(AudioDspService.formatGainDb(600), '+6.0 dB');
      expect(AudioDspService.formatGainDb(-200), '-2.0 dB');
      expect(AudioDspService.formatGainDb(150), '+1.5 dB');
    });

    test('presetNames list contains standard presets', () {
      expect(AudioDspService.presetNames, contains('Flat'));
      expect(AudioDspService.presetNames, contains('Bass Boost'));
      expect(AudioDspService.presetNames, contains('Vocal Booster'));
      expect(AudioDspService.presetNames, contains('Rock'));
      expect(AudioDspService.presetNames, contains('Electronic'));
      expect(AudioDspService.presetNames, contains('Custom'));
    });

    test('AudioDspService handles concurrent init calls gracefully', () async {
      final service = AudioDspService();
      // Invoke multiple concurrent init calls
      await Future.wait([
        service.init(),
        service.init(),
        service.init(),
      ]);
      expect(service.isInitialized, isTrue);
    });
  });
}
