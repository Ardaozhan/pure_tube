// PureTube - Advanced Zero-Ad Engine, SponsorBlock v2, Return YouTube Dislike & Usability Core
(function() {
    'use strict';

    if (window.__pureTubeInjected) return;
    window.__pureTubeInjected = true;

    // --- 1. ZERO-AD JSON RESPONSE INTERCEPTOR & ANTI-ADBLOCK BYPASS ---
    // Intercept YouTube's internal player & browse API so YouTube NEVER receives or renders ads!
    function stripAdsFromJson(json) {
        let modified = false;
        if (!json || typeof json !== 'object') return false;

        if (json.playerResponse && typeof json.playerResponse === 'object') {
            if (stripAdsFromJson(json.playerResponse)) modified = true;
        }

        // Strip all known ad payloads, SSAI cue ranges and ad slots
        const adKeys = [
            'adPlacements', 'playerAds', 'adSlots', 'cueRanges', 
            'adBreakHeartbeatParams', 'adBreakService', 'adBreakRenderer',
            'adBreakResponse', 'adBreakParams'
        ];
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
            if (json.playbackTracking.ptrackingUrl) delete json.playbackTracking.ptrackingUrl;
        }

        // Anti-Adblock modal suppression in playabilityStatus
        if (json.playabilityStatus && typeof json.playabilityStatus === 'object') {
            const status = json.playabilityStatus.status;
            const reason = (json.playabilityStatus.reason || '').toLowerCase();
            if (status !== 'OK') {
                if (reason.includes('ad blocker') || reason.includes('reklam engelle') || reason.includes('terms of service')) {
                    json.playabilityStatus.status = 'OK';
                    delete json.playabilityStatus.reason;
                    delete json.playabilityStatus.messages;
                    delete json.playabilityStatus.errorScreen;
                    modified = true;
                }
            }
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

        // Hook XMLHttpRequest for player API calls and ad trackings
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
        const markUserInteraction = () => {
            lastUserInteractionTime = Date.now();
        };
        ['touchstart', 'touchend', 'touchcancel', 'pointerdown', 'pointerup', 'mousedown', 'mouseup', 'click', 'keydown'].forEach(evt => {
            window.addEventListener(evt, markUserInteraction, { capture: true, passive: true });
            document.addEventListener(evt, markUserInteraction, { capture: true, passive: true });
        });

        // Spoof Page Visibility API across all standards
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

        try {
            Object.defineProperty(document, 'onvisibilitychange', { get: () => null, set: () => {}, configurable: true });
        } catch(_) {}

        try {
            document.hasFocus = () => true;
        } catch(_) {}

        if (typeof window.requestAnimationFrame === 'function') {
            const _origRAF = window.requestAnimationFrame.bind(window);
            window.requestAnimationFrame = function(callback) {
                if (document.hidden || document.visibilityState === 'hidden' || !document.hasFocus()) {
                    return setTimeout(() => callback(performance.now()), 16);
                }
                return _origRAF(callback);
            };
        }

        if (window.AudioContext || window.webkitAudioContext) {
            const AudioCtx = window.AudioContext || window.webkitAudioContext;
            if (AudioCtx.prototype && AudioCtx.prototype.suspend) {
                AudioCtx.prototype.suspend = function() {
                    console.log('[PureTube] Blocked AudioContext.suspend()');
                    return Promise.resolve();
                };
            }
        }

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

        document.addEventListener('click', (e) => {
            const btn = e.target.closest('button, [role="button"], yt-icon-button, tp-yt-paper-icon-button, .play-pause-button');
            if (btn) {
                const label = (btn.getAttribute('aria-label') || btn.innerText || btn.className || '').toLowerCase();
                if (label.includes('pause') || label.includes('durdur')) {
                    isUserPaused = true;
                    console.log('[PureTube] Explicit user pause clicked on web player');
                } else if (label.includes('play') || label.includes('oynat')) {
                    isUserPaused = false;
                    console.log('[PureTube] Explicit user play clicked on web player');
                }
            }
        }, true);

        if (window.HTMLMediaElement && window.HTMLMediaElement.prototype) {
            const originalMediaPause = HTMLMediaElement.prototype.pause;
            HTMLMediaElement.prototype.pause = function(...args) {
                if (isUserPaused) {
                    return originalMediaPause.apply(this, args);
                }
                console.log('[PureTube] Intercepted & prevented unwanted background pause on ' + this.tagName);
                return Promise.resolve();
            };

            const handleMediaPauseEvent = (e) => {
                const el = e.target;
                if (el && (el.tagName === 'VIDEO' || el.tagName === 'AUDIO')) {
                    if (isUserPaused) return;
                    setTimeout(() => {
                        if (!isUserPaused) {
                            try { el.play(); } catch(_) {}
                        }
                    }, 20);
                }
            };
            document.addEventListener('pause', handleMediaPauseEvent, true);
            window.addEventListener('pause', handleMediaPauseEvent, true);

            const handleMediaPlayEvent = (e) => {
                const el = e.target;
                if (el && (el.tagName === 'VIDEO' || el.tagName === 'AUDIO')) {
                    isUserPaused = false;
                }
                syncMediaMetadata();
            };
            document.addEventListener('play', handleMediaPlayEvent, true);
            window.addEventListener('play', handleMediaPlayEvent, true);

            setInterval(() => {
                const media = document.querySelector('video') || document.querySelector('audio');
                if (media && media.paused && !isUserPaused && media.currentTime > 0 && media.currentTime < (media.duration - 0.5)) {
                    console.log('[PureTube Watchdog] Waking up stalled media element in background');
                    try { media.play(); } catch(_) {}
                }
            }, 1500);
        }

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

    // --- 3. CONFIGURATION, STATE & CATEGORY METRICS ---
    let currentVideoId = '';
    let sponsorSegments = [];
    let sponsorBlockEnabled = true;
    let adBlockEnabled = true;
    let blockedAdsCount = 0;
    let adWasPlaying = false;
    let lastSkippedSegment = null;

    // RYD (Return YouTube Dislike) State
    let currentRydVotes = null;
    let lastRydVideoId = '';
    let rydFetchInProgress = false;

    const SB_COLORS = {
        sponsor: '#00d66c',        // Emerald Green
        intro: '#00e5ff',          // Cyan
        intermission: '#00e5ff',   // Cyan
        outro: '#3d5afe',          // Indigo / Blue
        selfpromo: '#ffeb3b',      // Amber Yellow
        interaction: '#e040fb',    // Neon Magenta
        music_offtopic: '#ff9100', // Orange
        preview: '#00b0ff'         // Light Blue
    };

    const SB_TITLES = {
        sponsor: 'Sponsor',
        intro: 'İntro / Giriş',
        intermission: 'Ara',
        outro: 'Bitiş / Jenerik',
        selfpromo: 'Kişisel Tanıtım',
        interaction: 'Abone Ol / Beğen',
        music_offtopic: 'Konu Dışı Müzik',
        preview: 'Önizleme'
    };

    function notifyFlutter(event, data) {
        if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
            window.flutter_inappwebview.callHandler(event, data);
        }
    }

    function formatMetric(num) {
        if (typeof num !== 'number' || isNaN(num)) return '0';
        if (num >= 1e9) {
            const v = (num / 1e9).toFixed(1);
            return (v.endsWith('.0') ? v.slice(0, -2) : v) + 'B';
        }
        if (num >= 1e6) {
            const v = (num / 1e6).toFixed(1);
            return (v.endsWith('.0') ? v.slice(0, -2) : v) + 'M';
        }
        if (num >= 1e3) {
            const v = (num / 1e3).toFixed(1);
            return (v.endsWith('.0') ? v.slice(0, -2) : v) + 'K';
        }
        return String(num);
    }

    function formatTimestamp(seconds) {
        if (typeof seconds !== 'number' || isNaN(seconds) || seconds < 0) return '0:00';
        const m = Math.floor(seconds / 60);
        const s = Math.floor(seconds % 60);
        return m + ':' + (s < 10 ? '0' : '') + s;
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

        try {
            const playerBarLink = document.querySelector('ytmusic-player-bar a[href*="watch?v="]');
            if (playerBarLink) {
                const subMatch = playerBarLink.getAttribute('href').match(/[?&]v=([^&#]+)/);
                if (subMatch) return subMatch[1];
            }
        } catch(e) {}

        return null;
    }

    // --- 5. SPONSORBLOCK V2 API & SEEKBAR SEGMENTS ---
    function findProgressBarTrack() {
        return document.querySelector(
            '.ytp-progress-bar, ' +
            '.segmented-progress-bar, ' +
            '.ytp-progress-list, ' +
            '.ytm-progress-bar, ' +
            'ytm-progress-bar, ' +
            '.chapter-hover-container'
        );
    }

    function removeSeekbarSegments() {
        const old = document.getElementById('puretube-sb-segments');
        if (old) old.remove();
    }

    function renderSeekbarSegments() {
        if (!sponsorBlockEnabled || sponsorSegments.length === 0) {
            removeSeekbarSegments();
            return;
        }

        const track = findProgressBarTrack();
        const video = document.querySelector('video');
        if (!track || !video || !isFinite(video.duration) || video.duration <= 0) return;

        const duration = video.duration;
        let container = document.getElementById('puretube-sb-segments');
        if (!container) {
            container = document.createElement('div');
            container.id = 'puretube-sb-segments';
            track.style.position = 'relative';
            track.appendChild(container);
        } else if (container.parentElement !== track) {
            track.appendChild(container);
        }

        container.innerHTML = '';
        for (let i = 0; i < sponsorSegments.length; i++) {
            const seg = sponsorSegments[i];
            if (seg.start >= duration) continue;

            const startPct = Math.max(0, Math.min(100, (seg.start / duration) * 100));
            const endPct = Math.max(0, Math.min(100, (seg.end / duration) * 100));
            const widthPct = Math.max(0.4, endPct - startPct);

            const segEl = document.createElement('div');
            segEl.className = 'puretube-sb-segment';
            segEl.style.left = startPct + '%';
            segEl.style.width = widthPct + '%';
            segEl.style.backgroundColor = SB_COLORS[seg.category] || '#00d66c';
            segEl.title = `${SB_TITLES[seg.category] || seg.category} (${formatTimestamp(seg.start)} - ${formatTimestamp(seg.end)})`;
            container.appendChild(segEl);
        }
    }

    async function fetchSponsorBlockSegments(videoId) {
        if (!videoId || !sponsorBlockEnabled) return;
        try {
            // 1. Try Flutter bridge first
            if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
                try {
                    const bridgeRes = await window.flutter_inappwebview.callHandler('fetchSponsorSegments', { videoId: videoId });
                    if (Array.isArray(bridgeRes) && bridgeRes.length > 0) {
                        sponsorSegments = bridgeRes.map(item => ({
                            start: item.startTime !== undefined ? Number(item.startTime) : (item.segment ? Number(item.segment[0]) : 0),
                            end: item.endTime !== undefined ? Number(item.endTime) : (item.segment ? Number(item.segment[1]) : 0),
                            category: item.category || 'sponsor',
                            uuid: item.UUID || item.uuid || ''
                        }));
                        renderSeekbarSegments();
                        return;
                    }
                } catch(_) {}
            }

            // 2. Direct SponsorBlock v2 API fallback
            const categories = '["sponsor","intro","outro","selfpromo","interaction","music_offtopic"]';
            const url = `https://sponsor.ajay.app/api/skipSegments?videoID=${videoId}&categories=${encodeURIComponent(categories)}`;
            const resp = await fetch(url);
            if (resp.status === 200) {
                const data = await resp.json();
                if (Array.isArray(data)) {
                    sponsorSegments = data.map(item => ({
                        start: item.segment ? item.segment[0] : (item.startTime || 0),
                        end: item.segment ? item.segment[1] : (item.endTime || 0),
                        category: item.category || 'sponsor',
                        uuid: item.UUID || item.uuid || ''
                    }));
                    renderSeekbarSegments();
                }
            } else {
                sponsorSegments = [];
                removeSeekbarSegments();
            }
        } catch (e) {
            sponsorSegments = [];
            removeSeekbarSegments();
        }
    }

    let badgeTimer = null;
    function showSponsorBadge(seg, fromTime) {
        let badge = document.getElementById('puretube-sponsor-badge');
        if (!badge) {
            badge = document.createElement('div');
            badge.id = 'puretube-sponsor-badge';
            document.body.appendChild(badge);
        }

        lastSkippedSegment = {
            from: fromTime,
            to: seg.end,
            segment: seg
        };

        const catTitle = SB_TITLES[seg.category] || 'Sponsor';
        badge.innerHTML = `
            <span class="puretube-badge-icon">
                <svg width="15" height="15" viewBox="0 0 24 24" fill="currentColor">
                    <path d="M7 2v11h3v9l7-12h-4l4-8z"/>
                </svg>
            </span>
            <span class="puretube-badge-text">${catTitle} atlandı (SponsorBlock)</span>
            <span class="puretube-badge-undo">Geri Al</span>
        `;

        const undoBtn = badge.querySelector('.puretube-badge-undo');
        if (undoBtn) {
            undoBtn.onclick = (e) => {
                e.stopPropagation();
                const video = document.querySelector('video');
                if (video && lastSkippedSegment) {
                    video.currentTime = Math.max(0, lastSkippedSegment.from - 0.5);
                    showToast('Geri alındı');
                }
                badge.classList.remove('puretube-badge-visible');
            };
        }

        badge.classList.add('puretube-badge-visible');
        clearTimeout(badgeTimer);
        badgeTimer = setTimeout(() => {
            badge.classList.remove('puretube-badge-visible');
        }, 3200);
    }

    function checkSponsorBlock(video) {
        if (!sponsorBlockEnabled || sponsorSegments.length === 0 || !video) return;
        const cur = video.currentTime;
        for (let i = 0; i < sponsorSegments.length; i++) {
            const seg = sponsorSegments[i];
            if (cur >= seg.start && cur < (seg.end - 0.25)) {
                const from = cur;
                video.currentTime = seg.end;
                showSponsorBadge(seg, from);
                break;
            }
        }
    }

    // --- 6. RETURN YOUTUBE DISLIKE (RYD) DOM INJECTOR ---
    async function fetchRydData(videoId) {
        if (!videoId || rydFetchInProgress) return;
        if (lastRydVideoId === videoId && currentRydVotes) {
            injectRydDom(currentRydVotes);
            return;
        }

        rydFetchInProgress = true;
        lastRydVideoId = videoId;

        try {
            // 1. Try Flutter bridge first
            if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
                try {
                    const bridgeRes = await window.flutter_inappwebview.callHandler('fetchRydVotes', { videoId: videoId });
                    if (bridgeRes && typeof bridgeRes === 'object' && bridgeRes.likes !== undefined) {
                        currentRydVotes = bridgeRes;
                        injectRydDom(currentRydVotes);
                        rydFetchInProgress = false;
                        return;
                    }
                } catch(_) {}
            }

            // 2. Direct RYD API fallback
            const resp = await fetch(`https://returnyoutubedislikeapi.com/votes?videoId=${videoId}`);
            if (resp.status === 200) {
                const data = await resp.json();
                const likes = Number(data.likes) || 0;
                const dislikes = Number(data.dislikes) || 0;
                const total = likes + dislikes;
                const likePct = total > 0 ? (likes / total) * 100 : (likes > 0 ? 100 : 0);
                currentRydVotes = {
                    videoId: videoId,
                    likes: likes,
                    dislikes: dislikes,
                    rating: Number(data.rating) || 0,
                    viewCount: Number(data.viewCount) || 0,
                    formattedLikes: formatMetric(likes),
                    formattedDislikes: formatMetric(dislikes),
                    likePercentage: likePct
                };
                injectRydDom(currentRydVotes);
            }
        } catch(e) {
            console.warn('[PureTube RYD] Fetch error:', e);
        } finally {
            rydFetchInProgress = false;
        }
    }

    function findDislikeButton() {
        const selectors = [
            'dislike-button-view-model button',
            'like-button-view-model + dislike-button-view-model button',
            'ytm-segmented-like-dislike-button-renderer ytm-toggle-button-renderer:nth-child(2) button',
            'ytm-segmented-like-dislike-button-renderer button[aria-label*="dislike" i]',
            'ytm-segmented-like-dislike-button-renderer button[aria-label*="beğenme" i]',
            'button.segmented-buttons-wrapper__button:nth-child(2)',
            '#dislike-button',
            'button[aria-label*="dislike" i]',
            'button[aria-label*="beğenme" i]',
            '.slim-video-action-bar-actions ytm-toggle-button-renderer:nth-child(2) button',
            '.slim-video-action-bar-actions button:nth-child(2)'
        ];

        for (const sel of selectors) {
            const btn = document.querySelector(sel);
            if (btn) return btn;
        }
        return null;
    }

    function findActionBarContainer() {
        return document.querySelector(
            'ytm-segmented-like-dislike-button-renderer, ' +
            'segmented-like-dislike-button-view-model, ' +
            '.slim-video-action-bar-actions, ' +
            'ytm-slim-video-action-bar-renderer, ' +
            '#actions.ytd-watch-metadata, ' +
            '#top-level-buttons-computed, ' +
            '.ytm-slim-video-action-bar'
        );
    }

    function injectRydDom(votes) {
        if (!votes) return;

        // 1. Insert/update dislike count on dislike button in YouTube mobile DOM
        const dislikeBtn = findDislikeButton();
        if (dislikeBtn) {
            let countSpan = dislikeBtn.querySelector('.puretube-ryd-count');
            if (!countSpan) {
                countSpan = document.createElement('span');
                countSpan.className = 'puretube-ryd-count';
                const textTarget = dislikeBtn.querySelector('.cbox, .yt-spec-button-shape-next__button-text-content, .button-renderer-text') || dislikeBtn;
                textTarget.appendChild(countSpan);
            }
            countSpan.textContent = votes.formattedDislikes || formatMetric(votes.dislikes);
            dislikeBtn.setAttribute('title', `${votes.dislikes.toLocaleString()} dislike`);
        }

        // 2. Add clean thin like/dislike ratio bar beneath the action bar
        const actionBar = findActionBarContainer();
        if (actionBar) {
            let rydBar = document.getElementById('puretube-ryd-bar');
            if (!rydBar) {
                rydBar = document.createElement('div');
                rydBar.id = 'puretube-ryd-bar';
                rydBar.innerHTML = `
                    <div class="puretube-ryd-likes"></div>
                    <div class="puretube-ryd-dislikes"></div>
                `;
                if (actionBar.parentNode) {
                    actionBar.parentNode.insertBefore(rydBar, actionBar.nextSibling);
                }
            }

            const likePct = Math.max(0, Math.min(100, votes.likePercentage || 0));
            const dislikePct = 100 - likePct;
            const likesEl = rydBar.querySelector('.puretube-ryd-likes');
            const dislikesEl = rydBar.querySelector('.puretube-ryd-dislikes');
            if (likesEl) likesEl.style.width = likePct + '%';
            if (dislikesEl) dislikesEl.style.width = dislikePct + '%';
            rydBar.setAttribute('title', `${votes.formattedLikes || votes.likes} beğeni / ${votes.formattedDislikes || votes.dislikes} beğenmeme (%${likePct.toFixed(1)})`);
        }
    }

    // --- 7. INSTANT 0-MS VIDEO AD CLEANER & ANTI-SSAI HARDENING ---
    function dismissAntiAdblockModals() {
        const modals = document.querySelectorAll(
            'ytd-enforcement-message-view-model, ' +
            'yt-playability-error-supported-renderers, ' +
            '.yt-playability-error-supported-renderers, ' +
            'tp-yt-paper-dialog:has(#feedback), ' +
            'tp-yt-iron-overlay-backdrop, ' +
            'ytd-popup-container:has(ytd-enforcement-message-view-model), ' +
            '.opened[modal]'
        );
        if (modals.length > 0) {
            modals.forEach(el => {
                try { el.remove(); } catch(_) {}
            });
            const video = document.querySelector('video');
            if (video && video.paused && !isUserPaused && video.currentTime > 0) {
                try { video.play(); } catch(_) {}
            }
        }
    }

    function isAdPlayingNow() {
        const player = document.querySelector('.html5-video-player') || document.getElementById('movie_player');
        if (player && (player.classList.contains('ad-showing') || player.classList.contains('ad-interrupting'))) {
            return true;
        }
        if (document.querySelector('.ytp-ad-player-overlay, .ytp-ad-preview-container, .ytp-ad-text, .ytm-ad-overlay, .ad-showing, .ad-interrupting, .video-ads.ytp-ad-module:not([style*="display: none"])')) {
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

        dismissAntiAdblockModals();

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

            // 3. Fast-forward the SSAI ad stream directly to the end
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
            renderSeekbarSegments();
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
            renderSeekbarSegments();
            if (currentRydVotes) injectRydDom(currentRydVotes);
        }
    }, true);

    document.addEventListener('loadedmetadata', (e) => {
        if (e.target && e.target.tagName === 'VIDEO') {
            renderSeekbarSegments();
        }
    }, true);

    // --- 8. REMOVE PROMOTIONS & YT MUSIC OPEN-APP BUTTONS ---
    function killYtMusicOpenAppButton() {
        const nav = document.querySelector('ytmusic-nav-bar');
        if (!nav) return;

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
        dismissAntiAdblockModals();

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

        if (currentRydVotes) {
            injectRydDom(currentRydVotes);
        }
    }

    // --- 9. MINIMAL FLOATING TOAST ---
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

    // --- 10. URL MONITORING & VIDEO LIFECYCLE ---
    function checkUrlChange() {
        const newId = extractVideoId(window.location.href);
        if (newId && newId !== currentVideoId) {
            currentVideoId = newId;
            notifyFlutter('onVideoChanged', { videoId: newId, url: window.location.href });
            fetchSponsorBlockSegments(newId);
            fetchRydData(newId);
        }
    }

    // --- 11. JAVASCRIPT BRIDGE & CONTROL ---
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

            try {
                const player = document.getElementById('movie_player') || document.querySelector('.html5-video-player');
                if (player && typeof player.nextVideo === 'function') {
                    console.log('[PureTube] Using movie_player.nextVideo()');
                    player.nextVideo();
                }
            } catch(e) {
                console.warn('[PureTube] player.nextVideo error:', e);
            }

            if (typeof _mediaSessionHandlers['nexttrack'] === 'function') {
                try {
                    console.log('[PureTube] Using mediaSessionHandler nexttrack');
                    _mediaSessionHandlers['nexttrack']({ action: 'nexttrack' });
                } catch(e) {
                    console.warn('[PureTube] mediaSession nexttrack error:', e);
                }
            }

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
                    clicked = clickElement(btn);
                    break;
                }
            }

            if (!clicked) {
                const upNext = document.querySelector(
                    'ytm-compact-video-renderer a.compact-media-item-image, ' +
                    'ytm-compact-video-renderer a.compact-media-item-metadata-content, ' +
                    'ytm-single-column-watch-next-results-renderer a[href*="watch?v="], ' +
                    'ytm-item-section-renderer ytm-video-with-context-renderer a, ' +
                    'a.compact-media-item-headline'
                );
                if (upNext) {
                    clicked = clickElement(upNext);
                }
            }

            const video = document.querySelector('video');
            if (video && isFinite(video.duration) && video.duration > 0) {
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

            try {
                const player = document.getElementById('movie_player') || document.querySelector('.html5-video-player');
                if (player && typeof player.previousVideo === 'function') {
                    player.previousVideo();
                }
            } catch(e) {
                console.warn('[PureTube] player.previousVideo error:', e);
            }

            if (typeof _mediaSessionHandlers['previoustrack'] === 'function') {
                try {
                    _mediaSessionHandlers['previoustrack']({ action: 'previoustrack' });
                } catch(e) {
                    console.warn('[PureTube] mediaSession previoustrack error:', e);
                }
            }

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
            if (enabled && currentVideoId) {
                fetchSponsorBlockSegments(currentVideoId);
            } else {
                removeSeekbarSegments();
            }
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

    // --- 12. MEDIA METADATA OBSERVER FOR SYSTEM NOTIFICATION ---
    let lastSentMedia = { title: '', artist: '', artwork: '', isPlaying: false, position: -1, duration: -1 };

    function syncMediaMetadata() {
        const video = document.querySelector('video');
        if (!video) return;

        let title = '';
        let artist = '';
        let artwork = '';

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

    // --- 13. FULLSCREEN & ORIENTATION CONTROLLER ---
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

    // --- 14. HIGH-PERFORMANCE DOM OBSERVER & LIFECYCLE HEARTBEATS ---
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
