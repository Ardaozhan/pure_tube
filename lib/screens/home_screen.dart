import 'dart:async';
import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/adblock_filter.dart';
import '../services/pip_service.dart';
import '../services/media_notification_service.dart';
import '../services/update_service.dart';
import 'settings_dialog.dart';

class HomeScreen extends StatefulWidget {
  final String ytJsCode;
  final String ytCssCode;

  const HomeScreen({
    super.key,
    required this.ytJsCode,
    required this.ytCssCode,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentTabIndex = 0; // 0: YouTube, 1: YouTube Music

  InAppWebViewController? _ytController;
  InAppWebViewController? _ytMusicController;

  String? _currentVideoId;
  int _blockedCount = 0;
  bool _isInPip = false;
  bool _isFullscreen = false;
  bool _adBlockEnabled = true;
  bool _sponsorBlockEnabled = true;
  bool _autoPipEnabled = true;
  double _loadProgress = 0.0;
  bool _isLoading = true;

  late String _ytJsCode;
  late String _ytCssCode;

  Timer? _saveCounterTimer;
  PullToRefreshController? _ytPullToRefreshController;

  void _setFullscreen(bool fullscreen, {String videoOrientation = 'landscape'}) {
    if (_isFullscreen == fullscreen) return;
    setState(() {
      _isFullscreen = fullscreen;
    });

    if (fullscreen) {
      _ytPullToRefreshController?.setEnabled(false);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      if (videoOrientation == 'portrait') {
        // Dik videolar dik büyüsün
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
        ]);
      } else {
        // Yatay videolar yatay büyüsün
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      }
    } else {
      // Tam ekrandan çıkınca kullanıcının sistem ayarlarına kesinlikle dokunma, serbest bırak
      _ytPullToRefreshController?.setEnabled(true);
      SystemChrome.setPreferredOrientations([]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([]);
    _ytPullToRefreshController = PullToRefreshController(
      settings: PullToRefreshSettings(
        color: Colors.redAccent,
        backgroundColor: const Color(0xFF1E1E1E),
      ),
      onRefresh: () async {
        _ytController?.reload();
      },
    );
    _ytJsCode = widget.ytJsCode;
    _ytCssCode = widget.ytCssCode;
    _loadSettings();
    _setupPipListener();
    _setupMediaNotificationListener();
    UpdateService.checkOnStartup(context);
  }

  void _setupMediaNotificationListener() {
    MediaNotificationService.initialize();
    MediaNotificationService.onAction = (source, action, positionMs) {
      debugPrint('[PureTube Dart] Media action received: source=$source, action=$action, pos=$positionMs');
      var controller = (source == 'music') ? _ytMusicController : _ytController;
      controller ??= (source == 'music') ? _ytController : _ytMusicController;
      if (controller == null) {
        debugPrint('[PureTube Dart] No controller available for action=$action');
        return;
      }

      switch (action) {
        case 'onPlay':
          controller.evaluateJavascript(
            source: 'if (window.pureTubeControl) window.pureTubeControl.play();',
          );
          break;
        case 'onPause':
          controller.evaluateJavascript(
            source: 'if (window.pureTubeControl) window.pureTubeControl.pause();',
          );
          break;
        case 'onNext':
          controller.evaluateJavascript(
            source: 'if (window.pureTubeControl) window.pureTubeControl.nextTrack();',
          );
          break;
        case 'onPrevious':
          controller.evaluateJavascript(
            source: 'if (window.pureTubeControl) window.pureTubeControl.prevTrack();',
          );
          break;
        case 'onSeek':
          if (positionMs != null) {
            final sec = positionMs / 1000.0;
            controller.evaluateJavascript(
              source: 'if (window.pureTubeControl) window.pureTubeControl.seekTo($sec);',
            );
          }
          break;
      }
    };
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final adBlock = prefs.getBool('adBlockEnabled') ?? true;
    final sponsor = prefs.getBool('sponsorBlockEnabled') ?? true;
    final autoPip = prefs.getBool('autoPipEnabled') ?? true;
    final savedBlockedCount = prefs.getInt('totalBlockedCount') ?? 0;

    _autoPipEnabled = autoPip;
    await PipService.setAutoPip(_currentTabIndex == 0 ? autoPip : false);

    if (mounted) {
      setState(() {
        _adBlockEnabled = adBlock;
        _sponsorBlockEnabled = sponsor;
        _blockedCount = savedBlockedCount;
      });
    }
  }

  void _incrementBlockedCount() {
    if (!_adBlockEnabled) return;
    _blockedCount++;
    if (mounted) {
      setState(() {});
    }
    _saveCounterTimer?.cancel();
    _saveCounterTimer = Timer(const Duration(milliseconds: 1500), () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('totalBlockedCount', _blockedCount);
    });
  }

  void _setupPipListener() {
    PipService.initialize();
    PipService.onPipModeChanged = (isInPip) {
      if (mounted) {
        setState(() {
          _isInPip = isInPip;
        });
        _ytController?.evaluateJavascript(
          source: 'if(window.pureTubeControl && window.pureTubeControl.setPipMode) { '
              'window.pureTubeControl.setPipMode($isInPip); '
              '}',
        );
      }
    };
  }

  Future<void> _openSettingsDialog() async {
    await showDialog(
      context: context,
      builder: (_) => SettingsDialog(
        totalBlockedCount: _blockedCount,
        onResetCounter: () async {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setInt('totalBlockedCount', 0);
          if (mounted) {
            setState(() {
              _blockedCount = 0;
            });
          }
        },
        onChanged: (adBlock, sponsorBlock) {
          setState(() {
            _adBlockEnabled = adBlock;
            _sponsorBlockEnabled = sponsorBlock;
          });
          _ytController?.evaluateJavascript(
            source: 'if(window.pureTubeControl) { '
                'window.pureTubeControl.setAdBlockEnabled($adBlock); '
                'window.pureTubeControl.setSponsorBlockEnabled($sponsorBlock); '
                '}',
          );
          _ytMusicController?.evaluateJavascript(
            source: 'if(window.pureTubeControl) { '
                'window.pureTubeControl.setAdBlockEnabled($adBlock); '
                'window.pureTubeControl.setSponsorBlockEnabled($sponsorBlock); '
                '}',
          );
        },
      ),
    );
    _loadSettings();
  }

  DateTime? _lastBackPressTime;

  Future<void> _handleBackPress() async {
    if (_isInPip) return;

    // 0. If currently in Fullscreen (landscape), exit fullscreen first
    if (_isFullscreen) {
      _setFullscreen(false);
      _ytController?.evaluateJavascript(
        source: 'if(document.exitFullscreen) { document.exitFullscreen(); } '
            'else if(document.webkitExitFullscreen) { document.webkitExitFullscreen(); }',
      );
      return;
    }

    // Active controller for current tab
    final controller = (_currentTabIndex == 1) ? _ytMusicController : _ytController;
    if (controller != null) {
      // 1. If on YouTube Music and the full-screen player drawer is covering the screen, minimize it first
      if (_currentTabIndex == 1) {
        try {
          final minimized = await controller.evaluateJavascript(
            source: '''
              (function() {
                const pp = document.querySelector('ytmusic-player-page, #player-page');
                if (pp) {
                  const rect = pp.getBoundingClientRect();
                  // Check if player page is physically expanded across the screen
                  if (rect.height > window.innerHeight * 0.5 && rect.top < 150) {
                    const btn = pp.querySelector('.down-chevron, [aria-label*="Daralt" i], [aria-label*="Dismiss" i], [aria-label*="Kapat" i]');
                    if (btn) {
                      try { btn.click(); } catch(e) {}
                      try {
                        const inner = btn.querySelector('button') || (btn.shadowRoot && btn.shadowRoot.querySelector('button'));
                        if (inner) inner.click();
                      } catch(e) {}
                      return true;
                    }
                  }
                }
                return false;
              })();
            ''',
          );
          if (minimized == true) {
            return;
          }
        } catch (_) {}
      }

      // 2. Standard web history navigation (works on both YouTube and YouTube Music)
      if (await controller.canGoBack()) {
        await controller.goBack();
        return;
      }
    }

    // Root exit confirmation
    _confirmOrExit();
  }

  void _confirmOrExit() {
    final now = DateTime.now();
    if (_lastBackPressTime == null || now.difference(_lastBackPressTime!) > const Duration(seconds: 2)) {
      _lastBackPressTime = now;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Çıkmak için tekrar geri kaydırın'),
            duration: Duration(seconds: 2),
            backgroundColor: Color(0xFF222222),
          ),
        );
      }
      return;
    }

    SystemNavigator.pop();
  }

  @override
  void dispose() {
    MediaNotificationService.clear();
    _saveCounterTimer?.cancel();
    SystemChrome.setPreferredOrientations([]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isYouTube = _currentTabIndex == 0;
    final isMusic = _currentTabIndex == 1;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _handleBackPress();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: (_isFullscreen || _isInPip)
            ? null
            : PreferredSize(
                preferredSize: Size.fromHeight(_isLoading ? 52 : 50),
                child: AppBar(
                backgroundColor: const Color(0xFF0F0F0F),
                elevation: 0,
                scrolledUnderElevation: 0,
                automaticallyImplyLeading: false,
                titleSpacing: 12,
                title: Container(
                  height: 36,
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white12, width: 0.8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // YouTube Pill
                      GestureDetector(
                        onTap: () {
                          if (_currentTabIndex != 0) {
                            _ytMusicController?.evaluateJavascript(
                              source: 'if (window.pureTubeControl) window.pureTubeControl.pause();',
                            );
                            setState(() {
                              _currentTabIndex = 0;
                            });
                            PipService.setAutoPip(_autoPipEnabled);
                          }
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeInOut,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                          decoration: BoxDecoration(
                            color: isYouTube ? Colors.redAccent : Colors.transparent,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: isYouTube
                                ? [
                                    BoxShadow(
                                      color: Colors.redAccent.withValues(alpha: 0.4),
                                      blurRadius: 8,
                                      offset: const Offset(0, 1),
                                    ),
                                  ]
                                : null,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.play_arrow_rounded,
                                size: 18,
                                color: isYouTube ? Colors.white : Colors.white60,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'YouTube',
                                style: TextStyle(
                                  color: isYouTube ? Colors.white : Colors.white60,
                                  fontSize: 12.5,
                                  fontWeight: isYouTube ? FontWeight.bold : FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Music Pill
                      GestureDetector(
                        onTap: () {
                          if (_currentTabIndex != 1) {
                            _ytController?.evaluateJavascript(
                              source: 'if (window.pureTubeControl) window.pureTubeControl.pause();',
                            );
                            setState(() {
                              _currentTabIndex = 1;
                            });
                            PipService.setAutoPip(false);
                          }
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeInOut,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                          decoration: BoxDecoration(
                            color: isMusic ? const Color(0xFFFF2D55) : Colors.transparent,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: isMusic
                                ? [
                                    BoxShadow(
                                      color: const Color(0xFFFF2D55).withValues(alpha: 0.4),
                                      blurRadius: 8,
                                      offset: const Offset(0, 1),
                                    ),
                                  ]
                                : null,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.music_note_rounded,
                                size: 16,
                                color: isMusic ? Colors.white : Colors.white60,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Music',
                                style: TextStyle(
                                  color: isMusic ? Colors.white : Colors.white60,
                                  fontSize: 12.5,
                                  fontWeight: isMusic ? FontWeight.bold : FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  // Ad Shield Counter
                  GestureDetector(
                    onTap: _openSettingsDialog,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 10),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.35)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.shield_rounded, color: Colors.greenAccent, size: 14),
                          const SizedBox(width: 4),
                          Text(
                            '$_blockedCount',
                            style: const TextStyle(
                              color: Colors.greenAccent,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  // PiP Button (YouTube only)
                  if (isYouTube)
                    IconButton(
                      tooltip: 'Küçük Pencere (PiP)',
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                      icon: const Icon(Icons.picture_in_picture_alt_rounded, color: Colors.white, size: 20),
                      onPressed: () {
                        // Immediately invoke native PiP synchronously on UI thread
                        PipService.enterPip();
                        _ytController?.evaluateJavascript(
                          source: 'if(window.pureTubeControl && window.pureTubeControl.setPipMode) { '
                              'window.pureTubeControl.setPipMode(true); '
                              '}',
                        );
                      },
                    ),
                  // Settings Button
                  IconButton(
                    tooltip: 'Ayarlar',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                    icon: const Icon(Icons.settings_rounded, color: Colors.white70, size: 20),
                    onPressed: _openSettingsDialog,
                  ),
                  const SizedBox(width: 8),
                ],
                bottom: _isLoading
                    ? PreferredSize(
                        preferredSize: const Size.fromHeight(2),
                        child: LinearProgressIndicator(
                          value: _loadProgress > 0 ? _loadProgress : null,
                          backgroundColor: Colors.transparent,
                          valueColor: const AlwaysStoppedAnimation<Color>(Colors.redAccent),
                          minHeight: 2,
                        ),
                      )
                    : null,
              ),
            ),
      body: SafeArea(
        top: false,
        bottom: !_isFullscreen && !_isInPip,
        child: IndexedStack(
          index: _currentTabIndex,
          children: [
            _buildWebViewTab(
              initialUrl: 'https://m.youtube.com',
              onCreated: (controller) => _ytController = controller,
              isYouTube: true,
            ),
            _buildWebViewTab(
              initialUrl: 'https://music.youtube.com',
              onCreated: (controller) => _ytMusicController = controller,
              isYouTube: false,
            ),
          ],
        ),
      ),
    ),
  );
}

  InAppWebViewSettings _createWebViewSettings() {
    return InAppWebViewSettings(
      javaScriptEnabled: true,
      mediaPlaybackRequiresUserGesture: false,
      allowsInlineMediaPlayback: true,
      allowBackgroundAudioPlaying: true,
      useShouldInterceptRequest: true,
      supportZoom: false,
      userAgent:
          'Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36',
      supportMultipleWindows: false,
      verticalScrollBarEnabled: false,
      horizontalScrollBarEnabled: false,
      transparentBackground: false,
      hardwareAcceleration: true,
      domStorageEnabled: true,
      databaseEnabled: true,
      cacheEnabled: true,
      cacheMode: CacheMode.LOAD_DEFAULT,
      useHybridComposition: false, // TLHC - Texture Layer Hybrid Composition (instant rendering)
      offscreenPreRaster: true,
      overScrollMode: OverScrollMode.IF_CONTENT_SCROLLS,
      scrollBarStyle: ScrollBarStyle.SCROLLBARS_INSIDE_OVERLAY,
      preferredContentMode: UserPreferredContentMode.MOBILE,
      mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
    );
  }

  Widget _buildWebViewTab({
    required String initialUrl,
    required void Function(InAppWebViewController) onCreated,
    bool isYouTube = false,
  }) {
    return InAppWebView(
      pullToRefreshController: isYouTube ? _ytPullToRefreshController : null,
      initialUrlRequest: URLRequest(url: WebUri(initialUrl)),
      initialUserScripts: UnmodifiableListView([
        if (_ytJsCode.isNotEmpty)
          UserScript(
            source: _ytJsCode,
            injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
          ),
      ]),
      initialSettings: _createWebViewSettings(),
      onWebViewCreated: (controller) {
        onCreated(controller);

        controller.addJavaScriptHandler(
          handlerName: 'onAdBlocked',
          callback: (args) => _incrementBlockedCount(),
        );

        controller.addJavaScriptHandler(
          handlerName: 'onVideoChanged',
          callback: (args) {
            if (args.isNotEmpty && args[0] is Map) {
              final map = args[0] as Map;
              final videoId = map['videoId'] as String?;
              if (mounted && videoId != null) {
                setState(() => _currentVideoId = videoId);
              }
            }
          },
        );

        controller.addJavaScriptHandler(
          handlerName: 'onMediaMetadataChanged',
          callback: (args) {
            if (args.isNotEmpty && args[0] is Map) {
              final map = args[0] as Map;
              final source = isYouTube ? 'youtube' : 'music';
              final title = map['title'] as String? ?? '';
              final artist = map['artist'] as String? ?? '';
              final artwork = map['artwork'] as String?;
              final isPlaying = map['isPlaying'] as bool? ?? false;
              final positionMs = (map['positionMs'] as num?)?.toInt() ?? 0;
              final durationMs = (map['durationMs'] as num?)?.toInt() ?? 0;

              MediaNotificationService.updateMetadata(
                source: source,
                title: title,
                artist: artist,
                artwork: artwork,
                isPlaying: isPlaying,
                positionMs: positionMs,
                durationMs: durationMs,
              );
            }
          },
        );

        if (isYouTube) {
          controller.addJavaScriptHandler(
            handlerName: 'onFullscreenToggle',
            callback: (args) {
              if (args.isNotEmpty && args[0] is Map) {
                final map = args[0] as Map;
                final isFs = map['isFullscreen'] as bool? ?? false;
                final orientation = map['orientation'] as String? ?? 'landscape';
                _setFullscreen(isFs, videoOrientation: orientation);
              }
            },
          );
        }
      },
      onProgressChanged: (controller, progress) {
        if (isYouTube && progress >= 90) {
          _ytPullToRefreshController?.endRefreshing();
        }
        if (mounted) {
          setState(() {
            _loadProgress = progress / 100.0;
            if (progress >= 90) {
              _isLoading = false;
            }
          });
        }
      },
      onEnterFullscreen: isYouTube
          ? (c) async {
              String orientation = 'landscape';
              try {
                final res = await c.evaluateJavascript(source: '''
                  (function() {
                    if (window.location.href.includes('/shorts/')) return 'portrait';
                    const p = document.querySelector('.html5-video-player');
                    if (p && (p.classList.contains('ytp-vertical-video') || p.classList.contains('ytp-fit-vertical-video'))) return 'portrait';
                    const v = document.querySelector('video');
                    if (v && v.videoWidth > 0 && v.videoHeight > 0) {
                      return (v.videoHeight > v.videoWidth) ? 'portrait' : 'landscape';
                    }
                    return 'landscape';
                  })();
                ''');
                if (res != null) {
                  orientation = res.toString();
                }
              } catch (_) {}
              _setFullscreen(true, videoOrientation: orientation);
            }
          : null,
      onExitFullscreen: isYouTube ? (c) => _setFullscreen(false) : null,
      onLoadStop: (controller, url) async {
        if (isYouTube) {
          _ytPullToRefreshController?.endRefreshing();
        }
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
        if (_ytCssCode.isNotEmpty) {
          await controller.injectCSSCode(source: _ytCssCode);
        }
        await controller.evaluateJavascript(
          source: 'if(window.pureTubeControl) { '
              'window.pureTubeControl.setAdBlockEnabled($_adBlockEnabled); '
              'window.pureTubeControl.setSponsorBlockEnabled($_sponsorBlockEnabled); '
              '}',
        );

        final urlStr = url?.toString() ?? '';
        final uri = Uri.tryParse(urlStr);
        final videoId = uri?.queryParameters['v'] ??
            (urlStr.contains('/shorts/')
                ? urlStr.split('/shorts/').last.split('?').first
                : (urlStr.contains('/watch?v=')
                    ? urlStr.split('/watch?v=').last.split('&').first
                    : null));
        if (mounted && videoId != null && videoId != _currentVideoId) {
          setState(() => _currentVideoId = videoId);
        }
      },
      shouldInterceptRequest: (controller, request) async {
        if (!_adBlockEnabled) return null;

        final uri = request.url;
        final host = uri.host;

        // Fast-path: Immediately bypass YouTube CDN & media streams without filtering overhead
        if (host.endsWith('.googlevideo.com') ||
            host.endsWith('.ytimg.com') ||
            host.endsWith('.ggpht.com') ||
            host.endsWith('.gstatic.com') ||
            host == 'fonts.googleapis.com' ||
            host == 'fonts.gstatic.com') {
          return null;
        }

        // On youtube / ytmusic domains, only intercept known ad-tracking paths
        if (host == 'm.youtube.com' || host == 'music.youtube.com') {
          final path = uri.path;
          if (path.startsWith('/pagead') ||
              path.startsWith('/api/stats/ads') ||
              path.startsWith('/ptracking') ||
              path.startsWith('/ad_break')) {
            _incrementBlockedCount();
            return WebResourceResponse(
              contentType: 'text/plain',
              data: Uint8List(0),
            );
          }
          return null;
        }

        if (AdBlockFilter.shouldBlock(uri)) {
          _incrementBlockedCount();
          return WebResourceResponse(
            contentType: 'text/plain',
            data: Uint8List(0),
          );
        }
        return null;
      },
    );
  }
}
