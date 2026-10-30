import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/audio_dsp_service.dart';

/// Sleek modal bottom sheet for Equalizer & Audio DSP control.
/// Supports 5-band or 10-band hardware Equalizer, Bass Boost (%0 - %100),
/// and Loudness Enhancer (+0dB to +20dB).
class EqualizerSheet extends StatelessWidget {
  const EqualizerSheet({super.key});

  /// Static helper to display the equalizer sheet from anywhere in the app.
  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const EqualizerSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dspService = AudioDspService();

    return ListenableBuilder(
      listenable: dspService,
      builder: (context, _) {
        final isEnabled = dspService.isEnabled;

        return Container(
          height: MediaQuery.of(context).size.height * 0.82,
          decoration: const BoxDecoration(
            color: Color(0xFF0C0B0A), // OLED pitch dark charcoal
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            border: Border(
              top: BorderSide(
                color: Color(0x33FFD700),
                width: 1.2,
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 24,
                spreadRadius: 4,
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                _buildDragHandle(),
                _buildHeader(context, dspService),
                const SizedBox(height: 8),
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildPresetSelector(dspService, isEnabled),
                        const SizedBox(height: 20),
                        _buildEqualizerSection(dspService, isEnabled),
                        const SizedBox(height: 20),
                        _buildHardwareEnhancersSection(dspService, isEnabled),
                        const SizedBox(height: 20),
                        _buildFooterActions(dspService, isEnabled),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDragHandle() {
    return Center(
      child: Container(
        width: 44,
        height: 4,
        margin: const EdgeInsets.only(top: 12, bottom: 8),
        decoration: BoxDecoration(
          color: const Color(0x4DFFFFFF),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, AudioDspService dsp) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: dsp.isEnabled
                  ? const Color(0x26FFD700)
                  : const Color(0x0FFFFFFF),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: dsp.isEnabled
                    ? const Color(0x80FFD700)
                    : const Color(0x1AFFFFFF),
                width: 1,
              ),
            ),
            child: Icon(
              Icons.graphic_eq_rounded,
              color: dsp.isEnabled
                  ? const Color(0xFFFFD700)
                  : const Color(0x80FFFFFF),
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'PureDSP Studio',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                Text(
                  dsp.isSupported
                      ? '${dsp.numberOfBands} Bant Donanımsal Ekolayzer'
                      : 'Ekolayzer Emülasyonu',
                  style: const TextStyle(
                    color: Color(0x80FFFFFF),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          // Master Toggle Switch
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                dsp.isEnabled ? 'AÇIK' : 'BYPASS',
                style: TextStyle(
                  color: dsp.isEnabled
                      ? const Color(0xFFFFD700)
                      : const Color(0x66FFFFFF),
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(width: 8),
              Switch(
                value: dsp.isEnabled,
                activeColor: const Color(0xFFFFD700),
                activeTrackColor: const Color(0x59FFD700),
                inactiveThumbColor: const Color(0x80FFFFFF),
                inactiveTrackColor: const Color(0x1FFFFFFF),
                onChanged: (val) {
                  HapticFeedback.lightImpact();
                  dsp.setEnabled(val);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPresetSelector(AudioDspService dsp, bool isEnabled) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'ÖN AYARLAR',
          style: TextStyle(
            color: Color(0x80FFFFFF),
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 38,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: AudioDspService.presetNames.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final presetName = AudioDspService.presetNames[index];
              final isSelected = (dsp.currentPreset == presetName);

              return Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: isEnabled
                      ? () {
                          HapticFeedback.selectionClick();
                          dsp.applyPreset(presetName);
                        }
                      : null,
                  borderRadius: BorderRadius.circular(20),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected && isEnabled
                          ? const Color(0x2EFFD700)
                          : const Color(0x0FFFFFFF),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isSelected && isEnabled
                            ? const Color(0xFFFFD700)
                            : const Color(0x1FFFFFFF),
                        width: isSelected ? 1.4 : 1.0,
                      ),
                      boxShadow: isSelected && isEnabled
                          ? const [
                              BoxShadow(
                                color: Color(0x26FFD700),
                                blurRadius: 10,
                                spreadRadius: 1,
                              ),
                            ]
                          : null,
                    ),
                    child: Center(
                      child: Text(
                        presetName,
                        style: TextStyle(
                          color: isSelected && isEnabled
                              ? const Color(0xFFFFD700)
                              : (isEnabled
                                  ? const Color(0xCCFFFFFF)
                                  : const Color(0x40FFFFFF)),
                          fontSize: 13,
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildEqualizerSection(AudioDspService dsp, bool isEnabled) {
    final numBands = dsp.numberOfBands;
    final freqs = dsp.centerFreqs;
    final minLevel = dsp.minBandLevel;
    final maxLevel = dsp.maxBandLevel;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF141311),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0x14FFFFFF),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'EKOLAYZER BANTLARI',
                style: TextStyle(
                  color: Color(0x80FFFFFF),
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
              Text(
                '${AudioDspService.formatGainDb(maxLevel)} / ${AudioDspService.formatGainDb(minLevel)}',
                style: const TextStyle(
                  color: Color(0x4DFFFFFF),
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Horizontal scrolling vertical sliders
          SizedBox(
            height: 210,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(numBands, (index) {
                  final freqHz = index < freqs.length ? freqs[index] : 1000;
                  final currentLevel = dsp.bandLevels[index] ?? 0;

                  return Container(
                    width: 58,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    child: Column(
                      children: [
                        // Gain label at top
                        Text(
                          AudioDspService.formatGainDb(currentLevel),
                          style: TextStyle(
                            color: isEnabled
                                ? (currentLevel != 0
                                    ? const Color(0xFFFFD700)
                                    : const Color(0xB3FFFFFF))
                                : const Color(0x40FFFFFF),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Vertical Slider
                        Expanded(
                          child: RotatedBox(
                            quarterTurns: 3,
                            child: SliderTheme(
                              data: SliderThemeData(
                                trackHeight: 4,
                                activeTrackColor: isEnabled
                                    ? const Color(0xFFFFD700)
                                    : const Color(0x40FFFFFF),
                                inactiveTrackColor: const Color(0x1FFFFFFF),
                                thumbColor: isEnabled
                                    ? const Color(0xFFFFD700)
                                    : const Color(0x66FFFFFF),
                                thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 7,
                                  pressedElevation: 4,
                                ),
                                overlayColor: const Color(0x26FFD700),
                                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                              ),
                              child: Slider(
                                value: currentLevel.toDouble(),
                                min: minLevel.toDouble(),
                                max: maxLevel.toDouble(),
                                onChanged: isEnabled
                                    ? (val) {
                                        dsp.setBandLevel(index, val.toInt());
                                      }
                                    : null,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Frequency label at bottom
                        Text(
                          AudioDspService.formatFrequency(freqHz),
                          style: TextStyle(
                            color: isEnabled
                                ? const Color(0x80FFFFFF)
                                : const Color(0x33FFFFFF),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHardwareEnhancersSection(AudioDspService dsp, bool isEnabled) {
    final bassPercent = (dsp.bassBoostStrength / 10).round(); // 0 - 100%
    final loudnessDb = (dsp.loudnessGainMb / 100.0).toStringAsFixed(1); // 0.0 - 20.0 dB

    return Column(
      children: [
        // Bass Boost Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF141311),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: const Color(0x14FFFFFF),
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: isEnabled && dsp.bassBoostStrength > 0
                              ? const Color(0x26FFD700)
                              : const Color(0x0FFFFFFF),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.speaker_group_rounded,
                          color: isEnabled && dsp.bassBoostStrength > 0
                              ? const Color(0xFFFFD700)
                              : const Color(0x66FFFFFF),
                          size: 16,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'Bass Boost',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    '$bassPercent%',
                    style: TextStyle(
                      color: isEnabled && dsp.bassBoostStrength > 0
                          ? const Color(0xFFFFD700)
                          : const Color(0x80FFFFFF),
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SliderTheme(
                data: SliderThemeData(
                  trackHeight: 4,
                  activeTrackColor: isEnabled
                      ? const Color(0xFFFFD700)
                      : const Color(0x40FFFFFF),
                  inactiveTrackColor: const Color(0x1FFFFFFF),
                  thumbColor: isEnabled
                      ? const Color(0xFFFFD700)
                      : const Color(0x66FFFFFF),
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                  overlayColor: const Color(0x26FFD700),
                ),
                child: Slider(
                  value: dsp.bassBoostStrength.toDouble(),
                  min: 0,
                  max: 1000,
                  onChanged: isEnabled
                      ? (val) {
                          dsp.setBassBoost(val.toInt());
                        }
                      : null,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // Loudness Enhancer Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF141311),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: const Color(0x14FFFFFF),
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: isEnabled && dsp.loudnessGainMb > 0
                              ? const Color(0x26FFD700)
                              : const Color(0x0FFFFFFF),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.bolt_rounded,
                          color: isEnabled && dsp.loudnessGainMb > 0
                              ? const Color(0xFFFFD700)
                              : const Color(0x66FFFFFF),
                          size: 16,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'Loudness Enhancer',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    '+$loudnessDb dB',
                    style: TextStyle(
                      color: isEnabled && dsp.loudnessGainMb > 0
                          ? const Color(0xFFFFD700)
                          : const Color(0x80FFFFFF),
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SliderTheme(
                data: SliderThemeData(
                  trackHeight: 4,
                  activeTrackColor: isEnabled
                      ? const Color(0xFFFFD700)
                      : const Color(0x40FFFFFF),
                  inactiveTrackColor: const Color(0x1FFFFFFF),
                  thumbColor: isEnabled
                      ? const Color(0xFFFFD700)
                      : const Color(0x66FFFFFF),
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                  overlayColor: const Color(0x26FFD700),
                ),
                child: Slider(
                  value: dsp.loudnessGainMb.toDouble(),
                  min: 0,
                  max: 2000,
                  onChanged: isEnabled
                      ? (val) {
                          dsp.setLoudnessEnhancer(val.toInt());
                        }
                      : null,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFooterActions(AudioDspService dsp, bool isEnabled) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        TextButton.icon(
          onPressed: isEnabled
              ? () {
                  HapticFeedback.mediumImpact();
                  dsp.resetToFlat();
                }
              : null,
          icon: const Icon(
            Icons.refresh_rounded,
            color: Color(0x80FFFFFF),
            size: 18,
          ),
          label: const Text(
            'Düz Seviyeye Sıfırla (Flat)',
            style: TextStyle(
              color: Color(0x80FFFFFF),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
