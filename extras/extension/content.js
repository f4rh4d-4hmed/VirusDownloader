/**
 * VirusDownloader Browser Extension - Content Script
 * Detects HTML5 video/audio elements and provides an IDM-style floating download badge.
 */

(function () {
  'use strict';

  let config = { showFloatingButton: true };
  const trackedVideos = new Set();

  // Fetch initial config
  chrome.runtime.sendMessage({ type: 'GET_CONFIG' }, (res) => {
    if (res) config = res;
    scanDomForMedia();
  });

  // Listen for config changes
  chrome.storage.onChanged.addListener((changes) => {
    if (changes.virusDownloaderConfig) {
      config = changes.virusDownloaderConfig.newValue;
    }
  });

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

    const fileName = getCleanFileName(url, document.title);
    const item = {
      id: `dom_${url.substring(0, 80)}_${Date.now()}`,
      url: url,
      fileName: fileName,
      tabTitle: document.title || 'Web Video',
      tabUrl: window.location.href,
      category: 'video',
      mimeType: 'video/mp4',
      sizeBytes: 0,
      headers: {
        'Referer': window.location.href,
        'User-Agent': navigator.userAgent
      }
    };

    chrome.runtime.sendMessage({
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

      let targetUrl = video.currentSrc || video.src || '';

      badge.classList.add('vd-btn-loading');
      badge.querySelector('span').innerText = 'Finding video stream...';

      function doSend(url, fileName, headers, category) {
        badge.querySelector('span').innerText = 'Sending to VirusDownloader...';
        chrome.runtime.sendMessage({
          type: 'SEND_TO_APP',
          payload: {
            url: url,
            fileName: fileName,
            headers: headers || {
              'Referer': window.location.href,
              'User-Agent': navigator.userAgent
            },
            category: category || 'video'
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
            setTimeout(() => {
              badge.classList.remove('vd-btn-error');
              badge.querySelector('span').innerText = 'Download with VirusDownloader';
            }, 4500);
          }
        });
      }

      // If video is dynamic blob or empty, fetch sniffed media stream from background
      if (!targetUrl || targetUrl.startsWith('blob:') || targetUrl.startsWith('data:')) {
        chrome.runtime.sendMessage({ type: 'GET_TAB_MEDIA' }, (res) => {
          const media = (res && res.media) || [];
          if (media.length > 0) {
            const best = media.find(m => m.category === 'video' || m.category === 'hls_stream') || media[0];
            doSend(best.url, best.fileName, best.headers, best.category);
          } else {
            badge.classList.remove('vd-btn-loading');
            badge.classList.add('vd-btn-error');
            badge.querySelector('span').innerText = 'Play video 2s to capture stream, then click';
            setTimeout(() => {
              badge.classList.remove('vd-btn-error');
              badge.querySelector('span').innerText = 'Download with VirusDownloader';
            }, 4000);
          }
        });
        return;
      }

      // Normalize protocol-relative URL
      if (targetUrl.startsWith('//')) {
        targetUrl = window.location.protocol + targetUrl;
      }

      const fileName = getCleanFileName(targetUrl, document.title);
      doSend(targetUrl, fileName, {
        'Referer': window.location.href,
        'User-Agent': navigator.userAgent
      }, 'video');
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
    scanDomForMedia();
  });

  if (document.body) {
    observer.observe(document.body, { childList: true, subtree: true });
    scanDomForMedia();
  } else {
    document.addEventListener('DOMContentLoaded', () => {
      observer.observe(document.body, { childList: true, subtree: true });
      scanDomForMedia();
    });
  }
})();

