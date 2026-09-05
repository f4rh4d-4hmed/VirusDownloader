/**
 * VirusDownloader Browser Extension - Background Service Worker
 * Sniffs video/audio requests with full headers (Referer, Cookie, User-Agent),
 * intercepts browser downloads, and connects to the VirusDownloader desktop app.
 */

const DEFAULT_SERVER_URL = 'http://127.0.0.1:9849';

const DEFAULT_CONFIG = {
  serverUrl: DEFAULT_SERVER_URL,
  interceptDownloads: false,
  showFloatingButton: true,
  minVideoSizeBytes: 200 * 1024, // 200 KB
  ignoredDomains: []
};

// Map of tabId -> Array of detected media items
const tabMediaStore = new Map();
// Cache of request headers by URL: url -> { [headerName]: headerValue }
const requestHeadersCache = new Map();
// Keep track of download IDs triggered by extension to avoid interception loops
const selfInitiatedDownloads = new Set();

// Load configuration
async function getConfig() {
  const data = await chrome.storage.local.get('virusDownloaderConfig');
  return { ...DEFAULT_CONFIG, ...(data.virusDownloaderConfig || {}) };
}

async function saveConfig(patch) {
  const current = await getConfig();
  const updated = { ...current, ...patch };
  await chrome.storage.local.set({ virusDownloaderConfig: updated });
  return updated;
}

// Media file extension regex
const MEDIA_EXT_REGEX = /\.(mp4|m3u8|mpd|webm|mkv|flv|ts|mov|avi|m4s|m4a|aac|mp3|ogg|wav|opus)(\?.*)?$/i;

// Parse file name from URL or Content-Disposition
function extractFileName(url, defaultName = 'download.mp4') {
  try {
    const parsed = new URL(url);
    const pathname = parsed.pathname;
    const parts = pathname.split('/').filter(Boolean);
    if (parts.length > 0) {
      const last = decodeURIComponent(parts[parts.length - 1]);
      if (last.includes('.')) {
        return last.split('?')[0];
      }
    }
  } catch (_) {}
  return defaultName;
}

// Determine media category
function getMediaCategory(url, mime = '') {
  const lowerUrl = url.toLowerCase();
  const lowerMime = mime.toLowerCase();
  if (lowerUrl.includes('.m3u8') || lowerMime.includes('mpegurl')) return 'hls_stream';
  if (lowerUrl.includes('.mpd') || lowerMime.includes('dash+xml')) return 'dash_stream';
  if (lowerMime.startsWith('audio/') || /\.(mp3|aac|m4a|ogg|wav|opus)(\?.*)?$/i.test(lowerUrl)) return 'audio';
  return 'video';
}

// 1. Capture Outgoing Request Headers (Referer, Cookie, User-Agent, Origin, Authorization)
chrome.webRequest.onBeforeSendHeaders.addListener(
  (details) => {
    if (!details.url || details.url.startsWith('chrome') || details.url.startsWith('edge')) return;

    const headers = {};
    if (details.requestHeaders) {
      for (const h of details.requestHeaders) {
        const name = h.name.toLowerCase();
        // Capture important headers for deep video retrieval
        if (['referer', 'user-agent', 'cookie', 'origin', 'authorization', 'range', 'sec-fetch-site'].includes(name)) {
          headers[h.name] = h.value;
        }
      }
    }

    // Keep cache bounded
    if (requestHeadersCache.size > 2000) {
      const firstKey = requestHeadersCache.keys().next().value;
      requestHeadersCache.delete(firstKey);
    }
    requestHeadersCache.set(details.url, headers);
  },
  { urls: ['<all_urls>'] },
  ['requestHeaders', 'extraHeaders']
);

