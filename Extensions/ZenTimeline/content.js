/* Reads the real HTML player. Does not write Media Session or change playback. */
(() => {
  'use strict';
  const documentID = crypto.randomUUID();
  const ids = new WeakMap();
  const waiting = new WeakSet();
  let serial = 0, selected = null, identity = '', priorArtwork = '', rejectedArtwork = '';
  let lastSent = 0, sequence = 0, suspended = false;
  const playing = v => v.isConnected && !v.paused && !v.ended;
  const httpURL = value => {
    try { if (!value) return ''; const u = new URL(value, document.baseURI); return /^https?:$/.test(u.protocol) ? u.href : ''; }
    catch { return ''; }
  };
  const meta = selector => document.querySelector(selector)?.content || '';
  function snapshot() {
    const videos = [...document.querySelectorAll('video')];
    const video = (selected && playing(selected) ? selected : videos.find(playing)) || (selected?.isConnected && !selected.ended ? selected : null);
    if (!video) { selected = null; return null; }
    selected = video;
    if (!ids.has(video)) ids.set(video, {id: ++serial, source: '', object: video.srcObject, revision: 0});
    const state = ids.get(video);
    const source = video.currentSrc;
    // Initial resource selection ('' → URL) is not a video change: otherwise
    // its still-valid first cover would be rejected after loadedmetadata.
    if ((state.source && source && state.source !== source) || state.object !== video.srcObject) state.revision++;
    if (source) state.source = source;
    state.object = video.srcObject;
    const nextIdentity = `${documentID}|${state.id}|${location.href}|${state.revision}`;
    const metadata = navigator.mediaSession?.metadata;
    let artworkURL = httpURL(metadata?.artwork?.[0]?.src || '') || httpURL(video.poster || '') ||
      httpURL(meta('meta[property="og:image:secure_url"]') || meta('meta[property="og:image"]') ||
        meta('meta[name="twitter:image"], meta[property="twitter:image"]'));
    // A SPA may change the player before publishing the new image. Never reuse
    // the unchanged image of its previous video while waiting for metadata.
    if (identity && identity !== nextIdentity) rejectedArtwork = priorArtwork;
    identity = nextIdentity;
    priorArtwork = artworkURL;
    if (artworkURL === rejectedArtwork) artworkURL = '';
    const duration = Number.isFinite(video.duration) && video.duration > 0 ? video.duration : null;
    const elapsed = Number.isFinite(video.currentTime) && video.currentTime >= 0 ? video.currentTime : null;
    return {
      identity, visible: !document.hidden, title: String(metadata?.title || document.title || 'Video').slice(0, 1024),
      artist: String(metadata?.artist || '').slice(0, 1024), album: String(metadata?.album || '').slice(0, 1024),
      pageURL: location.href, artworkURL, duration, elapsed,
      playbackRate: !video.seeking && !waiting.has(video) && Number.isFinite(video.playbackRate) && video.playbackRate > 0 ? video.playbackRate : 0,
      isPlaying: playing(video),
      sampledAt: Date.now() / 1000, sequence: ++sequence
    };
  }
  function report(force = false) {
    if (suspended || (!force && Date.now() - lastSent < 500)) return;
    lastSent = Date.now();
    browser.runtime.sendMessage({type: 'media', documentID, track: snapshot()}).catch(() => {});
  }
  for (const name of ['play', 'playing', 'pause', 'ended', 'emptied', 'loadedmetadata',
    'durationchange', 'seeking', 'seeked', 'ratechange', 'waiting', 'timeupdate']) {
    document.addEventListener(name, event => {
      const v = event.target;
      if (!(v instanceof HTMLVideoElement)) return;
      if (name === 'waiting') waiting.add(v);
      if (['playing', 'seeked', 'timeupdate'].includes(name)) waiting.delete(v);
      if (['play', 'playing'].includes(name)) selected = v;
      if (v === selected || playing(v)) report(name !== 'timeupdate');
    }, true);
  }
  browser.runtime.onMessage.addListener(message => {
    if (message.type === 'poll') report(true);
  });
  window.addEventListener('pagehide', () => {
    browser.runtime.sendMessage({type: 'media', documentID, track: null}).catch(() => {});
    suspended = true;
  });
  window.addEventListener('pageshow', () => { suspended = false; report(true); });
  report(true);
})();
