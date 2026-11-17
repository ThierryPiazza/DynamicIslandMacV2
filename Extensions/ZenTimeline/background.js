/* Background polling keeps hidden playing tabs current without relying on their timers. */
'use strict';
const selection = new MediaSelection();
let port = null, current = null, artworkKey = '', artworkData = '', imageGeneration = 0;
let lastKey = '', lastSequence = -1, imagePending = false, lastImageAttempt = 0;
const documents = new Map();
function badge(text, title) {
  browser.browserAction.setBadgeText({text});
  browser.browserAction.setTitle({title: `DynamicIsland: ${title}`});
}
function connect() {
  if (port) return;
  try {
    const connected = browser.runtime.connectNative('com.thierrypiazza.dynamicisland.zen');
    port = connected;
    connected.onMessage.addListener(message => {
      if (message.ok) badge('OK', 'ponte connesso');
    });
    connected.onDisconnect.addListener(() => {
      if (port === connected) port = null;
      badge('!', connected.error?.message || 'host non disponibile');
    });
  } catch (error) { badge('!', String(error)); }
}
function send() {
  connect();
  if (!port) return;
  // Do not refresh sampledAt: the app expires a stuck content process.
  const track = current ? {...current, artworkDataBase64: artworkData} : null;
  try { port.postMessage({version: 1, track}); } catch { port = null; }
}
async function loadArtwork(url, generation) {
  let encoded = '';
  imagePending = true;
  lastImageAttempt = Date.now();
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 5000);
  try {
    if (!/^https?:\/\//.test(url)) return;
    const response = await fetch(url, {credentials: 'omit', signal: controller.signal, cache: 'no-cache'});
    if (!response.ok) return;
    const blob = await response.blob();
    if (blob.size > 5 * 1024 * 1024 || !blob.type.startsWith('image/')) return;
    const image = await createImageBitmap(blob);
    try {
      const scale = Math.min(1, 320 / Math.max(image.width, image.height));
      const canvas = document.createElement('canvas');
      canvas.width = Math.max(1, Math.round(image.width * scale));
      canvas.height = Math.max(1, Math.round(image.height * scale));
      canvas.getContext('2d').drawImage(image, 0, 0, canvas.width, canvas.height);
      encoded = canvas.toDataURL('image/jpeg', 0.85).split(',')[1];
    } finally { image.close(); }
  } catch { /* Missing/private/blocked images remain a placeholder. */ }
  finally {
    clearTimeout(timeout);
    if (generation === imageGeneration) { imagePending = false; artworkData = encoded; send(); }
  }
}
function publish(track) {
  current = track;
  const key = track ? `${track.identity}|${track.artworkURL}` : '';
  if (key !== artworkKey) {
    artworkKey = key;
    artworkData = '';
    imagePending = false;
    const generation = ++imageGeneration;
    if (track?.artworkURL) void loadArtwork(track.artworkURL, generation);
  }
  if (track?.artworkURL && !artworkData && !imagePending && Date.now() - lastImageAttempt > 10000) {
    void loadArtwork(track.artworkURL, imageGeneration);
  }
  send();
}
browser.runtime.onMessage.addListener((message, sender) => {
  if (message.type !== 'media' || !sender.tab || sender.tab.incognito) return;
  const key = `${sender.tab.id}:${sender.frameId}`;
  const doc = documents.get(key);
  if (message.track && (!Number.isFinite(message.track.sampledAt) ||
      Math.abs(Date.now() / 1000 - message.track.sampledAt) > 6)) return;
  if (doc?.id === message.documentID && message.track && message.track.sequence <= doc.sequence) return;
  // Discard a late pagehide before changing the replacement document's sequence.
  if (!message.track && doc && doc.id !== message.documentID) return;
  documents.set(key, {id: message.documentID, sequence: message.track?.sequence || 0});
  const track = message.track ? {...message.track, tabID: sender.tab.id} : null;
  const selected = selection.update(key, track, sender.tab.active && track?.visible === true);
  if (selected?.key !== lastKey || selected?.sequence !== lastSequence || !selected) {
    lastKey = selected?.key; lastSequence = selected?.sequence;
    publish(selected);
  }
});
browser.tabs.onRemoved.addListener(tabID => {
  for (const key of documents.keys()) if (key.startsWith(`${tabID}:`)) documents.delete(key);
  publish(selection.removeTab(tabID));
});
browser.tabs.onUpdated.addListener((tabID, change) => {
  if (change.status === 'loading') {
    for (const key of documents.keys()) if (key.startsWith(`${tabID}:`)) documents.delete(key);
    publish(selection.removeTab(tabID));
  }
});
async function poll() {
  const tabs = await browser.tabs.query({});
  await Promise.allSettled(tabs.filter(t => !t.incognito).map(t => browser.tabs.sendMessage(t.id, {type: 'poll'})));
  publish(selection.current());
}
setInterval(() => { void poll(); }, 2000);
void poll();
