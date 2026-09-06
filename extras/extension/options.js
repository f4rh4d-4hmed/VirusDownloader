/**
 * VirusDownloader Browser Extension - Options Script
 */

document.addEventListener('DOMContentLoaded', () => {
  const serverUrlInput = document.getElementById('serverUrl');
  const interceptDownloadsInput = document.getElementById('interceptDownloads');
  const showFloatingButtonInput = document.getElementById('showFloatingButton');
  const minVideoSizeInput = document.getElementById('minVideoSize');
  const ignoredDomainsInput = document.getElementById('ignoredDomains');
  const testConnBtn = document.getElementById('testConnBtn');
  const testResult = document.getElementById('testResult');
  const saveBtn = document.getElementById('saveBtn');
  const saveResult = document.getElementById('saveResult');

  // Load configuration
  chrome.runtime.sendMessage({ type: 'GET_CONFIG' }, (config) => {
    if (config) {
      serverUrlInput.value = config.serverUrl || 'http://127.0.0.1:9849';
      interceptDownloadsInput.checked = config.interceptDownloads !== false;
      showFloatingButtonInput.checked = config.showFloatingButton !== false;
      minVideoSizeInput.value = Math.round((config.minVideoSizeBytes || 0) / 1024);
      ignoredDomainsInput.value = (config.ignoredDomains || []).join('\n');
    }
  });

  // Test Connection
  testConnBtn.addEventListener('click', async () => {
    testResult.className = 'status-msg';
    testResult.innerText = 'Testing...';

    const url = `${serverUrlInput.value.trim().replace(/\/$/, '')}/health`;
    try {
      const controller = new AbortController();
      const timeout = setTimeout(() => controller.abort(), 2500);

      const res = await fetch(url, { signal: controller.signal });
      clearTimeout(timeout);

      if (res.ok) {
        const data = await res.json();
        testResult.className = 'status-msg status-success';
        testResult.innerText = `✓ Connected to ${data.app || 'VirusDownloader'} v${data.version || '1.0'}`;
      } else {
        testResult.className = 'status-msg status-error';
        testResult.innerText = `Server responded with HTTP ${res.status}`;
      }
    } catch (err) {
      testResult.className = 'status-msg status-error';
      testResult.innerText = 'Failed to connect. Is VirusDownloader running?';
    }
  });

  // Save Settings
  saveBtn.addEventListener('click', () => {
    saveResult.className = 'status-msg';
    saveResult.innerText = '';

    const minSizeKB = parseInt(minVideoSizeInput.value.trim() || '0', 10);
    const ignoredList = ignoredDomainsInput.value
      .split('\n')
      .map(s => s.trim())
      .filter(Boolean);

    const updatedConfig = {
      serverUrl: serverUrlInput.value.trim() || 'http://127.0.0.1:9849',
      interceptDownloads: interceptDownloadsInput.checked,
      showFloatingButton: showFloatingButtonInput.checked,
      minVideoSizeBytes: minSizeKB * 1024,
      ignoredDomains: ignoredList
    };

    chrome.runtime.sendMessage({
      type: 'SAVE_CONFIG',
      config: updatedConfig
    }, () => {
      saveResult.className = 'status-msg status-success';
      saveResult.innerText = '✓ Settings saved successfully!';
      setTimeout(() => { saveResult.innerText = ''; }, 3000);
    });
  });
});