// 2. Sniff Media on Response Started (MIME type & extension matching)
chrome.webRequest.onResponseStarted.addListener(
  async (details) => {
    if (!details.url || details.tabId < 0) return;

    let mimeType = '';
    let contentLength = 0;
    if (details.responseHeaders) {
      for (const h of details.responseHeaders) {
        const name = h.name.toLowerCase();
        if (name === 'content-type') {
          mimeType = (h.value || '').toLowerCase();
        } else if (name === 'content-length') {
          contentLength = parseInt(h.value || '0', 10);
        }
      }
    }

    const isMediaResourceType = details.type === 'media';
    const isVideoMime = mimeType.startsWith('video/') ||
      mimeType.includes('application/vnd.apple.mpegurl') ||
      mimeType.includes('application/x-mpegurl') ||
      mimeType.includes('application/dash+xml') ||
      mimeType.includes('video/mp2t');

    const isAudioMime = mimeType.startsWith('audio/');
    const matchesExtension = MEDIA_EXT_REGEX.test(details.url);
    const hasMediaInQuery = /[?&](mime=video|mime=audio|format=m3u8|format=mpd)/i.test(details.url) ||
      details.url.includes('/videoplayback');

    if (!isMediaResourceType && !isVideoMime && !isAudioMime && !matchesExtension && !hasMediaInQuery) {
      return;
    }

    const config = await getConfig();
    if (contentLength > 0 && contentLength < config.minVideoSizeBytes && !matchesExtension && !hasMediaInQuery) {
      // Skip tiny video ads/sounds unless explicitly matching media extension
      return;
    }

    // Fetch tab info
    let tabTitle = 'Web Video';
    let tabUrl = '';
    try {
      const tab = await chrome.tabs.get(details.tabId);
      if (tab) {
        tabTitle = tab.title || tabTitle;
        tabUrl = tab.url || '';
      }
    } catch (_) {}

    // Check ignored domains
    if (tabUrl) {
      try {
        const urlHost = new URL(tabUrl).hostname;
        if (config.ignoredDomains.some(d => urlHost.includes(d))) return;
      } catch (_) {}
    }

    const cachedHeaders = requestHeadersCache.get(details.url) || {};
    if (!cachedHeaders['Referer'] && tabUrl) {
      cachedHeaders['Referer'] = tabUrl;
    }

    const fileName = extractFileName(details.url, `${tabTitle.replace(/[\\/:*?"<>|]/g, '_')}.mp4`);
    const category = getMediaCategory(details.url, mimeType);

    const mediaItem = {
      id: `${details.tabId}_${details.url.substring(0, 100)}_${Date.now()}`,
      url: details.url,
      fileName: fileName,
      tabTitle: tabTitle,
      tabUrl: tabUrl,
      category: category,
      mimeType: mimeType || 'video/mp4',
      sizeBytes: contentLength,
      headers: cachedHeaders,
      timestamp: Date.now()
    };

    addMediaToTab(details.tabId, mediaItem);
  },
  { urls: ['<all_urls>'] },
  ['responseHeaders']
);

// Add detected media to in-memory store
function addMediaToTab(tabId, item) {
  if (!tabMediaStore.has(tabId)) {
    tabMediaStore.set(tabId, []);
  }
  const list = tabMediaStore.get(tabId);
  // Avoid duplicate URLs in same tab
  const exists = list.some(m => m.url === item.url);
  if (!exists) {
    list.unshift(item);
    // Limit list to 30 items per tab
    if (list.length > 30) list.pop();
    updateBadge(tabId, list.length);
  }
}

// Update extension action badge
function updateBadge(tabId, count) {
  if (count > 0) {
    chrome.action.setBadgeText({ text: `${count}`, tabId });
    chrome.action.setBadgeBackgroundColor({ color: '#4F46E5', tabId });
  } else {
    chrome.action.setBadgeText({ text: '', tabId });
  }
}

// Clean up tab store on tab close
chrome.tabs.onRemoved.addListener((tabId) => {
  tabMediaStore.delete(tabId);
});

// Clean up tab store on tab URL navigation
chrome.tabs.onUpdated.addListener((tabId, changeInfo) => {
  if (changeInfo.status === 'loading') {
    tabMediaStore.set(tabId, []);
    updateBadge(tabId, 0);
  }
});

