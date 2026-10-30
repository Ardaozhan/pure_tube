import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Preset definition for Equalizer, Bass Boost, and Loudness Enhancer.
class DspPreset {
  final String name;
  final List<int> bandLevels; // in mB (milliBels)
  final int bassBoostStrength; // 0 to 1000
  final int loudnessGainMb; // 0 to 2000

  const DspPreset({
    required this.name,
    required this.bandLevels,
    this.bassBoostStrength = 0,
    this.loudnessGainMb = 0,
  });
}

/// Service providing unified Android Native Audio DSP control:
/// Equalizer (10-band or 5-band), Bass Boost, and Loudness Enhancer.
class AudioDspService extends ChangeNotifier {
  static final AudioDspService _instance = AudioDspService._internal();
  factory AudioDspService() => _instance;
  AudioDspService._internal();

  static const MethodChannel _channel = MethodChannel('com.puretube.pure_tube/audio_dsp');

  // Persistence keys
  static const String _prefEnabledKey = 'dsp_is_enabled';
  static const String _prefPresetKey = 'dsp_active_preset';
  static const String _prefBassKey = 'dsp_bass_boost_strength';
  static const String _prefLoudnessKey = 'dsp_loudness_gain_mb';
  static const String _prefBandPrefix = 'dsp_band_level_';

  bool _isInitialized = false;
  bool _isSupported = false;
  bool _isEnabled = false;
  int _numberOfBands = 5;
  int _minFreq = 60;
  int _maxFreq = 14000;
  List<int> _centerFreqs = [60, 230, 910, 3600, 14000];
  List<int> _bandLevelRange = [-1500, 1500]; // [min, max] in mB
  final Map<int, int> _bandLevels = {}; // bandIndex -> level (mB)
  int _bassBoostStrength = 0; // 0 to 1000
  int _loudnessGainMb = 0; // 0 to 2000
  String _currentPreset = 'Flat';
  bool _hasBassBoost = false;
  bool _hasLoudnessEnhancer = false;

  // Getters
  bool get isInitialized => _isInitialized;
  bool get isSupported => _isSupported;
  bool get isEnabled => _isEnabled;
  int get numberOfBands => _numberOfBands;
  int get minFreq => _minFreq;
  int get maxFreq => _maxFreq;
  List<int> get centerFreqs => List.unmodifiable(_centerFreqs);
  List<int> get bandLevelRange => List.unmodifiable(_bandLevelRange);
  int get minBandLevel => _bandLevelRange.isNotEmpty ? _bandLevelRange[0] : -1500;
  int get maxBandLevel => _bandLevelRange.length > 1 ? _bandLevelRange[1] : 1500;
  Map<int, int> get bandLevels => Map.unmodifiable(_bandLevels);
  int get bassBoostStrength => _bassBoostStrength;
  int get loudnessGainMb => _loudnessGainMb;
  String get currentPreset => _currentPreset;
  bool get hasBassBoost => _hasBassBoost;
  bool get hasLoudnessEnhancer => _hasLoudnessEnhancer;

  /// Available presets
  static const List<String> presetNames = [
    'Flat',
    'Bass Boost',
    'Vocal Booster',
    'Rock',
    'Electronic',
    'Custom',
  ];

  /// Initialize DSP engine, read hardware capabilities, and restore saved state.
  Future<void> init() async {
    if (_isInitialized) return;

    try {
      final res = await _channel.invokeMapMethod<String, dynamic>('initDsp');
      if (res != null) {
        _isSupported = res['isSupported'] as bool? ?? false;
        _numberOfBands = (res['numberOfBands'] as num?)?.toInt() ?? 5;
        _minFreq = (res['minFreq'] as num?)?.toInt() ?? 60;
        _maxFreq = (res['maxFreq'] as num?)?.toInt() ?? 14000;

        final rawFreqs = res['centerFreqs'] as List<dynamic>?;
        if (rawFreqs != null && rawFreqs.isNotEmpty) {
          _centerFreqs = rawFreqs.map((f) => (f as num).toInt()).toList();
        }

        final rawRange = res['bandLevelRange'] as List<dynamic>?;
        if (rawRange != null && rawRange.length >= 2) {
          _bandLevelRange = [
            (rawRange[0] as num).toInt(),
            (rawRange[1] as num).toInt(),
          ];
        }

        _hasBassBoost = res['hasBassBoost'] as bool? ?? true;
        _hasLoudnessEnhancer = res['hasLoudnessEnhancer'] as bool? ?? true;
      }
    } catch (e) {
      debugPrint('[AudioDspService] Hardware initDsp failed: $e');
      _isSupported = false;
    }

    // Default band levels to 0
    for (int i = 0; i < _numberOfBands; i++) {
      _bandLevels[i] = 0;
    }

    // Restore from SharedPreferences
    await _restoreSettings();
    _isInitialized = true;
    notifyListeners();
  }

