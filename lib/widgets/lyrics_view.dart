import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/lyrics_service.dart';

/// Spotify & Apple Music style animated scrolling karaoke view for synchronized lyrics.
class LyricsView extends StatefulWidget {
  final List<LyricLine> lyrics;
  final int currentPositionMs;
  final ValueChanged<int>? onSeekTo;
  final bool isLoading;
  final String? songTitle;
  final String? artistName;
  final VoidCallback? onClose;

  const LyricsView({
    super.key,
    required this.lyrics,
    required this.currentPositionMs,
    this.onSeekTo,
    this.isLoading = false,
    this.songTitle,
    this.artistName,
    this.onClose,
  });

  @override
  State<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<LyricsView> {
  final ScrollController _scrollController = ScrollController();
  late List<GlobalKey> _lineKeys;

  int _lastActiveIndex = -1;
  bool _isUserScrolling = false;
  Timer? _userScrollDebounceTimer;

  @override
  void initState() {
    super.initState();
    _rebuildKeys();
  }

  @override
  void didUpdateWidget(covariant LyricsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.lyrics.length != oldWidget.lyrics.length) {
      _rebuildKeys();
      _lastActiveIndex = -1;
    }

    final activeIndex = _calculateActiveIndex();
    if (activeIndex != _lastActiveIndex) {
      _lastActiveIndex = activeIndex;
      if (!_isUserScrolling && activeIndex >= 0) {
        _scrollToIndex(activeIndex);
      }
    }
  }

  void _rebuildKeys() {
    _lineKeys = List.generate(widget.lyrics.length, (_) => GlobalKey());
  }

