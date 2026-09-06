/**
 * VirusDownloader Browser Extension - Content Script
 * Detects HTML5 video/audio elements and provides an IDM-style floating download badge.
 */

(function () {
  'use strict';

  let config = { showFloatingButton: true };
  const trackedVideos = new Set();
  let observer = null;

  function isExtensionValid() {
    try {
      return Boolean(typeof chrome !== 'undefined' && chrome.runtime && chrome.runtime.id);
    } catch (_) {
      return false;
    }
  }

  function safeSendMessage(message, callback) {
    if (!isExtensionValid()) {
      if (observer) {
        observer.disconnect();
        observer = null;
      }
      if (callback) {
        callback({
          success: false,
          error: 'Extension was reloaded. Please refresh the page (F5).'
        });
      }
      return;
    }

    try {
      chrome.runtime.sendMessage(message, (response) => {
        const lastError = chrome.runtime?.lastError;
        if (lastError) {
          const msg = lastError.message || '';
          if (msg.includes('context invalidated') || msg.includes('Extension context')) {
            if (observer) {
              observer.disconnect();
              observer = null;
            }
            if (callback) callback({ success: false, error: 'Extension was reloaded. Please refresh the page (F5).' });
          } else {
            if (callback) callback({ success: false, error: msg });
          }
          return;
        }
        if (callback) callback(response);
      });
    } catch (err) {
      const msg = (err && err.message) || String(err);
      if (msg.includes('context invalidated') || msg.includes('Extension context')) {
        if (observer) {
          observer.disconnect();
          observer = null;
        }
        if (callback) callback({ success: false, error: 'Extension was reloaded. Please refresh the page (F5).' });
      } else {
        if (callback) callback({ success: false, error: msg });
      }
    }
  }

  // Fetch initial config
  chrome.runtime.sendMessage({ type: 'GET_CONFIG' }, (res) => {
    if (res) config = res;
  safeSendMessage({ type: 'GET_CONFIG' }, (res) => {
    if (res && res.showFloatingButton !== undefined) config = res;
    scanDomForMedia();
  });

  // Listen for config changes
  chrome.storage.onChanged.addListener((changes) => {
    if (changes.virusDownloaderConfig) {
      config = changes.virusDownloaderConfig.newValue;
  // Listen for config changes safely
  try {
    if (chrome?.storage?.onChanged) {
      chrome.storage.onChanged.addListener((changes) => {
        if (changes?.virusDownloaderConfig) {
          config = changes.virusDownloaderConfig.newValue;
        }
      });
    }
  });
  } catch (_) {}

  function getCleanFileName(url, defaultBase) {
    try {
      const u = new URL(url);
      const name = u.pathname.split('/').filter(Boolean).pop();
      if (name && name.includes('.')) {
        return decodeURIComponent(name.split('?')[0]);
      }
    } catch (_) {}
    const safeTitle = (document.title || defaultBase || 'video')
      .replace(/[\\/:*?"<>|]/g, '_')
      .trim();
    return `${safeTitle.substring(0, 50)}.mp4`;
  }

  function reportMedia(url, videoEl) {
    if (!url || url.startsWith('blob:') || url.startsWith('data:')) return;
    if (!isExtensionValid()) return;

    let absoluteUrl = url;
    try {
      absoluteUrl = new URL(url, window.location.href).href;
    } catch (_) {}

    const fileName = getCleanFileName(absoluteUrl, document.title);
    const item = {
      id: `dom_${absoluteUrl.substring(0, 80)}_${Date.now()}`,
      url: absoluteUrl,
      fileName: fileName,
      tabTitle: document.title || 'Web Video',
      tabUrl: window.location.href,
      category: 'videos',
      mimeType: 'video/mp4',
      sizeBytes: 0,
      headers: {
        'Referer': window.location.href,
        'User-Agent': navigator.userAgent
      }
    };

    chrome.runtime.sendMessage({
    safeSendMessage({
      type: 'DOM_MEDIA_FOUND',
      items: [item]
    });
  }

  // Attach hover badge to video player
  function attachFloatingButton(video) {
    if (video.dataset.vdAttached) return;
    video.dataset.vdAttached = 'true';

    // Container for the floating badge
    const badge = document.createElement('div');
    badge.className = 'vd-floating-download-btn';
    badge.innerHTML = `
      <svg viewBox="0 0 24 24" width="14" height="14" fill="currentColor">
        <path d="M19 9h-4V3H9v6H5l7 7 7-7zM5 18v2h14v-2H5z"/>
      </svg>
      <span>Download with VirusDownloader</span>
    `;

    // Position badge over video
    function updatePosition() {
      const rect = video.getBoundingClientRect();
      if (rect.width < 120 || rect.height < 80) {
        badge.style.display = 'none';
        return;
      }
      badge.style.display = 'flex';
      badge.style.top = `${Math.max(10, rect.top + window.scrollY + 10)}px`;
      badge.style.left = `${Math.max(10, rect.right + window.scrollX - 240)}px`;
    }

    badge.addEventListener('click', async (e) => {
      e.stopPropagation();
      e.preventDefault();

      // Resolve video target URL: check currentSrc, src, source child tags, and data attributes
      let targetUrl = '';
      if (video.currentSrc && !video.currentSrc.startsWith('blob:') && !video.currentSrc.startsWith('data:')) {
        targetUrl = video.currentSrc;
      } else if (video.src && !video.src.startsWith('blob:') && !video.src.startsWith('data:')) {
        targetUrl = video.src;
      } else {
        const sources = Array.from(video.querySelectorAll('source'));
        for (const s of sources) {
          const sSrc = s.src || s.getAttribute('src');
          if (sSrc && !sSrc.startsWith('blob:') && !sSrc.startsWith('data:')) {
            targetUrl = sSrc;
            break;
          }
        }
        if (!targetUrl) {
          const dataSrc = video.dataset.src || video.getAttribute('data-src') || video.getAttribute('data-url') || video.getAttribute('data-video');
          if (dataSrc && !dataSrc.startsWith('blob:') && !dataSrc.startsWith('data:')) {
            targetUrl = dataSrc;
          }
        }
      }

      if (targetUrl) {
        try {
          targetUrl = new URL(targetUrl, window.location.href).href;
        } catch (_) {}
      }

      badge.classList.add('vd-btn-loading');
      badge.querySelector('span').innerText = 'Finding video stream...';

      function doSend(url, fileName, headers, category) {
        badge.querySelector('span').innerText = 'Sending to VirusDownloader...';
        chrome.runtime.sendMessage({
        safeSendMessage({
          type: 'SEND_TO_APP',
          payload: {
            url: url,
            fileName: fileName,
            headers: headers || {
              'Referer': window.location.href,
              'User-Agent': navigator.userAgent
            },
            category: category || 'videos'
          }
        }, (response) => {
          badge.classList.remove('vd-btn-loading');
          if (response && response.success) {
            badge.classList.add('vd-btn-success');
            badge.querySelector('span').innerText = '✓ Sent to VirusDownloader!';
            setTimeout(() => {
              badge.classList.remove('vd-btn-success');
              badge.querySelector('span').innerText = 'Download with VirusDownloader';
            }, 3000);
          } else {
            badge.classList.add('vd-btn-error');
            badge.querySelector('span').innerText = (response && response.error) || 'Failed to connect';
            const err = (response && response.error) || 'Failed to connect';
            badge.querySelector('span').innerText = err;
            setTimeout(() => {
              badge.classList.remove('vd-btn-error');
              badge.querySelector('span').innerText = 'Download with VirusDownloader';
            }, 4500);
            }, err.includes('refresh') ? 6000 : 4500);
          }
        });
      }

      // If video is dynamic blob or empty, fetch sniffed media stream from background
      if (!targetUrl || targetUrl.startsWith('blob:') || targetUrl.startsWith('data:')) {
        chrome.runtime.sendMessage({ type: 'GET_TAB_MEDIA' }, (res) => {
        safeSendMessage({ type: 'GET_TAB_MEDIA' }, (res) => {
          const media = (res && res.media) || [];
          if (media.length > 0) {
            // Prioritize master manifest (HLS .m3u8, DASH .mpd) or full mp4 over fragments
            const best = media.find(m => m.url.includes('.m3u8') || m.url.includes('.mpd')) ||
                         media.find(m => m.category === 'videos' || m.category === 'video') ||
                         media[0];
            doSend(best.url, best.fileName, best.headers, best.category);
          } else {
            badge.classList.remove('vd-btn-loading');
            badge.classList.add('vd-btn-error');
            badge.querySelector('span').innerText = 'Play video 2s to capture stream, then click';
            const err = (res && res.error) || 'Play video 2s to capture stream, then click';
            badge.querySelector('span').innerText = err;
            setTimeout(() => {
              badge.classList.remove('vd-btn-error');
              badge.querySelector('span').innerText = 'Download with VirusDownloader';
            }, 4000);
          }
        });
        return;
      }

      const fileName = getCleanFileName(targetUrl, document.title);
      doSend(targetUrl, fileName, {
        'Referer': window.location.href,
        'User-Agent': navigator.userAgent
      }, 'videos');
    });

    let hideTimeout;
    function showBadge() {
      if (!config.showFloatingButton) return;
      clearTimeout(hideTimeout);
      updatePosition();
      badge.classList.add('vd-visible');
    }

    function hideBadge() {
      hideTimeout = setTimeout(() => {
        badge.classList.remove('vd-visible');
      }, 400);
    }

    video.addEventListener('mouseenter', showBadge);
    video.addEventListener('mouseleave', hideBadge);
    badge.addEventListener('mouseenter', () => clearTimeout(hideTimeout));
    badge.addEventListener('mouseleave', hideBadge);

    document.body.appendChild(badge);
  }

  // Scan document for video and audio elements
  function scanDomForMedia() {
    if (!isExtensionValid()) {
      if (observer) {
        observer.disconnect();
        observer = null;
      }
      return;
    }

    const videos = document.querySelectorAll('video');
    videos.forEach((video) => {
      if (!trackedVideos.has(video)) {
        trackedVideos.add(video);

        // Check src
        if (video.currentSrc) {
          reportMedia(video.currentSrc, video);
        } else if (video.src) {
          reportMedia(video.src, video);
        }

        video.addEventListener('loadeddata', () => {
          if (video.currentSrc) reportMedia(video.currentSrc, video);
        });

        video.addEventListener('play', () => {
          if (video.currentSrc) reportMedia(video.currentSrc, video);
        });

        if (config.showFloatingButton) {
          attachFloatingButton(video);
        }
      }
    });

    // Scan source tags
    const sources = document.querySelectorAll('video source, audio source');
    sources.forEach((srcEl) => {
      if (srcEl.src) {
        reportMedia(srcEl.src);
      }
    });
  }

  // MutationObserver for SPA navigation and dynamic video injection
  const observer = new MutationObserver(() => {
  observer = new MutationObserver(() => {
    scanDomForMedia();
  });

  if (document.body) {
    observer.observe(document.body, { childList: true, subtree: true });
    scanDomForMedia();
  } else {
    document.addEventListener('DOMContentLoaded', () => {
      observer.observe(document.body, { childList: true, subtree: true });
      if (document.body && observer) {
        observer.observe(document.body, { childList: true, subtree: true });
      }
      scanDomForMedia();
    });
  }
})();

