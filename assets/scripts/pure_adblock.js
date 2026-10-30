// PureTube - Advanced Zero-Ad Engine, SponsorBlock & Usability Core
(function() {
    'use strict';

    if (window.__pureTubeInjected) return;
    window.__pureTubeInjected = true;

    // --- 1. ZERO-AD JSON RESPONSE INTERCEPTOR (ROOT CAUSE FIX) ---
    // Intercept YouTube's internal player & browse API so YouTube NEVER receives or renders ads!
    function stripAdsFromJson(json) {
        let modified = false;
        if (!json || typeof json !== 'object') return false;

        if (json.playerResponse && typeof json.playerResponse === 'object') {
            if (stripAdsFromJson(json.playerResponse)) modified = true;
        }

        const adKeys = ['adPlacements', 'playerAds', 'adSlots', 'cueRanges', 'adBreakHeartbeatParams'];
        for (const key of adKeys) {
            if (json[key] !== undefined) {
                if (Array.isArray(json[key])) json[key] = [];
                delete json[key];
                modified = true;
            }
        }

        if (json.playbackTracking) {
            if (json.playbackTracking.atrUrl) delete json.playbackTracking.atrUrl;
            if (json.playbackTracking.qoeUrl) delete json.playbackTracking.qoeUrl;
        }
        return modified;
    }

    // Intercept window.ytInitialPlayerResponse before YouTube initializes
    let _rawInitialPlayerResponse = window.ytInitialPlayerResponse;
    try {
        Object.defineProperty(window, 'ytInitialPlayerResponse', {
            get: function() {
                return _rawInitialPlayerResponse;
            },
            set: function(val) {
                stripAdsFromJson(val);
                _rawInitialPlayerResponse = val;
            },
            configurable: true
        });
        if (_rawInitialPlayerResponse) {
            stripAdsFromJson(_rawInitialPlayerResponse);
        }
    } catch(e) {}

    // Intercept window.ytInitialData
    let _rawInitialData = window.ytInitialData;
    try {
        Object.defineProperty(window, 'ytInitialData', {
            get: function() {
                return _rawInitialData;
            },
            set: function(val) {
                stripAdsFromJson(val);
                _rawInitialData = val;
            },
            configurable: true
        });
        if (_rawInitialData) {
            stripAdsFromJson(_rawInitialData);
        }
    } catch(e) {}

    // Intercept window.ytplayer configs
    try {
        if (window.ytplayer && window.ytplayer.config && window.ytplayer.config.args) {
            let rpr = window.ytplayer.config.args.raw_player_response;
            if (typeof rpr === 'string') {
                try {
                    let parsed = JSON.parse(rpr);
                    if (stripAdsFromJson(parsed)) {
                        window.ytplayer.config.args.raw_player_response = JSON.stringify(parsed);
                    }
                } catch(e) {}
            } else if (rpr) {
                stripAdsFromJson(rpr);
            }
        }
    } catch(e) {}

    // Intercept fetch requests for player, browse and next
    try {
        const originalFetch = window.fetch;
        window.fetch = async function(...args) {
            const response = await originalFetch.apply(this, args);
            try {
                const reqUrl = typeof args[0] === 'string' ? args[0] : (args[0] && args[0].url ? args[0].url : '');
                const resUrl = response.url || '';
                if (
                    reqUrl.includes('/youtubei/v1/player') || resUrl.includes('/youtubei/v1/player') ||
                    reqUrl.includes('/youtubei/v1/next') || resUrl.includes('/youtubei/v1/next') ||
                    reqUrl.includes('/youtubei/v1/browse') || resUrl.includes('/youtubei/v1/browse')
                ) {
                    const clone = response.clone();
                    const json = await clone.json();
                    if (stripAdsFromJson(json)) {
                        notifyFlutter('onAdBlocked', { count: 1 });
                        const safeHeaders = new Headers(response.headers);
                        safeHeaders.delete('content-encoding');
                        safeHeaders.delete('content-length');
                        return new Response(JSON.stringify(json), {
                            headers: safeHeaders,
                            status: response.status,
                            statusText: response.statusText
                        });
                    }
                }
            } catch(e) {}
            return response;
        };

        // Also hook XMLHttpRequest for player API calls and ad trackings
        const originalOpen = XMLHttpRequest.prototype.open;
        const originalSend = XMLHttpRequest.prototype.send;
        XMLHttpRequest.prototype.open = function(method, url) {
            this._url = typeof url === 'string' ? url : '';
            return originalOpen.apply(this, arguments);
        };
        XMLHttpRequest.prototype.send = function() {
            if (this._url && (
                this._url.includes('/pagead/') || 
                this._url.includes('/api/stats/ads') || 
                this._url.includes('/ptracking') || 
                this._url.includes('/ad_break') ||
                this._url.includes('/get_midroll_info') ||
                this._url.includes('doubleclick.net') ||
                this._url.includes('googleads')
            )) {
                // Abort ad tracking requests silently
                return;
            }
            if (this._url && (this._url.includes('/youtubei/v1/player') || this._url.includes('/youtubei/v1/next'))) {
                this.addEventListener('readystatechange', function() {
                    if (this.readyState === 4 && this.status === 200) {
                        try {
                            const json = JSON.parse(this.responseText);
                            if (stripAdsFromJson(json)) {
                                Object.defineProperty(this, 'responseText', { value: JSON.stringify(json) });
                                Object.defineProperty(this, 'response', { value: JSON.stringify(json) });
                            }
                        } catch(e) {}
                    }
                });
            }
            return originalSend.apply(this, arguments);
        };
    } catch(e) {
        console.warn('[PureTube] Fetch interception error:', e);
    }

    // --- 2. ADVANCED BACKGROUND PLAYBACK & INACTIVITY-PAUSE BYPASS ---
    let isUserPaused = false;
    let lastUserInteractionTime = Date.now();

    window.__pureTubeAllowPause = function() {
        isUserPaused = true;
        lastUserInteractionTime = Date.now();
    };
    window.__pureTubeMarkInteraction = function() {
        isUserPaused = false;
        lastUserInteractionTime = Date.now();
    };

    const _mediaSessionHandlers = {};
    if (window.navigator && window.navigator.mediaSession) {
        try {
            const origSetAction = window.navigator.mediaSession.setActionHandler.bind(window.navigator.mediaSession);
            window.navigator.mediaSession.setActionHandler = function(action, handler) {
                _mediaSessionHandlers[action] = handler;
                return origSetAction(action, handler);
            };
        } catch(e) {}
    }

    try {
        // Track recent human interactions (touch, click, pointer)
        const markUserInteraction = () => {
            lastUserInteractionTime = Date.now();
        };
        ['touchstart', 'touchend', 'touchcancel', 'pointerdown', 'pointerup', 'mousedown', 'mouseup', 'click', 'keydown'].forEach(evt => {
            window.addEventListener(evt, markUserInteraction, { capture: true, passive: true });
            document.addEventListener(evt, markUserInteraction, { capture: true, passive: true });
        });

        // 1. Spoof Page Visibility API across all standards
        const falseGetter = () => false;
        const visibleGetter = () => 'visible';
        
        ['hidden', 'webkitHidden', 'mozHidden', 'msHidden'].forEach(prop => {
            try {
                Object.defineProperty(document, prop, { get: falseGetter, configurable: true });
            } catch(_) {}
        });

        ['visibilityState', 'webkitVisibilityState', 'mozVisibilityState', 'msVisibilityState'].forEach(prop => {
            try {
                Object.defineProperty(document, prop, { get: visibleGetter, configurable: true });
            } catch(_) {}
        });

        // Spoof document focus
        try {
            document.hasFocus = () => true;
        } catch(_) {}

        // 2. Block all events signaling background / loss of focus
        const backgroundEvents = [
            'visibilitychange',
            'webkitvisibilitychange',
            'mozvisibilitychange',
            'msvisibilitychange',
            'pagehide',
            'freeze',
            'blur',
            'focusout'
        ];
        backgroundEvents.forEach(evt => {
            window.addEventListener(evt, (e) => e.stopImmediatePropagation(), true);
            document.addEventListener(evt, (e) => e.stopImmediatePropagation(), true);
        });

        // 3. Prevent programmatic pause() triggered by backgrounding (allow when requested by notification or user)
        if (window.HTMLMediaElement && window.HTMLMediaElement.prototype) {
            const originalMediaPause = HTMLMediaElement.prototype.pause;
            HTMLMediaElement.prototype.pause = function(...args) {
                if (isUserPaused) {
                    return originalMediaPause.apply(this, args);
                }
                const timeSinceUser = Date.now() - lastUserInteractionTime;
                // If user touched screen in the last 2.5s, it was a deliberate touch on the web player
                if (timeSinceUser <= 2500) {
                    isUserPaused = true;
                    return originalMediaPause.apply(this, args);
                }
                // Background inactivity pause attempt detected: block it!
                console.log('[PureTube] Intercepted & prevented background pause (idle time: ' + timeSinceUser + 'ms)');
                return Promise.resolve();
            };

            // 4. Auto-resume fallback if video receives an unexpected pause event from background
            document.addEventListener('pause', (e) => {
                if (e.target && e.target.tagName === 'VIDEO') {
                    if (isUserPaused) return; // Deliberate user pause! Keep it paused!
                    const timeSinceUser = Date.now() - lastUserInteractionTime;
                    if (timeSinceUser > 2500) {
                        console.log('[PureTube] Auto-resuming video after background pause event');
                        setTimeout(() => {
                            if (!isUserPaused) {
                                try { e.target.play(); } catch(_) {}
                            }
                        }, 50);
                    } else {
                        isUserPaused = true;
                    }
                }
            }, true);

            document.addEventListener('play', (e) => {
                if (e.target && e.target.tagName === 'VIDEO') {
                    isUserPaused = false;
                }
                syncMediaMetadata();
            }, true);
        }

        // 5. Keep Screen Awake via Web API when playing
        if ('wakeLock' in navigator) {
            let wakeLock = null;
            const requestWakeLock = async () => {
                try {
                    wakeLock = await navigator.wakeLock.request('screen');
                    wakeLock.addEventListener('release', () => {
                        setTimeout(requestWakeLock, 1000);
                    });
                } catch(err) {}
            };
            requestWakeLock();
            document.addEventListener('visibilitychange', () => {
                if (!wakeLock || wakeLock.released) requestWakeLock();
            });
        }
    } catch(e) {
        console.warn('[PureTube] Background playback patch error:', e);
    }

    // --- 3. CONFIGURATION & STATE ---
    let sponsorSegments = [];
    let currentVideoId = '';
    let sponsorBlockEnabled = true;
    let adBlockEnabled = true;
    let blockedAdsCount = 0;
    let adWasPlaying = false;

    function notifyFlutter(event, data) {
        if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
            window.flutter_inappwebview.callHandler(event, data);
        }
    }

    // --- 4. VIDEO ID EXTRACTION ---
    function extractVideoId(url) {
        if (!url) url = window.location.href;
        let match = url.match(/[?&]v=([^&#]+)/);
        if (match) return match[1];
        match = url.match(/\/shorts\/([^&#/?]+)/);
        if (match) return match[1];
        match = url.match(/\/watch\/([^&#/?]+)/);
        if (match) return match[1];

        // YouTube Music active player bar fallback
        try {
            const playerBarLink = document.querySelector('ytmusic-player-bar a[href*="watch?v="]');
            if (playerBarLink) {
                const subMatch = playerBarLink.getAttribute('href').match(/[?&]v=([^&#]+)/);
                if (subMatch) return subMatch[1];
            }
        } catch(e) {}

        return null;
    }

    // --- 5. SPONSORBLOCK INTEGRATION ---
    async function fetchSponsorBlockSegments(videoId) {
        if (!videoId || !sponsorBlockEnabled) return;
        try {
            const url = `https://sponsor.ajay.app/api/skipSegments?videoID=${videoId}&categories=["sponsor","intro","outro","interaction","selfpromo"]`;
            const resp = await fetch(url);
            if (resp.status === 200) {
                const data = await resp.json();
                sponsorSegments = data.map(item => ({
                    start: item.segment[0],
                    end: item.segment[1],
                    category: item.category
                }));
                showToast(`SponsorBlock: ${sponsorSegments.length} sponsor bölümü yüklendi`);
            } else {
                sponsorSegments = [];
            }
        } catch (e) {
            sponsorSegments = [];
        }
    }

    function checkSponsorBlock(video) {
        if (!sponsorBlockEnabled || sponsorSegments.length === 0 || !video) return;
        const cur = video.currentTime;
        for (let i = 0; i < sponsorSegments.length; i++) {
            const seg = sponsorSegments[i];
            if (cur >= seg.start && cur < seg.end - 0.5) {
                video.currentTime = seg.end;
                showToast(`⚡ Sponsor atlandı (${seg.category})`);
                break;
            }
        }
    }

    // --- 6. INSTANT 0-MS VIDEO AD CLEANER ---
    function isAdPlayingNow() {
        const player = document.querySelector('.html5-video-player') || document.getElementById('movie_player');
        if (player && (player.classList.contains('ad-showing') || player.classList.contains('ad-interrupting'))) {
            return true;
        }
        if (document.querySelector('.ytp-ad-player-overlay, .ytp-ad-preview-container, .ytp-ad-text, .ytm-ad-overlay, .ad-showing, .ad-interrupting')) {
            return true;
        }
        const skipBtn = document.querySelector('.ytp-ad-skip-button, .ytp-ad-skip-button-modern, .ytm-ad-skip-button, button.ytp-ad-skip-button-slot');
        if (skipBtn) {
            return true;
        }
        return false;
    }

    function handleVideoAds() {
        if (!adBlockEnabled) return;

        const video = document.querySelector('video');
        if (!video) return;

        const player = document.querySelector('.html5-video-player') || document.getElementById('movie_player');
        const isAd = isAdPlayingNow();

        if (isAd) {
            adWasPlaying = true;
            blockedAdsCount++;
            notifyFlutter('onAdBlocked', { count: blockedAdsCount });

            // 1. Mute ad immediately so no sound leaks
            video.muted = true;

            // 2. Click any skip button immediately
            const skipButtons = [
                '.ytp-ad-skip-button',
                '.ytp-ad-skip-button-modern',
                '.ytp-skip-ad-button',
                '.ytm-ad-skip-button',
                '.videoAdUiSkipButton',
                'button.ytp-ad-skip-button-slot',
                '.ytp-ad-skip-button-text',
                'button[aria-label*="Skip" i]',
                'button[aria-label*="atla" i]'
            ];

            for (const selector of skipButtons) {
                const btn = document.querySelector(selector);
                if (btn && btn.offsetParent !== null) {
                    btn.click();
                    break;
                }
            }

            // 3. Fast-forward the ad stream directly to the end
            if (isFinite(video.duration) && video.duration > 0) {
                video.currentTime = video.duration;
            }
            video.playbackRate = 16.0;

            // 4. Call native player skipAd / cancelPlayback if exposed
            if (player) {
                if (typeof player.skipAd === 'function') {
                    try { player.skipAd(); } catch(e) {}
                }
                if (typeof player.cancelPlayback === 'function') {
                    try { player.cancelPlayback(); } catch(e) {}
                }
            }
        } else {
            // Main video is active: Ensure normal playback state
            if (adWasPlaying || video.playbackRate > 2.0) {
                adWasPlaying = false;
                video.playbackRate = 1.0;
                video.muted = false;
            }
        }

        // Auto close overlay ads
        const closeButtons = document.querySelectorAll('.ytp-ad-overlay-close-button, .ytp-ad-image-overlay-close-btn');
        closeButtons.forEach(btn => btn.click());

        // SponsorBlock check
        if (!isAd) {
            checkSponsorBlock(video);
        }
    }

    // Attach immediate event hooks on video elements
    document.addEventListener('timeupdate', (e) => {
        if (e.target && e.target.tagName === 'VIDEO') {
            handleVideoAds();
        }
    }, true);

    document.addEventListener('play', (e) => {
        if (e.target && e.target.tagName === 'VIDEO') {
            handleVideoAds();
        }
    }, true);

    // --- 7. REMOVE PROMOTIONS & YT MUSIC OPEN-APP BUTTONS ---
    function killYtMusicOpenAppButton() {
        const nav = document.querySelector('ytmusic-nav-bar');
        if (!nav) return;

        // Only search strictly inside ytmusic-nav-bar and its shadowRoot
        const roots = [nav];
        if (nav.shadowRoot) roots.push(nav.shadowRoot);

        roots.forEach(root => {
            const btns = root.querySelectorAll('a, button, yt-button-renderer, yt-button-shape, .yt-spec-button-shape-next');
            btns.forEach(btn => {
                const text = (btn.innerText || btn.textContent || '').trim().replace(/\s+/g, ' ').toLowerCase();
                const aria = (btn.getAttribute('aria-label') || '').toLowerCase();
                const href = (btn.getAttribute('href') || '').toLowerCase();

                if (
                    (text.length < 25 && (text.includes('uygulamayı') || text.includes('open app') || text.includes('uygulama'))) ||
                    aria.includes('uygulamayı') || aria.includes('open app') ||
                    href.includes('play.google.com') || href.includes('market://')
                ) {
                    btn.style.setProperty('display', 'none', 'important');
                    btn.style.setProperty('visibility', 'hidden', 'important');
                    btn.style.setProperty('width', '0px', 'important');
                    btn.style.setProperty('height', '0px', 'important');
                    btn.remove();
                }
            });
        });
    }

    function cleanDomElements() {
        const adSelectors = [
            'ytd-promoted-video-renderer',
            'ytd-promoted-sparkles-web-renderer',
            'ytm-promoted-sparkles-web-renderer',
            'ytm-companion-ad-renderer',
            'ytd-action-companion-ad-renderer',
            'ytd-display-ad-renderer',
            'ytd-ad-slot-renderer',
            'ytm-ad-slot-renderer',
            'ytm-promoted-video-renderer',
            '#player-ads',
            '.ad-container',
            '.ad-display',
            'ytm-mealbar-promo-renderer',
            'ytmusic-mealbar-promo-renderer',
            'yt-upsell-dialog-renderer',
            'ytmusic-upsell-dialog-renderer',
            'ytm-app-banner',
            'ytmusic-app-navigation-bar-renderer',
            'ytmusic-open-in-app-renderer',
            '.open-in-app',
            '.open-in-app-button',
            'ytmusic-banner-renderer',
            'ytm-merch-shelf-renderer',
            'ytm-paid-content-overlay-renderer'
        ];

        adSelectors.forEach(sel => {
            const elements = document.querySelectorAll(sel);
            elements.forEach(el => el.remove());
        });

        killYtMusicOpenAppButton();
    }

    // --- 8. MINIMAL FLOATING TOAST ---
    function showToast(message) {
        let toast = document.getElementById('puretube-toast');
        if (!toast) {
            toast = document.createElement('div');
            toast.id = 'puretube-toast';
            toast.style.cssText = `
                position: fixed;
                bottom: 70px;
                left: 50%;
                transform: translateX(-50%);
                background: rgba(18, 18, 18, 0.92);
                color: #00e676;
                padding: 8px 18px;
                border-radius: 20px;
                font-size: 13px;
                font-family: sans-serif;
                font-weight: 600;
                z-index: 9999999;
                pointer-events: none;
                box-shadow: 0 4px 14px rgba(0,0,0,0.5);
                transition: opacity 0.3s;
                opacity: 0;
            `;
            document.body.appendChild(toast);
        }
        toast.textContent = message;
        toast.style.opacity = '1';
        clearTimeout(window.__pureToastTimer);
        window.__pureToastTimer = setTimeout(() => {
            toast.style.opacity = '0';
        }, 2200);
    }

    // --- 9. URL MONITORING ---
    function checkUrlChange() {
        const newId = extractVideoId(window.location.href);
        if (newId && newId !== currentVideoId) {
            currentVideoId = newId;
            notifyFlutter('onVideoChanged', { videoId: newId, url: window.location.href });
            fetchSponsorBlockSegments(newId);
        }
    }

    // --- 10. JAVASCRIPT BRIDGE & CONTROL ---
    window.pureTubeControl = {
        seekBy: function(seconds) {
            const video = document.querySelector('video');
            if (video) {
                video.currentTime = Math.max(0, video.currentTime + seconds);
                showToast((seconds > 0 ? `+${seconds}` : `${seconds}`) + ' sn');
                syncMediaMetadata();
            }
        },
        seekTo: function(seconds) {
            window.__pureTubeMarkInteraction();
            const video = document.querySelector('video');
            if (video) {
                video.currentTime = Math.max(0, Math.min(seconds, isFinite(video.duration) ? video.duration : seconds));
                syncMediaMetadata();
            }
        },
        play: function() {
            window.__pureTubeMarkInteraction();
            console.log('[PureTube] pureTubeControl.play() called');
            const video = document.querySelector('video');
            if (video && video.paused) {
                try { video.play(); } catch(e) {}
            }
            if (typeof _mediaSessionHandlers['play'] === 'function') {
                try { _mediaSessionHandlers['play']({ action: 'play' }); } catch(e) {}
            }
            const ytMusicPlay = document.querySelector('ytmusic-player-bar #play-pause-button[aria-label*="Play" i], ytmusic-player-bar #play-pause-button[aria-label*="Oynat" i], ytmusic-player-bar .play-pause-button');
            if (ytMusicPlay && video && video.paused) {
                try { ytMusicPlay.click(); } catch(e) {}
            }
            const ytPlay = document.querySelector('.player-control-play-pause-icon, .ytp-play-button, button[aria-label*="Play" i], button[aria-label*="Oynat" i]');
            if (ytPlay && video && video.paused) {
                try { ytPlay.click(); } catch(e) {}
            }
            syncMediaMetadata();
        },
        pause: function() {
            window.__pureTubeAllowPause();
            console.log('[PureTube] pureTubeControl.pause() called');
            const video = document.querySelector('video');
            if (video && !video.paused) {
                try { video.pause(); } catch(e) {}
            }
            if (typeof _mediaSessionHandlers['pause'] === 'function') {
                try { _mediaSessionHandlers['pause']({ action: 'pause' }); } catch(e) {}
            }
            const ytMusicPause = document.querySelector('ytmusic-player-bar #play-pause-button[aria-label*="Pause" i], ytmusic-player-bar #play-pause-button[aria-label*="Duraklat" i], ytmusic-player-bar #play-pause-button[aria-label*="Durdur" i]');
            if (ytMusicPause && video && !video.paused) {
                try { ytMusicPause.click(); } catch(e) {}
            }
            const ytPause = document.querySelector('.player-control-play-pause-icon, .ytp-play-button, button[aria-label*="Pause" i], button[aria-label*="Duraklat" i], button[aria-label*="Durdur" i]');
            if (ytPause && video && !video.paused) {
                try { ytPause.click(); } catch(e) {}
            }
            syncMediaMetadata();
        },
        togglePlay: function() {
            const video = document.querySelector('video');
            if (video && !video.paused) {
                this.pause();
            } else {
                this.play();
            }
        },
        nextTrack: function() {
            window.__pureTubeMarkInteraction();
            console.log('[PureTube] pureTubeControl.nextTrack() called');

            const clickElement = (el) => {
                if (!el) return false;
                try { el.click(); } catch(e) {}
                try {
                    const inner = el.querySelector('button') || (el.shadowRoot && el.shadowRoot.querySelector('button'));
                    if (inner) inner.click();
                } catch(e) {}
                try {
                    el.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true, view: window }));
                } catch(e) {}
                return true;
            };

            // 1. Try movie_player (Internal HTML5 Player API used by YouTube & YT Music)
            try {
                const player = document.getElementById('movie_player') || document.querySelector('.html5-video-player');
                if (player && typeof player.nextVideo === 'function') {
                    console.log('[PureTube] Using movie_player.nextVideo()');
                    player.nextVideo();
                }
            } catch(e) {
                console.warn('[PureTube] player.nextVideo error:', e);
            }

            // 2. Try MediaSession handler with W3C action details
            if (typeof _mediaSessionHandlers['nexttrack'] === 'function') {
                try {
                    console.log('[PureTube] Using mediaSessionHandler nexttrack');
                    _mediaSessionHandlers['nexttrack']({ action: 'nexttrack' });
                } catch(e) {
                    console.warn('[PureTube] mediaSession nexttrack error:', e);
                }
            }

            // 3. Try clicking Next buttons across YouTube Music and YouTube
            const nextSelectors = [
                'ytmusic-player-bar .next-button',
                'ytmusic-player-bar [aria-label*="Next" i]',
                'ytmusic-player-bar [aria-label*="Sonraki" i]',
                'ytmusic-player-page .next-button',
                'ytmusic-player-page [aria-label*="Next" i]',
                'ytmusic-player-page [aria-label*="Sonraki" i]',
                'tp-yt-paper-icon-button.next-button',
                'tp-yt-paper-icon-button[aria-label*="Next" i]',
                'tp-yt-paper-icon-button[aria-label*="Sonraki" i]',
                'yt-icon-button.next-button',
                'yt-icon-button[aria-label*="Next" i]',
                'yt-icon-button[aria-label*="Sonraki" i]',
                'button.next-button',
                '#next-button',
                '.next-button',
                '[aria-label*="Sonraki parça" i]',
                '[aria-label*="Sonraki video" i]',
                '[aria-label*="Sonraki" i]',
                '[aria-label*="Next track" i]',
                '[aria-label*="Next video" i]',
                '[aria-label*="Next song" i]',
                '[aria-label*="Skip to next" i]',
                '.ytp-next-button',
                '.ytm-next-button',
                'button[aria-label*="Sonraki" i]',
                'button[aria-label*="Next" i]',
                '.icon-button[aria-label*="Sonraki" i]',
                '.icon-button[aria-label*="Next" i]'
            ];

            let clicked = false;
            for (const sel of nextSelectors) {
                const btn = document.querySelector(sel);
                if (btn && (btn.offsetParent !== null || btn.offsetWidth > 0 || btn.offsetHeight > 0)) {
                    console.log('[PureTube] Clicked next button selector:', sel);
                    clicked = clickElement(btn);
                    break;
                }
            }

            // 4. If YouTube mobile watch page without playlist, click first Up Next recommendation
            if (!clicked) {
                const upNext = document.querySelector(
                    'ytm-compact-video-renderer a.compact-media-item-image, ' +
                    'ytm-compact-video-renderer a.compact-media-item-metadata-content, ' +
                    'ytm-single-column-watch-next-results-renderer a[href*="watch?v="], ' +
                    'ytm-item-section-renderer ytm-video-with-context-renderer a, ' +
                    'a.compact-media-item-headline'
                );
                if (upNext) {
                    console.log('[PureTube] Clicked up-next recommendation');
                    clicked = clickElement(upNext);
                }
            }

            // 5. Fallback: seek to video end and play to force autoplay transition
            const video = document.querySelector('video');
            if (video && isFinite(video.duration) && video.duration > 0) {
                console.log('[PureTube] Seeking to end of video for autoplay next');
                video.currentTime = Math.max(0, video.duration - 0.2);
                try { video.play(); } catch(e) {}
            }

            setTimeout(syncMediaMetadata, 500);
        },
        prevTrack: function() {
            window.__pureTubeMarkInteraction();
            console.log('[PureTube] pureTubeControl.prevTrack() called');

            const video = document.querySelector('video');
            if (video && video.currentTime > 3.0) {
                console.log('[PureTube] Seeking to start of video');
                video.currentTime = 0;
                setTimeout(syncMediaMetadata, 300);
                return;
            }

            const clickElement = (el) => {
                if (!el) return false;
                try { el.click(); } catch(e) {}
                try {
                    const inner = el.querySelector('button') || (el.shadowRoot && el.shadowRoot.querySelector('button'));
                    if (inner) inner.click();
                } catch(e) {}
                try {
                    el.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true, view: window }));
                } catch(e) {}
                return true;
            };

            // 1. Try movie_player
            try {
                const player = document.getElementById('movie_player') || document.querySelector('.html5-video-player');
                if (player && typeof player.previousVideo === 'function') {
                    console.log('[PureTube] Using movie_player.previousVideo()');
                    player.previousVideo();
                }
            } catch(e) {
                console.warn('[PureTube] player.previousVideo error:', e);
            }

            // 2. Try MediaSession handler with action details
            if (typeof _mediaSessionHandlers['previoustrack'] === 'function') {
                try {
                    console.log('[PureTube] Using mediaSessionHandler previoustrack');
                    _mediaSessionHandlers['previoustrack']({ action: 'previoustrack' });
                } catch(e) {
                    console.warn('[PureTube] mediaSession previoustrack error:', e);
                }
            }

            // 3. Try clicking Prev buttons
            const prevSelectors = [
                'ytmusic-player-bar .previous-button',
                'ytmusic-player-bar [aria-label*="Previous" i]',
                'ytmusic-player-bar [aria-label*="Önceki" i]',
                'ytmusic-player-page .previous-button',
                'ytmusic-player-page [aria-label*="Previous" i]',
                'ytmusic-player-page [aria-label*="Önceki" i]',
                'tp-yt-paper-icon-button.previous-button',
                'tp-yt-paper-icon-button[aria-label*="Previous" i]',
                'tp-yt-paper-icon-button[aria-label*="Önceki" i]',
                'yt-icon-button.previous-button',
                'yt-icon-button[aria-label*="Previous" i]',
                'yt-icon-button[aria-label*="Önceki" i]',
                'button.previous-button',
                '#previous-button',
                '.previous-button',
                '[aria-label*="Önceki parça" i]',
                '[aria-label*="Önceki video" i]',
                '[aria-label*="Önceki" i]',
                '[aria-label*="Previous track" i]',
                '[aria-label*="Previous video" i]',
                '[aria-label*="Previous song" i]',
                '.ytp-prev-button',
                '.ytm-prev-button',
                'button[aria-label*="Önceki" i]',
                'button[aria-label*="Previous" i]',
                '.icon-button[aria-label*="Önceki" i]',
                '.icon-button[aria-label*="Previous" i]'
            ];

            let clicked = false;
            for (const sel of prevSelectors) {
                const btn = document.querySelector(sel);
                if (btn && (btn.offsetParent !== null || btn.offsetWidth > 0 || btn.offsetHeight > 0)) {
                    console.log('[PureTube] Clicked prev button selector:', sel);
                    clicked = clickElement(btn);
                    break;
                }
            }

            if (!clicked && video) {
                video.currentTime = 0;
            }

            setTimeout(syncMediaMetadata, 500);
        },
        setSponsorBlockEnabled: function(enabled) {
            sponsorBlockEnabled = enabled;
            if (enabled && currentVideoId) fetchSponsorBlockSegments(currentVideoId);
        },
        setAdBlockEnabled: function(enabled) {
            adBlockEnabled = enabled;
        },
        setPipMode: function(enabled) {
            if (enabled) {
                document.body.classList.add('pure-pip-active');
                const video = document.querySelector('video');
                if (video) {
                    try {
                        if (video.paused) video.play();
                        video.scrollIntoView({ behavior: 'instant', block: 'center' });
                    } catch(e) {}
                }
            } else {
                document.body.classList.remove('pure-pip-active');
            }
        }
    };

    // --- 11. MEDIA METADATA OBSERVER FOR SYSTEM NOTIFICATION ---
    let lastSentMedia = { title: '', artist: '', artwork: '', isPlaying: false, position: -1, duration: -1 };

    function syncMediaMetadata() {
        const video = document.querySelector('video');
        if (!video) return;

        let title = '';
        let artist = '';
        let artwork = '';

        // 1. Prioritize navigator.mediaSession.metadata (most accurate and high-res on both YT and YT Music)
        if (window.navigator && window.navigator.mediaSession && window.navigator.mediaSession.metadata) {
            const m = window.navigator.mediaSession.metadata;
            if (m.title) title = m.title;
            if (m.artist) artist = m.artist;
            if (m.artwork && m.artwork.length > 0) {
                artwork = m.artwork[m.artwork.length - 1].src || m.artwork[0].src || '';
            }
        }

        const isMusic = window.location.hostname.includes('music.youtube.com');
        if (!title && isMusic) {
            const tEl = document.querySelector('ytmusic-player-bar .title, ytmusic-player-page .title, .content-info-wrapper .title');
            const aEl = document.querySelector('ytmusic-player-bar .byline, ytmusic-player-bar .subtitle, ytmusic-player-page .subtitle');
            const imgEl = document.querySelector('ytmusic-player-bar .image, ytmusic-player-bar img');
            if (tEl) title = tEl.innerText || tEl.textContent;
            if (aEl) artist = aEl.innerText || aEl.textContent;
            if (imgEl && !artwork) artwork = imgEl.src;
        } else if (!title) {
            const tEl = document.querySelector('.slim-video-metadata-title, h1.title, h1, .ytm-slim-video-metadata-title');
            const cEl = document.querySelector('.ytm-channel-thumbnail-with-link-name, .owner-name, ytm-channel-thumbnail-with-link-renderer .name');
            if (tEl) title = tEl.innerText || tEl.textContent;
            if (cEl) artist = cEl.innerText || cEl.textContent;
            if (currentVideoId && !artwork) {
                artwork = `https://i.ytimg.com/vi/${currentVideoId}/hqdefault.jpg`;
            }
        }

        if (!title && document.title) {
            title = document.title.replace(' - YouTube Music', '').replace(' - YouTube', '').trim();
        }

        title = (title || '').trim();
        const lowerTitle = title.toLowerCase();
        if (lowerTitle === 'youtube' || lowerTitle === 'youtube music' || lowerTitle === 'home' || lowerTitle === 'ana sayfa') {
            title = '';
        }

        artist = (artist || '').trim();
        if (!artist) {
            artist = isMusic ? 'YouTube Music' : 'YouTube';
        }
        const isPlaying = !video.paused;
        const currentPosSec = video.currentTime || 0;
        const durationSec = (isFinite(video.duration) && video.duration > 0) ? video.duration : 0;
        const positionMs = Math.floor(currentPosSec * 1000);
        const durationMs = Math.floor(durationSec * 1000);

        const metadataChanged = (title !== lastSentMedia.title || artist !== lastSentMedia.artist || isPlaying !== lastSentMedia.isPlaying || Math.abs(durationMs - (lastSentMedia.duration || 0)) > 1000);
        const positionDiffSec = Math.abs(currentPosSec - ((lastSentMedia.position || 0) / 1000));

        if (title && (metadataChanged || positionDiffSec >= 2.5)) {
            lastSentMedia = { title, artist, artwork, isPlaying, position: positionMs, duration: durationMs };
            notifyFlutter('onMediaMetadataChanged', {
                source: isMusic ? 'music' : 'youtube',
                title: title,
                artist: artist,
                artwork: artwork,
                isPlaying: isPlaying,
                positionMs: positionMs,
                durationMs: durationMs
            });
        }
    }

    setInterval(syncMediaMetadata, 1000);
    document.addEventListener('play', syncMediaMetadata, true);
    document.addEventListener('pause', syncMediaMetadata, true);
    document.addEventListener('seeked', syncMediaMetadata, true);

    // --- 10. FULLSCREEN & ORIENTATION CONTROLLER ---
    function getVideoOrientation() {
        if (window.location.href.includes('/shorts/')) {
            return 'portrait';
        }
        const player = document.querySelector('.html5-video-player');
        if (player && (player.classList.contains('ytp-vertical-video') || player.classList.contains('ytp-fit-vertical-video'))) {
            return 'portrait';
        }
        const video = document.querySelector('video');
        if (video && video.videoWidth > 0 && video.videoHeight > 0) {
            return (video.videoHeight > video.videoWidth) ? 'portrait' : 'landscape';
        }
        return 'landscape';
    }

    function dispatchFullscreenToggle(isFs) {
        const orientation = getVideoOrientation();
        notifyFlutter('onFullscreenToggle', {
            isFullscreen: isFs,
            orientation: orientation
        });
    }

    document.addEventListener('fullscreenchange', () => {
        const isFullscreen = !!document.fullscreenElement;
        dispatchFullscreenToggle(isFullscreen);
    });
    document.addEventListener('webkitfullscreenchange', () => {
        const isFullscreen = !!document.webkitFullscreenElement;
        dispatchFullscreenToggle(isFullscreen);
    });

    document.addEventListener('click', (e) => {
        const fsBtn = e.target.closest('.ytp-fullscreen-button, button[aria-label*="Tam ekran"], button[aria-label*="Fullscreen"], .fullscreen-icon');
        if (fsBtn) {
            setTimeout(() => {
                const isFullscreen = !!(document.fullscreenElement || document.webkitFullscreenElement || document.querySelector('.ytp-fullscreen'));
                dispatchFullscreenToggle(isFullscreen);
            }, 60);
        }
    }, true);

    // --- 11. HIGH-PERFORMANCE DOM OBSERVER (ELIMINATES STUTTER) ---
    let cleanTimeout = null;
    function scheduleClean() {
        if (cleanTimeout) return;
        cleanTimeout = setTimeout(() => {
            cleanDomElements();
            handleVideoAds();
            cleanTimeout = null;
        }, 150);
    }

    const observer = new MutationObserver((mutations) => {
        for (let i = 0; i < mutations.length; i++) {
            if (mutations[i].addedNodes.length > 0) {
                scheduleClean();
                break;
            }
        }
    });

    if (document.body) {
        observer.observe(document.body, { childList: true, subtree: true });
    } else {
        document.addEventListener('DOMContentLoaded', () => {
            observer.observe(document.body, { childList: true, subtree: true });
        });
    }

    // Battery-friendly unified background heartbeat
    setInterval(handleVideoAds, 500);
    setInterval(() => {
        checkUrlChange();
        cleanDomElements();
    }, 1500);

    checkUrlChange();
    cleanDomElements();
    handleVideoAds();
    console.log('[PureTube] Ultra-Smooth High-Performance Engine Initialized.');
})();
