// Returns only media candidates, never the title of an unrelated tab.
(command = null) => {
    const frames = [];
    const visit = (win, depth) => {
        if (depth > 6) return;
        try {
            frames.push(win);
            for (const frame of win.document.querySelectorAll('iframe')) {
                try { void frame.contentWindow.document; visit(frame.contentWindow, depth + 1); } catch (_) {}
            }
        } catch (_) {}
    };
    visit(window, 0);
    const candidates = [];
    for (const win of frames) {
        try {
            const session = win.navigator.mediaSession;
            const metadata = session && session.metadata;
            const media = Array.from(win.document.querySelectorAll('video, audio'));
            const active = media.find(m => !m.paused && !m.ended && !m.muted && m.volume > 0);
            const previous = media.find(m => !m.ended && (m.currentTime > 0 || (metadata && session.playbackState === 'paused')));
            const element = active || previous;
            const playing = Boolean(active) || (!media.length && session && session.playbackState === 'playing');
            if (!element && !(metadata && session.playbackState !== 'none')) continue;
            const sourceID = element ? (element.currentSrc || element.src || '') : '';
            if (command) {
                if (location.href !== command.pageURL || win.location.href !== command.frameURL) continue;
                if (!element || sourceID !== command.mediaURL) continue;
                if (command.action === 'pause') element.pause();
                else if (command.action === 'play') element.play().catch(() => {});
                else return false;
                return true;
            }
            const artwork = metadata && metadata.artwork && metadata.artwork[0];
            candidates.push({
                title: (metadata && metadata.title) || win.document.title || document.title || 'Contenuto multimediale',
                artist: (metadata && metadata.artist) || '',
                album: (metadata && metadata.album) || '',
                artworkURL: artwork ? new URL(artwork.src, win.location.href).href : '',
                pageURL: location.href,
                frameURL: win.location.href,
                mediaURL: sourceID,
                source: win.location.hostname || 'Browser',
                duration: element && Number.isFinite(element.duration) ? element.duration : 0,
                elapsed: element && Number.isFinite(element.currentTime) ? element.currentTime : 0,
                playbackRate: element ? element.playbackRate : 1,
                isPlaying: playing,
                canToggle: Boolean(element)
            });
        } catch (_) {}
    }
    if (command) return false;
    return candidates.find(c => c.isPlaying) || candidates[0] || null;
}