  /// Restores DSP settings from SharedPreferences
  Future<void> _restoreSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _isEnabled = prefs.getBool(_prefEnabledKey) ?? false;
      _currentPreset = prefs.getString(_prefPresetKey) ?? 'Flat';
      _bassBoostStrength = prefs.getInt(_prefBassKey) ?? 0;
      _loudnessGainMb = prefs.getInt(_prefLoudnessKey) ?? 0;

      for (int i = 0; i < _numberOfBands; i++) {
        final savedLevel = prefs.getInt('$_prefBandPrefix$i');
        if (savedLevel != null) {
          _bandLevels[i] = savedLevel.clamp(minBandLevel, maxBandLevel);
        } else {
          _bandLevels[i] = 0;
        }
      }

      // Apply initial settings if DSP is supported
      if (_isSupported) {
        await _channel.invokeMethod('setEnabled', {'enabled': _isEnabled});

        for (final entry in _bandLevels.entries) {
          await _channel.invokeMethod('setBandLevel', {
            'band': entry.key,
            'level': entry.value,
          });
        }

        if (_hasBassBoost) {
          await _channel.invokeMethod('setBassBoost', {
            'strength': _bassBoostStrength,
          });
        }

        if (_hasLoudnessEnhancer) {
          await _channel.invokeMethod('setLoudnessEnhancer', {
            'gainMb': _loudnessGainMb,
          });
        }
      }
    } catch (e) {
      debugPrint('[AudioDspService] Failed to restore settings: $e');
    }
  }

  /// Master switch to enable or bypass all DSP effects.
  Future<void> setEnabled(bool enabled) async {
    _isEnabled = enabled;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefEnabledKey, enabled);

      if (_isSupported) {
        await _channel.invokeMethod('setEnabled', {'enabled': enabled});
      }
    } catch (e) {
      debugPrint('[AudioDspService] Error setting enabled: $e');
    }
  }

  /// Sets level for a specific EQ band in milliBels (mB).
  Future<void> setBandLevel(int band, int levelMb) async {
    final clampedLevel = levelMb.clamp(minBandLevel, maxBandLevel);
    _bandLevels[band] = clampedLevel;
    _currentPreset = 'Custom';
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('$_prefBandPrefix$band', clampedLevel);
      await prefs.setString(_prefPresetKey, 'Custom');

      if (_isSupported) {
        await _channel.invokeMethod('setBandLevel', {
          'band': band,
          'level': clampedLevel,
        });
      }
    } catch (e) {
      debugPrint('[AudioDspService] Error setting band $band level: $e');
    }
  }

  /// Sets Bass Boost strength (0 to 1000).
  Future<void> setBassBoost(int strength) async {
    final clampedStrength = strength.clamp(0, 1000);
    _bassBoostStrength = clampedStrength;
    if (_currentPreset != 'Custom') {
      _currentPreset = 'Custom';
    }
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_prefBassKey, clampedStrength);
      await prefs.setString(_prefPresetKey, 'Custom');

      if (_isSupported && _hasBassBoost) {
        await _channel.invokeMethod('setBassBoost', {
          'strength': clampedStrength,
        });
      }
    } catch (e) {
      debugPrint('[AudioDspService] Error setting bass boost: $e');
    }
  }

  /// Sets Loudness Enhancer target gain (0 to 2000 mB, i.e. 0 to +20dB).
  Future<void> setLoudnessEnhancer(int gainMb) async {
    final clampedGain = gainMb.clamp(0, 2000);
    _loudnessGainMb = clampedGain;
    if (_currentPreset != 'Custom') {
      _currentPreset = 'Custom';
    }
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_prefLoudnessKey, clampedGain);
      await prefs.setString(_prefPresetKey, 'Custom');

      if (_isSupported && _hasLoudnessEnhancer) {
        await _channel.invokeMethod('setLoudnessEnhancer', {
          'gainMb': clampedGain,
        });
      }
    } catch (e) {
      debugPrint('[AudioDspService] Error setting loudness enhancer: $e');
    }
  }

  /// Applies one of the standard audio presets.
  Future<void> applyPreset(String presetName) async {
    final preset = _generatePreset(presetName);
    _currentPreset = preset.name;
    _bassBoostStrength = preset.bassBoostStrength;
    _loudnessGainMb = preset.loudnessGainMb;

    for (int i = 0; i < _numberOfBands; i++) {
      if (i < preset.bandLevels.length) {
        _bandLevels[i] = preset.bandLevels[i].clamp(minBandLevel, maxBandLevel);
      } else {
        _bandLevels[i] = 0;
      }
    }

    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefPresetKey, preset.name);
      await prefs.setInt(_prefBassKey, _bassBoostStrength);
      await prefs.setInt(_prefLoudnessKey, _loudnessGainMb);

      for (int i = 0; i < _numberOfBands; i++) {
        await prefs.setInt('$_prefBandPrefix$i', _bandLevels[i] ?? 0);
      }

      if (_isSupported) {
        for (final entry in _bandLevels.entries) {
          await _channel.invokeMethod('setBandLevel', {
            'band': entry.key,
            'level': entry.value,
          });
        }
        if (_hasBassBoost) {
          await _channel.invokeMethod('setBassBoost', {
            'strength': _bassBoostStrength,
          });
        }
        if (_hasLoudnessEnhancer) {
          await _channel.invokeMethod('setLoudnessEnhancer', {
            'gainMb': _loudnessGainMb,
          });
        }
      }
    } catch (e) {
      debugPrint('[AudioDspService] Error applying preset $presetName: $e');
    }
  }

  /// Resets all bands and effects to flat (0).
  Future<void> resetToFlat() async {
    await applyPreset('Flat');
  }

  /// Generates band levels for the given preset according to the device's band count (5 or 10).
  DspPreset _generatePreset(String name) {
    final is10Band = _numberOfBands >= 8;

    switch (name) {
      case 'Bass Boost':
        return DspPreset(
          name: name,
          bandLevels: is10Band
              ? [700, 600, 450, 200, 0, 0, 0, 0, 0, 0]
              : [600, 450, 0, 0, 0],
          bassBoostStrength: 700,
          loudnessGainMb: 150,
        );
      case 'Vocal Booster':
        return DspPreset(
          name: name,
          bandLevels: is10Band
              ? [-200, -100, 0, 200, 500, 600, 400, 200, 0, -100]
              : [-200, 150, 500, 350, -100],
          bassBoostStrength: 0,
          loudnessGainMb: 0,
        );
      case 'Rock':
        return DspPreset(
          name: name,
          bandLevels: is10Band
              ? [500, 400, 200, -100, -200, 0, 200, 350, 500, 550]
              : [500, 200, -200, 250, 500],
          bassBoostStrength: 350,
          loudnessGainMb: 0,
        );
      case 'Electronic':
        return DspPreset(
          name: name,
          bandLevels: is10Band
              ? [650, 550, 350, 100, 0, 0, 200, 350, 600, 650]
              : [600, 300, 0, 300, 600],
          bassBoostStrength: 600,
          loudnessGainMb: 300,
        );
      case 'Flat':
      default:
        return DspPreset(
          name: 'Flat',
          bandLevels: List.filled(_numberOfBands, 0),
          bassBoostStrength: 0,
          loudnessGainMb: 0,
        );
    }
  }

  /// Helper formatters
  static String formatFrequency(int freqHz) {
    if (freqHz >= 1000) {
      final khz = freqHz / 1000.0;
      return khz == khz.roundToDouble()
          ? '${khz.toInt()} kHz'
          : '${khz.toStringAsFixed(1)} kHz';
    }
    return '$freqHz Hz';
  }

  static String formatGainDb(int gainMb) {
    final db = gainMb / 100.0;
    if (db == 0) return '0 dB';
    final sign = db > 0 ? '+' : '';
    return '$sign${db.toStringAsFixed(1)} dB';
  }
}
