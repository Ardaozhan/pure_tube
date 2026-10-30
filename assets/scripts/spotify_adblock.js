// PureTube - Spotify Web AdBlocker, Mobile Responsive & Background Audio Engine
(function() {
    'use strict';

    if (window.__spotifyPureInjected) return;
    window.__spotifyPureInjected = true;

    // --- 1. NAVIGATOR SPOOFING (BYPASS UNSUPPORTED BROWSER) ---
    try {
        const chromeUa = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36';
        Object.defineProperty(navigator, 'userAgent', {
            get: function() { return chromeUa; },
            configurable: true
        });
        Object.defineProperty(navigator, 'appVersion', {
            get: function() { return '5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36'; },
            configurable: true
        });
        Object.defineProperty(navigator, 'platform', {
            get: function() { return 'Win32'; },
            configurable: true
        });
        Object.defineProperty(navigator, 'vendor', {
            get: function() { return 'Google Inc.'; },
            configurable: true
        });
    } catch(e) {}

    // --- 2. BACKGROUND PLAYBACK TRICK ---
    try {
        Object.defineProperty(document, 'hidden', {
            get: function() { return false; },
            configurable: true
        });
        Object.defineProperty(document, 'visibilityState', {
            get: function() { return 'visible'; },
            configurable: true
        });
        document.addEventListener('visibilitychange', function(e) {
            e.stopImmediatePropagation();
        }, true);
    } catch(e) {}

    // --- 3. DYNAMIC MOBILE VIEWPORT & SCALING ---
    function applyMobileScaling() {
        let meta = document.querySelector('meta[name="viewport"]');
        if (!meta) {
            meta = document.createElement('meta');
            meta.name = 'viewport';
            document.head.appendChild(meta);
        }
        meta.content = 'width=device-width, initial-scale=1.0, maximum-scale=2.0';
    }

    applyMobileScaling();
    document.addEventListener('DOMContentLoaded', applyMobileScaling);

    // --- 4. AD DETECTION & AUTOMATIC SKIP / MUTE ---
    function handleSpotifyAds() {
        const adLink = document.querySelector('a[href*="/ad/"], a[href*="spotify:ad:"]');
        const isAdBanner = document.querySelector('[data-testid="ad-header"]') || adLink;

        const audio = document.querySelector('audio');

        if (isAdBanner && audio) {
            audio.muted = true;
            const nextBtn = document.querySelector('[data-testid="control-button-skip-forward"]');
            if (nextBtn) {
                nextBtn.click();
            }
        } else if (audio && audio.muted) {
            audio.muted = false;
        }

        const closeButtons = document.querySelectorAll(
            'button[aria-label="Kapat"], button[aria-label="Close"], [data-testid="upgrade-button-header"]'
        );
        closeButtons.forEach(btn => {
            if (btn && btn.closest && btn.closest('[role="dialog"]')) {
                btn.click();
            }
        });
    }

    // --- 5. CLEAN PROMOTIONS & APP UPSELLS ---
    function cleanSpotifyUpsells() {
        const adElements = [
            '[data-testid="ad-header"]',
            '[data-testid="upgrade-button"]',
            '[data-testid="billboard-ad-container"]',
            '.sponsor-container',
            '[aria-label*="Premium"]'
        ];

        adElements.forEach(sel => {
            const elements = document.querySelectorAll(sel);
            elements.forEach(el => {
                if (el.tagName === 'BUTTON' || el.tagName === 'DIV') {
                    el.style.display = 'none';
                }
            });
        });
    }

    setInterval(handleSpotifyAds, 500);
    setInterval(cleanSpotifyUpsells, 1500);

    console.log('[PureTube] Spotify Chrome Engine initialized.');
})();
