import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/pip_service.dart';
import '../services/update_service.dart';
import '../widgets/equalizer_sheet.dart';

class SettingsDialog extends StatefulWidget {
  final int totalBlockedCount;
  final Function(bool adBlock, bool sponsorBlock, bool ryd) onChanged;
  final VoidCallback? onResetCounter;

  const SettingsDialog({
    super.key,
    required this.totalBlockedCount,
    required this.onChanged,
    this.onResetCounter,
  });

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  bool _adBlockEnabled = true;
  bool _sponsorBlockEnabled = true;
  bool _rydEnabled = true;
  bool _ultraSmoothMode = true;
  bool _autoPipEnabled = true;
  bool _isCheckingUpdate = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _adBlockEnabled = prefs.getBool('adBlockEnabled') ?? true;
        _sponsorBlockEnabled = prefs.getBool('sponsorBlockEnabled') ?? true;
        _rydEnabled = prefs.getBool('rydEnabled') ?? true;
        _ultraSmoothMode = prefs.getBool('ultraSmoothMode') ?? true;
        _autoPipEnabled = prefs.getBool('autoPipEnabled') ?? true;
      });
    }
  }

  Future<void> _saveSetting(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
    if (key == 'autoPipEnabled') {
      await PipService.setAutoPip(value);
    }
    widget.onChanged(_adBlockEnabled, _sponsorBlockEnabled, _rydEnabled);
  }

  Future<void> _manualCheckUpdate() async {
    setState(() => _isCheckingUpdate = true);
    await UpdateService.check(context, isManual: true);
    if (mounted) {
      setState(() => _isCheckingUpdate = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF0C0C0C), // OLED pitch black
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: const BorderSide(color: Colors.white12, width: 0.8),
      ),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      actionsPadding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
      title: const Row(
        children: [
          Icon(Icons.tune_rounded, color: Colors.redAccent, size: 24),
          SizedBox(width: 10),
          Text(
            'PureTube Ayarları',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Stats Banner (Zero-Ad Shield)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.greenAccent.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.25)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.shield_rounded, color: Colors.greenAccent, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Kalıcı Engellenen Reklamlar',
                            style: TextStyle(color: Colors.white70, fontSize: 11.5),
                          ),
                          Text(
                            '${widget.totalBlockedCount} adet reklam & izleyici',
                            style: const TextStyle(
                              color: Colors.greenAccent,
                              fontSize: 13.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (widget.onResetCounter != null)
                      TextButton(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: () {
                          widget.onResetCounter!();
                          Navigator.pop(context);
                        },
                        child: const Text('Sıfırla', style: TextStyle(color: Colors.white38, fontSize: 11)),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Switches
              SwitchListTile(
                activeColor: Colors.redAccent,
                contentPadding: EdgeInsets.zero,
                title: const Text('Reklam Engelleme', style: TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w600)),
                subtitle: const Text('Video ve banner reklamlarını filtreler', style: TextStyle(color: Colors.white54, fontSize: 11.5)),
                value: _adBlockEnabled,
                onChanged: (val) {
                  setState(() => _adBlockEnabled = val);
                  _saveSetting('adBlockEnabled', val);
                },
              ),

              SwitchListTile(
                activeColor: Colors.redAccent,
                contentPadding: EdgeInsets.zero,
                title: const Text('SponsorBlock v2', style: TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w600)),
                subtitle: const Text('Sponsorlu bölümleri ve introları otomatik atlar', style: TextStyle(color: Colors.white54, fontSize: 11.5)),
                value: _sponsorBlockEnabled,
                onChanged: (val) {
                  setState(() => _sponsorBlockEnabled = val);
                  _saveSetting('sponsorBlockEnabled', val);
                },
              ),

              SwitchListTile(
                activeColor: Colors.redAccent,
                contentPadding: EdgeInsets.zero,
                title: const Text('Return YouTube Dislike (RYD)', style: TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w600)),
                subtitle: const Text('Kaldırılan beğenmeme (dislike) sayılarını gösterir', style: TextStyle(color: Colors.white54, fontSize: 11.5)),
                value: _rydEnabled,
                onChanged: (val) {
                  setState(() => _rydEnabled = val);
                  _saveSetting('rydEnabled', val);
                },
              ),

              SwitchListTile(
                activeColor: Colors.redAccent,
                contentPadding: EdgeInsets.zero,
                title: const Text('144Hz AMOLED Ultra Akıcı Mod', style: TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w600)),
                subtitle: const Text('Xiaomi 14T ve yüksek yenileme hızlı AMOLED ekranlar için ultra akıcı GPU rendering (144Hz)', style: TextStyle(color: Colors.white54, fontSize: 11.5)),
                value: _ultraSmoothMode,
                onChanged: (val) {
                  setState(() => _ultraSmoothMode = val);
                  _saveSetting('ultraSmoothMode', val);
                },
              ),

              SwitchListTile(
                activeColor: Colors.redAccent,
                contentPadding: EdgeInsets.zero,
                title: const Text('Otomatik PiP (Küçük Pencere)', style: TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w600)),
                subtitle: const Text('Ana ekrana dönüldüğünde küçük pencereye geçer', style: TextStyle(color: Colors.white54, fontSize: 11.5)),
                value: _autoPipEnabled,
                onChanged: (val) {
                  setState(() => _autoPipEnabled = val);
                  _saveSetting('autoPipEnabled', val);
                },
              ),

              const SizedBox(height: 10),

              // PureDSP Equalizer Shortcut Tile
              Container(
                margin: const EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF141414),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0x33FFD700)),
                ),
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.tune_rounded, color: Color(0xFFFFD700), size: 24),
                  title: const Text(
                    'PureDSP Ekolayzer & Bass Boost',
                    style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text(
                    '10-bant donanım ekolayzeri, Bass & Loudness ayarları',
                    style: TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded, color: Colors.white38, size: 20),
                  onTap: () {
                    Navigator.pop(context);
                    EqualizerSheet.show(context);
                  },
                ),
              ),

              const Divider(color: Colors.white12, height: 24),

              // Version and OTA Update Check
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.system_update_rounded, color: Colors.redAccent, size: 22),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'PureTube Sürümü',
                            style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                          Text(
                            'v${UpdateService.currentVersion} (Kablosuz Güncelleme)',
                            style: TextStyle(color: Colors.white54, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        backgroundColor: Colors.redAccent.withValues(alpha: 0.15),
                        foregroundColor: Colors.redAccent,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: _isCheckingUpdate
                          ? const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.redAccent),
                            )
                          : const Icon(Icons.refresh_rounded, size: 14),
                      label: Text(
                        _isCheckingUpdate ? 'Kontrol...' : 'Denetle',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                      onPressed: _isCheckingUpdate ? null : _manualCheckUpdate,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              const Row(
                children: [
                  Icon(Icons.headset_rounded, color: Colors.white70, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Arka planda ve ekran kilitliyken çalma otomatik olarak etkindir.',
                      style: TextStyle(color: Colors.white54, fontSize: 11.5),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Kapat', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}