// 3. Intercept Browser Downloads (if enabled)
chrome.downloads.onCreated.addListener(async (downloadItem) => {
  const config = await getConfig();
  if (!config.interceptDownloads) return;

  if (selfInitiatedDownloads.has(downloadItem.id)) {
    selfInitiatedDownloads.delete(downloadItem.id);
    return;
  }

  const downloadUrl = downloadItem.finalUrl || downloadItem.url;
  if (!downloadUrl || downloadUrl.startsWith('data:') || downloadUrl.startsWith('blob:')) {
    return;
  }

  // Cancel standard browser download
  try {
    await chrome.downloads.cancel(downloadItem.id);
    await chrome.downloads.erase({ id: downloadItem.id });
  } catch (_) {}

  // Gather headers
  const headers = requestHeadersCache.get(downloadUrl) || {};
  if (!headers['Referer'] && downloadItem.referrer) {
    headers['Referer'] = downloadItem.referrer;
  }

  const fileName = downloadItem.filename
    ? downloadItem.filename.split(/[/\\]/).pop()
    : extractFileName(downloadUrl, 'download.bin');

  // Send to desktop app
  await sendToDesktopApp({
    url: downloadUrl,
    fileName: fileName,
    headers: headers,
    category: getMediaCategory(downloadUrl, downloadItem.mime)
  });
});

// 4. Send Download Task to Desktop VirusDownloader App
async function sendToDesktopApp(payload) {
  let url = (payload.url || '').trim();
  if (url.startsWith('//')) {
    url = 'https:' + url;
  }
  if (!url || url.startsWith('blob:') || url.startsWith('data:')) {
    return {
      success: false,
      error: 'Cannot download browser-internal blob/data stream directly. Please click the extension icon to select the sniffed media stream.'
    };
  }

  const config = await getConfig();
  const targetUrl = `${config.serverUrl.replace(/\/$/, '')}/add`;

  try {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 6000);

    const res = await fetch(targetUrl, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        url: url,
        fileName: payload.fileName,
        headers: payload.headers || {},
        category: payload.category || 'other'
      }),
      signal: controller.signal
    });
    clearTimeout(timeout);

    const data = await res.json().catch(() => ({}));
    if (res.ok) {
      return { success: true, data };
    }
    return { success: false, error: data.error || `App responded with HTTP ${res.status}` };
  } catch (err) {
    return { success: false, error: 'Cannot connect to VirusDownloader. Is the app running?' };
  }
}

// 5. Check Desktop App Health
async function checkDesktopAppHealth() {
  const config = await getConfig();
  const targetUrl = `${config.serverUrl.replace(/\/$/, '')}/health`;

  try {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 2000);

    const res = await fetch(targetUrl, { signal: controller.signal });
    clearTimeout(timeout);

    if (res.ok) {
      const data = await res.json();
      return { connected: true, app: data.app || 'VirusDownloader', version: data.version };
    }
    return { connected: false, error: `HTTP ${res.status}` };
  } catch (err) {
    return { connected: false, error: 'Offline' };
  }
}

// 6. Communication with Popup and Content Scripts
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  const tabId = sender.tab ? sender.tab.id : null;

  if (message.type === 'GET_TAB_MEDIA') {
    const targetTabId = message.tabId || tabId;
    const items = tabMediaStore.get(targetTabId) || [];
    sendResponse({ media: items });
    return true;
  }

  if (message.type === 'DOM_MEDIA_FOUND') {
    if (tabId && message.items) {
      for (const item of message.items) {
        const cachedHeaders = requestHeadersCache.get(item.url) || {};
        if (!cachedHeaders['Referer'] && item.tabUrl) {
          cachedHeaders['Referer'] = item.tabUrl;
        }
        item.headers = { ...item.headers, ...cachedHeaders };
        addMediaToTab(tabId, item);
      }
      sendResponse({ status: 'ok' });
    }
    return true;
  }

  if (message.type === 'SEND_TO_APP') {
    sendToDesktopApp(message.payload).then(result => {
      sendResponse(result);
    });
    return true;
  }

  if (message.type === 'CHECK_APP_STATUS') {
    checkDesktopAppHealth().then(status => {
      sendResponse(status);
    });
    return true;
  }

  if (message.type === 'GET_CONFIG') {
    getConfig().then(cfg => sendResponse(cfg));
    return true;
  }

  if (message.type === 'SAVE_CONFIG') {
    saveConfig(message.config).then(cfg => sendResponse(cfg));
    return true;
  }

  if (message.type === 'DOWNLOAD_IN_BROWSER') {
    chrome.downloads.download({
      url: message.url,
      filename: message.fileName
    }, (downloadId) => {
      if (downloadId) {
        selfInitiatedDownloads.add(downloadId);
      }
      sendResponse({ downloadId });
    });
    return true;
  }
});