  @override
  void dispose() {
    _userScrollDebounceTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  int _calculateActiveIndex() {
    if (widget.lyrics.isEmpty) return -1;
    final pos = widget.currentPositionMs;
    if (pos < widget.lyrics.first.timestampMs) return 0;

    for (int i = 0; i < widget.lyrics.length; i++) {
      final isLast = (i == widget.lyrics.length - 1);
      final currentLineTime = widget.lyrics[i].timestampMs;
      final nextLineTime = isLast ? double.infinity : widget.lyrics[i + 1].timestampMs;

      if (pos >= currentLineTime && pos < nextLineTime) {
        return i;
      }
    }
    return widget.lyrics.length - 1;
  }

  void _scrollToIndex(int index) {
    if (index < 0 || index >= _lineKeys.length) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final context = _lineKeys[index].currentContext;
      if (context != null) {
        Scrollable.ensureVisible(
          context,
          alignment: 0.42,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOutCubic,
        );
      } else if (_scrollController.hasClients) {
        // Fallback approximation
        final targetOffset = (index * 72.0) - 150.0;
        _scrollController.animateTo(
          targetOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOutCubic,
        );
      }
    });
  }

  void _onUserScrolled() {
    if (!_isUserScrolling) {
      setState(() {
        _isUserScrolling = true;
      });
    }
    _userScrollDebounceTimer?.cancel();
    _userScrollDebounceTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) {
        setState(() {
          _isUserScrolling = false;
        });
        final activeIndex = _calculateActiveIndex();
        if (activeIndex >= 0) {
          _scrollToIndex(activeIndex);
        }
      }
    });
  }

  void _resumeAutoScroll() {
    _userScrollDebounceTimer?.cancel();
    setState(() {
      _isUserScrolling = false;
    });
    final activeIndex = _calculateActiveIndex();
    if (activeIndex >= 0) {
      _scrollToIndex(activeIndex);
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeIndex = _calculateActiveIndex();

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF000000), // OLED Pitch Black
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF16130B), // Subtle warm ambient gold glow at top
            Color(0xFF080706),
            Color(0xFF000000),
            Color(0xFF000000),
          ],
          stops: [0.0, 0.25, 0.65, 1.0],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: Stack(
                children: [
                  if (widget.isLoading)
                    _buildLoadingState()
                  else if (widget.lyrics.isEmpty)
                    _buildEmptyState()
                  else
                    _buildLyricsList(activeIndex),

                  // Floating "Sync with playback" button when user scrolls away
                  if (_isUserScrolling && widget.lyrics.isNotEmpty)
                    Positioned(
                      bottom: 24,
                      right: 20,
                      child: _buildSyncPillButton(),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Color(0x0FFFFFFF),
            width: 1,
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle pill
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: const Color(0x40FFFFFF),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Row(
            children: [
              // Live karaoke badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0x26FFD700),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color(0x66FFD700),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Color(0xFFFFD700),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Color(0xFFFFD700),
                            blurRadius: 6,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'SÖZLER',
                      style: TextStyle(
                        color: Color(0xFFFFD700),
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Track & Artist title
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.songTitle ?? 'Şarkı Sözleri',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (widget.artistName != null && widget.artistName!.isNotEmpty)
                      Text(
                        widget.artistName!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0x80FFFFFF),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                  ],
                ),
              ),
              if (widget.onClose != null)
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white70),
                  onPressed: widget.onClose,
                  tooltip: 'Kapat',
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLyricsList(int activeIndex) {
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is UserScrollNotification) {
          _onUserScrolled();
        }
        return false;
      },
      child: ShaderMask(
        shaderCallback: (rect) {
          return const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.transparent,
              Colors.black,
              Colors.black,
              Colors.transparent,
            ],
            stops: [0.0, 0.08, 0.88, 1.0],
          ).createShader(rect);
        },
        blendMode: BlendMode.dstIn,
        child: ListView.builder(
          controller: _scrollController,
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 80),
          itemCount: widget.lyrics.length,
          itemBuilder: (context, index) {
            final line = widget.lyrics[index];
            final isActive = (index == activeIndex);
            final isPast = (index < activeIndex);

            return Padding(
              key: _lineKeys[index],
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  HapticFeedback.selectionClick();
                  widget.onSeekTo?.call(line.timestampMs);
                  _resumeAutoScroll();
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.centerLeft,
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 350),
                    curve: Curves.easeOutCubic,
                    style: _getLyricTextStyle(isActive: isActive, isPast: isPast),
                    child: Text(
                      line.text.isEmpty ? '♪' : line.text,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  TextStyle _getLyricTextStyle({required bool isActive, required bool isPast}) {
    if (isActive) {
      return const TextStyle(
        color: Color(0xFFFFF9E6), // Glowing Neon Gold / White
        fontSize: 26,
        fontWeight: FontWeight.w800,
        height: 1.32,
        letterSpacing: -0.4,
        shadows: [
          Shadow(
            color: Color(0xCCFFD700),
            blurRadius: 18,
          ),
          Shadow(
            color: Color(0x88FFA000),
            blurRadius: 36,
          ),
          Shadow(
            color: Color(0xDDFFFFFF),
            blurRadius: 6,
          ),
        ],
      );
    } else if (isPast) {
      return const TextStyle(
        color: Color(0x6BFFFFFF),
        fontSize: 19,
        fontWeight: FontWeight.w600,
        height: 1.35,
        letterSpacing: -0.2,
      );
    } else {
      return const TextStyle(
        color: Color(0x3DFFFFFF),
        fontSize: 18,
        fontWeight: FontWeight.w500,
        height: 1.35,
        letterSpacing: -0.2,
      );
    }
  }

  Widget _buildSyncPillButton() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.mediumImpact();
          _resumeAutoScroll();
        },
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF1C1A14),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: const Color(0xB3FFD700),
              width: 1.2,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33FFD700),
                blurRadius: 16,
                spreadRadius: 2,
              ),
              BoxShadow(
                color: Colors.black54,
                blurRadius: 8,
              ),
            ],
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.sync_rounded,
                color: Color(0xFFFFD700),
                size: 18,
              ),
              SizedBox(width: 8),
              Text(
                'Senkrona Dön',
                style: TextStyle(
                  color: Color(0xFFFFD700),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0x14FFD700),
            ),
            child: const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFFD700)),
              strokeWidth: 2.5,
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Senkronize sözler aranıyor...',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'LRCLIB veritabanı sorgulanıyor',
            style: TextStyle(
              color: Color(0x59FFFFFF),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0x0AFFFFFF),
                border: Border.all(
                  color: const Color(0x14FFFFFF),
                  width: 1,
                ),
              ),
              child: const Icon(
                Icons.lyrics_outlined,
                color: Color(0x59FFFFFF),
                size: 40,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Bu parça için senkronize söz bulunamadı',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Şarkı adı veya sanatçı eşleşmesi LRCLIB arşivinde mevcut olmayabilir.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0x66FFFFFF),
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
