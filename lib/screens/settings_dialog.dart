import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/pip_service.dart';
import '../services/update_service.dart';

class SettingsDialog extends StatefulWidget {
  final int totalBlockedCount;
  final Function(bool adBlock, bool sponsorBlock) onChanged;
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
  bool _autoPipEnabled = true;
  bool _isCheckingUpdate = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _adBlockEnabled = prefs.getBool('adBlockEnabled') ?? true;
      _sponsorBlockEnabled = prefs.getBool('sponsorBlockEnabled') ?? true;
      _autoPipEnabled = prefs.getBool('autoPipEnabled') ?? true;
    });
  }

  Future<void> _saveSetting(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
    if (key == 'autoPipEnabled') {
      await PipService.setAutoPip(value);
    }
    widget.onChanged(_adBlockEnabled, _sponsorBlockEnabled);
  }

  Future<void> _manualCheckUpdate() async {
    setState(() => _isCheckingUpdate = true);
    final update = await UpdateService.checkForUpdate();
    if (!mounted) return;
    setState(() => _isCheckingUpdate = false);

    if (update != null) {
      Navigator.pop(context);
      UpdateService.showUpdateDialog(context, update);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🎉 Tebrikler! PureTube en güncel sürümde.'),
          duration: Duration(seconds: 2),
          backgroundColor: Color(0xFF2E7D32),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF222222),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Row(
        children: [
          Icon(Icons.tune_rounded, color: Colors.redAccent),
          SizedBox(width: 10),
          Text(
            'PureTube Ayarları',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Stats Banner
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.redAccent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.shield_outlined, color: Colors.greenAccent, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Kalıcı Engellenen Reklamlar',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                        Text(
                          '${widget.totalBlockedCount} adet reklam ve izleyici',
                          style: const TextStyle(
                            color: Colors.greenAccent,
                            fontSize: 14,
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
            const SizedBox(height: 14),

            // Switches
            SwitchListTile(
              activeColor: Colors.redAccent,
              contentPadding: EdgeInsets.zero,
              title: const Text('Reklam Engelleme', style: TextStyle(color: Colors.white, fontSize: 14)),
              subtitle: const Text('Video ve banner reklamlarını filtreler', style: TextStyle(color: Colors.white54, fontSize: 12)),
              value: _adBlockEnabled,
              onChanged: (val) {
                setState(() => _adBlockEnabled = val);
                _saveSetting('adBlockEnabled', val);
              },
            ),

            SwitchListTile(
              activeColor: Colors.redAccent,
              contentPadding: EdgeInsets.zero,
              title: const Text('SponsorBlock (Sponsor Atlama)', style: TextStyle(color: Colors.white, fontSize: 14)),
              subtitle: const Text('Video içi tanıtım ve sponsorlukları otomatik atlar', style: TextStyle(color: Colors.white54, fontSize: 12)),
              value: _sponsorBlockEnabled,
              onChanged: (val) {
                setState(() => _sponsorBlockEnabled = val);
                _saveSetting('sponsorBlockEnabled', val);
              },
            ),

            SwitchListTile(
              activeColor: Colors.redAccent,
              contentPadding: EdgeInsets.zero,
              title: const Text('Otomatik PiP (Küçük Pencere)', style: TextStyle(color: Colors.white, fontSize: 14)),
              subtitle: const Text('Ana ekrana dönüldüğünde küçük pencereye geçer', style: TextStyle(color: Colors.white54, fontSize: 12)),
              value: _autoPipEnabled,
              onChanged: (val) {
                setState(() => _autoPipEnabled = val);
                _saveSetting('autoPipEnabled', val);
              },
            ),

            const Divider(color: Colors.white24, height: 24),

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
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Kapat', style: TextStyle(color: Colors.redAccent)),
        ),
      ],
    );
  }
}
