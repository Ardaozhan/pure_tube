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
import '../services/ryd_service.dart';
import '../services/sponsorblock_service.dart';
import '../services/lyrics_service.dart';
import '../database/library_repository.dart';
import '../widgets/equalizer_sheet.dart';
import '../widgets/gesture_overlay.dart';
import '../widgets/download_modal.dart';
import '../widgets/lyrics_view.dart';
import 'settings_dialog.dart';
import 'library_screen.dart';
import 'downloads_screen.dart';

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
  // Navigation tabs: 0: YouTube, 1: Müzik, 2: Kütüphane, 3: İndirilenler
  int _currentTabIndex = 0;
  final GlobalKey<DownloadsScreenState> _downloadsKey = GlobalKey<DownloadsScreenState>();

  InAppWebViewController? _ytController;
  InAppWebViewController? _ytMusicController;

  String? _currentVideoId;
  String _currentTitle = '';
  String _currentArtist = '';
  String? _currentArtwork;
  bool _isPlaying = false;
  int _currentPositionMs = 0;
  int _currentDurationMs = 0;

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
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
        ]);
      } else {
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      }
    } else {
      _ytPullToRefreshController?.setEnabled(true);
      SystemChrome.setPreferredOrientations([]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([]);
    try {
      _ytPullToRefreshController = PullToRefreshController(
        settings: PullToRefreshSettings(
          color: Colors.redAccent,
          backgroundColor: const Color(0xFF1E1E1E),
        ),
        onRefresh: () async {
          _ytController?.reload();
        },
      );
    } catch (_) {
      _ytPullToRefreshController = null;
    }
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

  Future<String?> _resolveCurrentVideoId() async {
    if (_currentVideoId != null && _currentVideoId!.isNotEmpty) {
      return _currentVideoId;
    }
    final controller = (_currentTabIndex == 1) ? _ytMusicController : _ytController;
    if (controller != null) {
      final currentUrl = await controller.getUrl();
      if (currentUrl != null) {
        final urlStr = currentUrl.toString();
        final uri = Uri.tryParse(urlStr);
        final v = uri?.queryParameters['v'] ??
            (urlStr.contains('/shorts/')
                ? urlStr.split('/shorts/').last.split('?').first
                : (urlStr.contains('/watch?v=')
                    ? urlStr.split('/watch?v=').last.split('&').first
                    : null));
        if (v != null && v.isNotEmpty) {
          return v;
        }
      }
      try {
        final jsVid = await controller.evaluateJavascript(source: '''
          (function() {
            const urlParams = new URLSearchParams(window.location.search);
            if (urlParams.get('v')) return urlParams.get('v');
            if (window.location.pathname.includes('/shorts/')) {
              return window.location.pathname.split('/shorts/')[1].split('/')[0];
            }
            if (window.location.pathname.includes('/watch')) {
              return urlParams.get('v');
            }
            return null;
          })();
        ''');
        if (jsVid != null && jsVid.toString().isNotEmpty && jsVid.toString() != 'null') {
          return jsVid.toString();
        }
      } catch (_) {}
    }
    return null;
  }

  Future<void> _openDownloadModal() async {
    final videoId = await _resolveCurrentVideoId();
    if (!mounted) return;
    if (videoId != null && videoId.isNotEmpty) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => DownloadModal(videoId: videoId),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('İndirmek için lütfen önce bir video veya müzik açın.'),
          backgroundColor: Color(0xFF222222),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _openLyricsSheet() async {
    final controller = (_currentTabIndex == 1) ? _ytMusicController : _ytController;
    String songTitle = _currentTitle;
    String artistName = _currentArtist;

    if (songTitle.isEmpty && controller != null) {
      final pageTitle = await controller.getTitle();
      if (pageTitle != null && pageTitle.isNotEmpty) {
        songTitle = pageTitle
            .replaceAll(' - YouTube', '')
            .replaceAll(' - YouTube Music', '')
            .trim();
      }
    }

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _LyricsModalSheet(
        title: songTitle,
        artist: artistName,
        initialPositionMs: _currentPositionMs,
        durationSeconds: _currentDurationMs > 0 ? (_currentDurationMs ~/ 1000) : null,
        controller: controller,
      ),
    );
  }

  Future<void> _recordWatchHistory({
    required String videoId,
    String? title,
    String? author,
    String? thumbnailUrl,
    int? positionMs,
    int? durationMs,
  }) async {
    if (videoId.isEmpty) return;
    String cleanTitle = (title ?? _currentTitle)
        .replaceAll(' - YouTube', '')
        .replaceAll(' - YouTube Music', '')
        .trim();
    if (cleanTitle.isEmpty) {
      cleanTitle = 'YouTube Video ($videoId)';
    }

    final thumb = thumbnailUrl ?? _currentArtwork ?? 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg';

    try {
      await LibraryRepository.instance.recordHistory(
        videoId: videoId,
        title: cleanTitle,
        author: author ?? (_currentArtist.isNotEmpty ? _currentArtist : null),
        thumbnailUrl: thumb,
        positionMs: positionMs,
        durationMs: durationMs,
      );
    } catch (e) {
      debugPrint('[PureTube] Error recording history: $e');
    }
  }

  void _handleLibraryVideoTap(String videoId) {
    setState(() {
      _currentTabIndex = 0;
    });
    PipService.setAutoPip(_autoPipEnabled);
    _ytController?.loadUrl(
      urlRequest: URLRequest(url: WebUri('https://m.youtube.com/watch?v=$videoId')),
    );
  }

  void _handleLibraryChannelTap(String channelId) {
    setState(() {
      _currentTabIndex = 0;
    });
    PipService.setAutoPip(_autoPipEnabled);
    String targetUrl;
    if (channelId.startsWith('http://') || channelId.startsWith('https://')) {
      targetUrl = channelId;
    } else if (channelId.startsWith('/')) {
      targetUrl = 'https://m.youtube.com$channelId';
    } else if (channelId.startsWith('@')) {
      targetUrl = 'https://m.youtube.com/$channelId';
    } else {
      targetUrl = 'https://m.youtube.com/channel/$channelId';
    }
    _ytController?.loadUrl(
      urlRequest: URLRequest(url: WebUri(targetUrl)),
    );
  }

  DateTime? _lastBackPressTime;

  Future<void> _handleBackPress() async {
    if (_isInPip) return;

    // 0. If currently in Fullscreen, exit fullscreen first
    if (_isFullscreen) {
      _setFullscreen(false);
      _ytController?.evaluateJavascript(
        source: 'if(document.exitFullscreen) { document.exitFullscreen(); } '
            'else if(document.webkitExitFullscreen) { document.webkitExitFullscreen(); }',
      );
      return;
    }

    // 1. If on Library (2) or Downloads (3), go back to YouTube tab (0)
    if (_currentTabIndex > 1) {
      setState(() {
        _currentTabIndex = 0;
      });
      PipService.setAutoPip(_autoPipEnabled);
      return;
    }

    // Active controller for current tab
    final controller = (_currentTabIndex == 1) ? _ytMusicController : _ytController;
    if (controller != null) {
      // 2. If on YouTube Music and player drawer is expanded, collapse it first
      if (_currentTabIndex == 1) {
        try {
          final minimized = await controller.evaluateJavascript(
            source: '''
              (function() {
                const pp = document.querySelector('ytmusic-player-page, #player-page');
                if (pp) {
                  const rect = pp.getBoundingClientRect();
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

      // 3. Standard web history navigation
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
    final showTopBar = !_isFullscreen && !_isInPip && (isYouTube || isMusic);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _handleBackPress();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black, // Pure OLED pitch-black (#000000)
        appBar: showTopBar
            ? PreferredSize(
                preferredSize: Size.fromHeight(_isLoading ? 52 : 50),
                child: AppBar(
                  backgroundColor: Colors.black, // OLED pitch black (#000000)
                  elevation: 0,
                  scrolledUnderElevation: 0,
                  automaticallyImplyLeading: false,
                  titleSpacing: 16,
                  title: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isMusic ? Icons.music_note_rounded : Icons.play_arrow_rounded,
                        color: isMusic ? const Color(0xFFFF2D55) : Colors.redAccent,
                        size: 26,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isMusic ? 'PureMusic' : 'PureTube',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 19,
                          fontWeight: FontWeight.bold,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ],
                  ),
                  actions: [
                    // Ad Shield Counter
                    GestureDetector(
                      onTap: _openSettingsDialog,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 11),
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
                    const SizedBox(width: 2),

                    // "İndir" button
                    IconButton(
                      tooltip: 'İndir',
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                      icon: const Icon(Icons.download_rounded, color: Colors.white, size: 21),
                      onPressed: _openDownloadModal,
                    ),

                    // "Ekolayzer" button
                    IconButton(
                      tooltip: 'Ekolayzer',
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                      icon: const Icon(Icons.tune_rounded, color: Color(0xFFFFD700), size: 20),
                      onPressed: () => EqualizerSheet.show(context),
                    ),

                    // "Sözler" button (on Music tab or when music is playing)
                    if (isMusic || _isPlaying)
                      IconButton(
                        tooltip: 'Şarkı Sözleri',
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                        icon: const Icon(Icons.lyrics_rounded, color: Color(0xFF64B5F6), size: 20),
                        onPressed: _openLyricsSheet,
                      ),

                    // PiP button (YouTube only)
                    if (isYouTube)
                      IconButton(
                        tooltip: 'Küçük Pencere (PiP)',
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                        icon: const Icon(Icons.picture_in_picture_alt_rounded, color: Colors.white, size: 20),
                        onPressed: () {
                          PipService.enterPip();
                          _ytController?.evaluateJavascript(
                            source: 'if(window.pureTubeControl && window.pureTubeControl.setPipMode) { '
                                'window.pureTubeControl.setPipMode(true); '
                                '}',
                          );
                        },
                      ),

                    // Settings button
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
                            valueColor: AlwaysStoppedAnimation<Color>(
                              isMusic ? const Color(0xFFFF2D55) : Colors.redAccent,
                            ),
                            minHeight: 2,
                          ),
                        )
                      : null,
                ),
              )
            : null,
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
              LibraryScreen(
                onVideoTap: _handleLibraryVideoTap,
                onChannelTap: _handleLibraryChannelTap,
              ),
              DownloadsScreen(
                key: _downloadsKey,
              ),
            ],
          ),
        ),
        bottomNavigationBar: (_isFullscreen || _isInPip)
            ? null
            : Theme(
                data: Theme.of(context).copyWith(
                  canvasColor: Colors.black,
                  splashColor: Colors.transparent,
                  highlightColor: Colors.transparent,
                ),
                child: Container(
                  decoration: const BoxDecoration(
                    color: Colors.black,
                    border: Border(
                      top: BorderSide(color: Color(0x1FFFFFFF), width: 0.8),
                    ),
                  ),
                  child: BottomNavigationBar(
                    currentIndex: _currentTabIndex,
                    onTap: (index) {
                      if (_currentTabIndex == index) return;
                      // Refresh downloads list when opening tab 3
                      if (index == 3) {
                        _downloadsKey.currentState?.refreshList();
                      }
                      setState(() {
                        _currentTabIndex = index;
                      });
                      if (index == 0) {
                        PipService.setAutoPip(_autoPipEnabled);
                      } else {
                        PipService.setAutoPip(false);
                      }
                    },
                    backgroundColor: Colors.black,
                    elevation: 0,
                    type: BottomNavigationBarType.fixed,
                    selectedItemColor: _currentTabIndex == 1 ? const Color(0xFFFF2D55) : Colors.redAccent,
                    unselectedItemColor: Colors.white54,
                    selectedFontSize: 11,
                    unselectedFontSize: 11,
                    items: const [
                      BottomNavigationBarItem(
                        icon: Icon(Icons.play_circle_outline_rounded),
                        activeIcon: Icon(Icons.play_circle_filled_rounded),
                        label: 'YouTube',
                      ),
                      BottomNavigationBarItem(
                        icon: Icon(Icons.music_note_outlined),
                        activeIcon: Icon(Icons.music_note_rounded),
                        label: 'Müzik',
                      ),
                      BottomNavigationBarItem(
                        icon: Icon(Icons.video_library_outlined),
                        activeIcon: Icon(Icons.video_library_rounded),
                        label: 'Kütüphane',
                      ),
                      BottomNavigationBarItem(
                        icon: Icon(Icons.download_rounded),
                        activeIcon: Icon(Icons.download_done_rounded),
                        label: 'İndirilenler',
                      ),
                    ],
                  ),
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
    final webView = InAppWebView(
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
              final title = map['title'] as String?;
              final author = map['author'] as String?;
              if (mounted && videoId != null) {
                setState(() => _currentVideoId = videoId);
                // Prefetch RYD votes and SponsorBlock segments asynchronously
                RydService.instance.fetchVotes(videoId);
                SponsorBlockService.instance.fetchSegments(videoId);
                _recordWatchHistory(
                  videoId: videoId,
                  title: title,
                  author: author,
                );
              }
            }
          },
        );

        controller.addJavaScriptHandler(
          handlerName: 'fetchRydVotes',
          callback: (args) async {
            if (args.isNotEmpty && args[0] is Map) {
              final map = args[0] as Map;
              final videoId = map['videoId'] as String?;
              if (videoId != null && videoId.isNotEmpty) {
                final votes = await RydService.instance.fetchVotes(videoId);
                return votes?.toMap();
              }
            }
            return null;
          },
        );

        controller.addJavaScriptHandler(
          handlerName: 'fetchSponsorSegments',
          callback: (args) async {
            if (args.isNotEmpty && args[0] is Map) {
              final map = args[0] as Map;
              final videoId = map['videoId'] as String?;
              if (videoId != null && videoId.isNotEmpty) {
                final segments = await SponsorBlockService.instance.fetchSegments(videoId);
                return segments.map((s) => s.toMap()).toList();
              }
            }
            return [];
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

              if (mounted) {
                setState(() {
                  if (title.isNotEmpty) _currentTitle = title;
                  if (artist.isNotEmpty) _currentArtist = artist;
                  if (artwork != null && artwork.isNotEmpty) _currentArtwork = artwork;
                  _isPlaying = isPlaying;
                  _currentPositionMs = positionMs;
                  _currentDurationMs = durationMs;
                });
              }

              MediaNotificationService.updateMetadata(
                source: source,
                title: title,
                artist: artist,
                artwork: artwork,
                isPlaying: isPlaying,
                positionMs: positionMs,
                durationMs: durationMs,
              );

              if (_currentVideoId != null && _currentVideoId!.isNotEmpty) {
                _recordWatchHistory(
                  videoId: _currentVideoId!,
                  title: title.isNotEmpty ? title : null,
                  author: artist.isNotEmpty ? artist : null,
                  thumbnailUrl: artwork,
                  positionMs: positionMs,
                  durationMs: durationMs,
                );
              }
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
      onTitleChanged: (controller, title) {
        if (title != null && title.isNotEmpty && !title.contains('YouTube') && _currentVideoId != null) {
          _currentTitle = title;
          _recordWatchHistory(
            videoId: _currentVideoId!,
            title: title,
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
        if (videoId != null && videoId.isNotEmpty) {
          if (mounted && videoId != _currentVideoId) {
            setState(() => _currentVideoId = videoId);
          }
          final pageTitle = await controller.getTitle();
          _recordWatchHistory(
            videoId: videoId,
            title: pageTitle,
          );
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

    return GestureOverlay(
      enabled: _isFullscreen,
      onSeek: (seconds) {
        final ctrl = isYouTube ? _ytController : _ytMusicController;
        ctrl?.evaluateJavascript(
          source: 'if (window.pureTubeControl) window.pureTubeControl.seekBy($seconds);',
        );
      },
      child: webView,
    );
  }
}

/// Spotify & Apple Music style modal bottom sheet with synchronized lyrics & real-time karaoke tracking.
class _LyricsModalSheet extends StatefulWidget {
  final String title;
  final String artist;
  final int initialPositionMs;
  final int? durationSeconds;
  final InAppWebViewController? controller;

  const _LyricsModalSheet({
    required this.title,
    required this.artist,
    required this.initialPositionMs,
    this.durationSeconds,
    this.controller,
  });

  @override
  State<_LyricsModalSheet> createState() => _LyricsModalSheetState();
}

class _LyricsModalSheetState extends State<_LyricsModalSheet> {
  List<LyricLine> _lyrics = [];
  bool _isLoading = true;
  late int _positionMs;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _positionMs = widget.initialPositionMs;
    _fetchLyrics();
    _startPositionPolling();
  }

  Future<void> _fetchLyrics() async {
    final result = await LyricsService().getLyrics(
      trackName: widget.title,
      artistName: widget.artist.isNotEmpty ? widget.artist : null,
      durationSeconds: widget.durationSeconds,
    );
    if (mounted) {
      setState(() {
        _lyrics = result ?? [];
        _isLoading = false;
      });
    }
  }

  void _startPositionPolling() {
    _pollTimer = Timer.periodic(const Duration(milliseconds: 400), (_) async {
      if (widget.controller == null) return;
      try {
        final res = await widget.controller!.evaluateJavascript(
          source: '(function() { const v = document.querySelector("video"); return v ? Math.round(v.currentTime * 1000) : 0; })();',
        );
        if (res != null && mounted) {
          final pos = (res as num).toInt();
          if (pos > 0 && pos != _positionMs) {
            setState(() {
              _positionMs = pos;
            });
          }
        }
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.84,
      decoration: const BoxDecoration(
        color: Color(0xFF0C0B0A), // OLED pitch black
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(top: BorderSide(color: Color(0x33FFD700), width: 1.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black,
            blurRadius: 24,
            spreadRadius: 4,
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: LyricsView(
          lyrics: _lyrics,
          currentPositionMs: _positionMs,
          isLoading: _isLoading,
          songTitle: widget.title.isNotEmpty ? widget.title : 'Şarkı Sözleri',
          artistName: widget.artist,
          onClose: () => Navigator.pop(context),
          onSeekTo: (seekPosMs) {
            final sec = seekPosMs / 1000.0;
            widget.controller?.evaluateJavascript(
              source: 'if (window.pureTubeControl) window.pureTubeControl.seekTo($sec);',
            );
          },
        ),
      ),
    );
  }
}
