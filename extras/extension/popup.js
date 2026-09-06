/**
 * VirusDownloader Browser Extension - Popup Script
 */

document.addEventListener('DOMContentLoaded', async () => {
  // Elements
  const statusDot = document.getElementById('statusDot');
  const statusText = document.getElementById('statusText');
  const refreshBtn = document.getElementById('refreshBtn');
  const optionsBtn = document.getElementById('optionsBtn');
  const tabMediaBtn = document.getElementById('tabMediaBtn');
  const tabManualBtn = document.getElementById('tabManualBtn');
  const mediaView = document.getElementById('mediaView');
  const manualView = document.getElementById('manualView');
  const mediaList = document.getElementById('mediaList');
  const emptyMediaState = document.getElementById('emptyMediaState');
  const mediaCountBadge = document.getElementById('mediaCountBadge');
  const interceptToggle = document.getElementById('interceptToggle');

  // Manual Form Elements
  const manualForm = document.getElementById('manualForm');
  const manualUrl = document.getElementById('manualUrl');
  const manualFileName = document.getElementById('manualFileName');
  const manualReferer = document.getElementById('manualReferer');
  const manualCustomHeaders = document.getElementById('manualCustomHeaders');
  const manualSendBtn = document.getElementById('manualSendBtn');

  let currentTabId = null;
  let isAppConnected = false;

  // 1. Get Current Tab
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  if (tab) {
    currentTabId = tab.id;
    if (tab.url && !tab.url.startsWith('chrome')) {
      manualReferer.value = tab.url;
    }
  }

  // 2. Tab Navigation
  tabMediaBtn.addEventListener('click', () => {
    tabMediaBtn.classList.add('active');
    tabManualBtn.classList.remove('active');
    mediaView.classList.remove('hidden');
    manualView.classList.add('hidden');
  });

  tabManualBtn.addEventListener('click', () => {
    tabManualBtn.classList.add('active');
    tabMediaBtn.classList.remove('active');
    manualView.classList.remove('hidden');
    mediaView.classList.add('hidden');
  });

  // 3. Open Options
  optionsBtn.addEventListener('click', () => {
    chrome.runtime.openOptionsPage();
  });

  // 4. Refresh Button
  refreshBtn.addEventListener('click', () => {
    checkAppStatus();
    loadTabMedia();
  });

  // 5. App Status Check
  async function checkAppStatus() {
    statusDot.className = 'dot';
    statusText.innerText = 'Checking...';

    chrome.runtime.sendMessage({ type: 'CHECK_APP_STATUS' }, (res) => {
      if (res && res.connected) {
        isAppConnected = true;
        statusDot.className = 'dot connected';
        statusText.innerText = 'VirusDownloader Ready';
      } else {
        isAppConnected = false;
        statusDot.className = 'dot error';
        statusText.innerText = 'App Offline (Launch VirusDownloader)';
      }
    });
  }

  // 6. Format Helpers
  function formatBytes(bytes) {
    if (!bytes || bytes <= 0) return 'Stream / Dynamic';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    let i = 0;
    let b = bytes;
    while (b >= 1024 && i < units.length - 1) {
      b /= 1024;
      i++;
    }
    return `${b.toFixed(1)} ${units[i]}`;
  }

  function getFormatBadgeClass(category, url) {
    const u = url.toLowerCase();
    if (u.includes('.m3u8')) return { text: 'M3U8 HLS', cls: 'format-hls' };
    if (u.includes('.mpd')) return { text: 'DASH', cls: 'format-dash' };
    if (u.includes('.webm')) return { text: 'WEBM', cls: 'format-webm' };
    if (category === 'audio' || /\.(mp3|aac|m4a|ogg|wav)/i.test(u)) return { text: 'AUDIO', cls: 'format-audio' };
    if (u.includes('.mp4')) return { text: 'MP4', cls: 'format-mp4' };
    return { text: 'MEDIA', cls: 'format-other' };
  }

  // 7. Load Tab Media
  function loadTabMedia() {
    if (!currentTabId) return;

    chrome.runtime.sendMessage({ type: 'GET_TAB_MEDIA', tabId: currentTabId }, (res) => {
      const media = (res && res.media) || [];
      mediaCountBadge.innerText = `${media.length}`;

      if (media.length === 0) {
        emptyMediaState.style.display = 'flex';
        mediaList.innerHTML = '';
        return;
      }

      emptyMediaState.style.display = 'none';
      mediaList.innerHTML = '';

      // Sort so master streams (.m3u8 / .mpd) and complete videos appear first
      media.sort((a, b) => {
        const aMaster = (a.url || '').includes('.m3u8') || (a.url || '').includes('.mpd');
        const bMaster = (b.url || '').includes('.m3u8') || (b.url || '').includes('.mpd');
        if (aMaster && !bMaster) return -1;
        if (!aMaster && bMaster) return 1;
        return 0;
      });

      media.forEach((item) => {
        const card = document.createElement('div');
        card.className = 'media-card';

        const badgeInfo = getFormatBadgeClass(item.category, item.url);
        const displayName = item.fileName || item.tabTitle || 'Video Stream';

        card.innerHTML = `
          <div class="media-header">
            <div class="media-title" title="${displayName}">${escapeHtml(displayName)}</div>
            <span class="format-pill ${badgeInfo.cls}">${badgeInfo.text}</span>
          </div>
          <div class="media-meta">
            <span>Size: ${formatBytes(item.sizeBytes)}</span>
            <span>•</span>
            <span title="${item.url}">${truncateUrl(item.url)}</span>
          </div>
          <div class="media-actions">
            <button class="btn-send" data-action="send">
              <svg viewBox="0 0 24 24" width="13" height="13" fill="currentColor">
                <path d="M19 9h-4V3H9v6H5l7 7 7-7zM5 18v2h14v-2H5z"/>
              </svg>
              <span>Download</span>
            </button>
            <button class="btn-icon" data-action="browser" title="Download via Browser">
              <svg viewBox="0 0 24 24" width="13" height="13" fill="currentColor">
                <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-1 17.93c-3.95-.49-7-3.85-7-7.93 0-.62.08-1.21.21-1.79L9 15v1c0 1.1.9 2 2 2v1.93zm6.9-2.54c-.26-.81-1-1.39-1.9-1.39h-1v-3c0-.55-.45-1-1-1H8v-2h2c.55 0 1-.45 1-1V7h2c1.1 0 2-.9 2-2v-.41c2.93 1.19 5 4.06 5 7.41 0 2.08-.8 3.97-2.1 5.39z"/>
              </svg>
            </button>
            <button class="btn-icon" data-action="copy-curl" title="Copy as cURL Command">
              cURL
            </button>
            <button class="btn-icon" data-action="copy-url" title="Copy URL with Referer">
              <svg viewBox="0 0 24 24" width="13" height="13" fill="currentColor">
                <path d="M16 1H4c-1.1 0-2 .9-2 2v14h2V3h12V1zm3 4H8c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h11c1.1 0 2-.9 2-2V7c0-1.1-.9-2-2-2zm0 16H8V7h11v14z"/>
              </svg>
            </button>
          </div>
        `;

        // Button handlers
        const sendBtn = card.querySelector('[data-action="send"]');
        sendBtn.addEventListener('click', () => {
          sendBtn.disabled = true;
          const origText = sendBtn.querySelector('span').innerText;
          sendBtn.querySelector('span').innerText = 'Sending...';

          const headers = { ...(item.headers || {}) };
          delete headers['range'];
          delete headers['Range'];

          chrome.runtime.sendMessage({
            type: 'SEND_TO_APP',
            payload: {
              url: item.url,
              fileName: item.fileName,
              headers: headers,
              category: item.category || 'videos'
            }
          }, (res) => {
            sendBtn.disabled = false;
            if (res && res.success) {
              sendBtn.querySelector('span').innerText = '✓ Queued!';
              setTimeout(() => {
                sendBtn.querySelector('span').innerText = origText;
              }, 2500);
            } else {
              alert((res && res.error) || 'Failed to send to VirusDownloader. Make sure the app is running.');
              sendBtn.querySelector('span').innerText = origText;
            }
          });
        });

        const browserBtn = card.querySelector('[data-action="browser"]');
        browserBtn.addEventListener('click', () => {
          chrome.runtime.sendMessage({
            type: 'DOWNLOAD_IN_BROWSER',
            url: item.url,
            fileName: item.fileName
          });
        });

        const curlBtn = card.querySelector('[data-action="copy-curl"]');
        curlBtn.addEventListener('click', () => {
          let curlCmd = `curl -L "${item.url}"`;
          if (item.headers) {
            for (const [k, v] of Object.entries(item.headers)) {
              curlCmd += ` -H "${k}: ${v.replace(/"/g, '\\"')}"`;
            }
          }
          curlCmd += ` -o "${item.fileName}"`;
          navigator.clipboard.writeText(curlCmd).then(() => {
            curlBtn.innerText = 'Copied!';
            setTimeout(() => { curlBtn.innerText = 'cURL'; }, 2000);
          });
        });

        const copyUrlBtn = card.querySelector('[data-action="copy-url"]');
        copyUrlBtn.addEventListener('click', () => {
          const text = `URL: ${item.url}\nReferer: ${(item.headers && item.headers['Referer']) || 'none'}`;
          navigator.clipboard.writeText(text).then(() => {
            copyUrlBtn.style.color = '#10b981';
            setTimeout(() => { copyUrlBtn.style.color = ''; }, 2000);
          });
        });

        mediaList.appendChild(card);
      });
    });
  }

  // 8. Intercept Toggle
  chrome.runtime.sendMessage({ type: 'GET_CONFIG' }, (cfg) => {
    if (cfg) {
      interceptToggle.checked = cfg.interceptDownloads !== false;
    }
  });

  interceptToggle.addEventListener('change', () => {
    chrome.runtime.sendMessage({
      type: 'SAVE_CONFIG',
      config: { interceptDownloads: interceptToggle.checked }
    });
  });

  // 9. Manual URL Form
  manualForm.addEventListener('submit', (e) => {
    e.preventDefault();
    const url = manualUrl.value.trim();
    if (!url) return;

    let headers = {};
    if (manualReferer.value.trim()) {
      headers['Referer'] = manualReferer.value.trim();
    }
    if (manualCustomHeaders.value.trim()) {
      try {
        const parsed = JSON.parse(manualCustomHeaders.value.trim());
        headers = { ...headers, ...parsed };
      } catch (_) {
        // Parse line by line "Key: Value"
        const lines = manualCustomHeaders.value.trim().split('\n');
        for (const line of lines) {
          const idx = line.indexOf(':');
          if (idx > 0) {
            headers[line.substring(0, idx).trim()] = line.substring(idx + 1).trim();
          }
        }
      }
    }

    manualSendBtn.disabled = true;
    manualSendBtn.innerText = 'Sending to VirusDownloader...';

    chrome.runtime.sendMessage({
      type: 'SEND_TO_APP',
      payload: {
        url: url,
        fileName: manualFileName.value.trim() || 'video.mp4',
        headers: headers,
        category: 'videos'
      }
    }, (res) => {
      manualSendBtn.disabled = false;
      manualSendBtn.innerText = 'Send to VirusDownloader';
      if (res && res.success) {
        alert('Download queued successfully in VirusDownloader!');
        manualUrl.value = '';
        manualFileName.value = '';
      } else {
        alert((res && res.error) || 'Failed to send to VirusDownloader.');
      }
    });
  });

  function escapeHtml(str) {
    return (str || '').replace(/[&<>"']/g, (m) => {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#039;' }[m];
    });
  }

  function truncateUrl(url) {
    try {
      const u = new URL(url);
      return `${u.hostname}.../${u.pathname.split('/').pop() || ''}`.substring(0, 32);
    } catch (_) {
      return url.substring(0, 32);
    }
  }

  // Initial loads
  checkAppStatus();
  loadTabMedia();
});

