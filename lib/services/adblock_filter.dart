class AdBlockFilter {
  static final Set<String> _blockedDomains = {
    'doubleclick.net',
    'googleads.g.doubleclick.net',
    'pagead2.googlesyndication.com',
    'pubads.g.doubleclick.net',
    'adservice.google.com',
    'ad.doubleclick.net',
    'securepubads.g.doubleclick.net',
    'static.doubleclick.net',
    'cm.g.doubleclick.net',
    'tpc.googlesyndication.com',
    'googlesyndication.com',
    'pagead.l.google.com',
    'ads-fa.spotify.com',
    'audio-ak-spotify-com.akamaized.net',
  };

  static final List<String> _blockedPathPrefixes = [
    '/pagead',
    '/api/stats/ads',
    '/api/stats/qoe',
    '/ptracking',
    '/youtubei/v1/log_event',
    '/ad_break',
    '/get_midroll_info',
    '/pcs/view',
    '/ads',
    '/ad-logic',
  ];

  /// Ultra-fast non-blocking request filter
  static bool shouldBlock(Uri uri) {
    final host = uri.host;
    if (host.isEmpty) return false;

    // Fast O(1) domain check with sub-domain traversal
    String currentHost = host;
    while (true) {
      if (_blockedDomains.contains(currentHost)) return true;
      final dotIndex = currentHost.indexOf('.');
      if (dotIndex == -1 || dotIndex == currentHost.length - 1) break;
      currentHost = currentHost.substring(dotIndex + 1);
    }

    // Fast path check without regex overhead
    final path = uri.path;
    for (final prefix in _blockedPathPrefixes) {
      if (path.startsWith(prefix)) return true;
    }

    if (path.contains('generate_204') && uri.query.contains('ad')) {
      return true;
    }

    return false;
  }
}
