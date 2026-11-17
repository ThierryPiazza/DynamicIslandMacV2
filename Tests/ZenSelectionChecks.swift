import Foundation
import JavaScriptCore

@main
struct ZenSelectionChecks {
    static func main() throws {
        let context = JSContext()!
        var error: String?
        context.exceptionHandler = { _, value in error = value?.toString() }
        for file in ["selection.js", "background.js", "content.js"] {
            let script = try String(contentsOfFile: "Extensions/ZenTimeline/\(file)", encoding: .utf8)
            // Parse every production script even though browser APIs are not present.
            context.evaluateScript("new Function(\(json(script)))")
            precondition(error == nil, error ?? "")
        }
        context.evaluateScript(try String(contentsOfFile: "Extensions/ZenTimeline/selection.js", encoding: .utf8))
        context.evaluateScript("""
        function check(ok, message) { if (!ok) throw new Error(message); }
        const s = new MediaSelection();
        const a = {identity: 'video-a', isPlaying: true, tabID: 1};
        const b = {identity: 'video-b', isPlaying: false, tabID: 2};
        check(s.update('a', a, false, 100).identity === 'video-a', 'background start');
        check(s.update('b', b, true, 101).identity === 'video-a', 'paused tab stole owner');
        check(s.update('b', {...b, isPlaying:true}, false, 102).identity === 'video-a', 'hidden autoplay stole owner');
        check(s.update('a', {...a, isPlaying:false}, false, 103).isPlaying === false, 'pause lost');
        check(s.update('b', {...b, isPlaying:false}, true, 104).identity === 'video-a', 'inactive pause stole owner');
        check(s.update('b', {...b, isPlaying:true}, true, 105).identity === 'video-b', 'explicit new playback');
        check(s.update('b', {...b, identity:'video-c', isPlaying:true}, false, 106).identity === 'video-c', 'SPA change');
        check(s.update('b', null, false, 107) === null, 'old paused video resurrected');
        check(s.update('a', a, false, 108).identity === 'video-a', 'resume');
        check(s.current(9000) === null, 'stale player not expired');
        """)
        precondition(error == nil, error ?? "")
        // Execute the production content script against a small DOM fixture.
        // This remains a simulation; the native transport is tested separately.
        context.evaluateScript("""
        const reports = [];
        let pollContent;
        class HTMLVideoElement {}
        const v = Object.assign(new HTMLVideoElement(), {isConnected:true, paused:false, ended:false,
          currentSrc:'', srcObject:null, poster:'https://fixture.invalid/cover-a.png',
          duration:120, currentTime:0, playbackRate:1, seeking:false});
        const crypto = {randomUUID: () => 'document-a'};
        const location = {href:'https://fixture.invalid/video-a'};
        const navigator = {mediaSession:{metadata:{title:'A', artist:'', album:'', artwork:[]}}};
        const document = {baseURI:location.href, title:'A', hidden:false,
          querySelectorAll: () => [v], querySelector: () => null, addEventListener: () => {}};
        const window = {addEventListener: () => {}};
        const browser = {runtime:{sendMessage: m => {reports.push(m); return {catch: () => {}};},
          onMessage:{addListener: fn => {pollContent = fn;}}}};
        class URL {
          constructor(value, base) { this.href = value; this.protocol = value.split(':')[0] + ':'; }
        }
        """)
        context.evaluateScript(try String(contentsOfFile: "Extensions/ZenTimeline/content.js", encoding: .utf8))
        context.evaluateScript("""
        const first = reports.at(-1).track;
        check(first.artworkURL.includes('cover-a'), 'initial cover missing');
        check(first.elapsed === 0, 'real zero was removed');
        v.currentSrc = 'https://fixture.invalid/a.mp4'; pollContent({type:'poll'});
        check(reports.at(-1).track.identity === first.identity, 'initial resource selection changed identity');
        check(reports.at(-1).track.artworkURL === first.artworkURL, 'initial cover was rejected');
        v.paused = true; v.currentTime = 24; pollContent({type:'poll'});
        check(reports.at(-1).track.elapsed === 24 && !reports.at(-1).track.isPlaying, 'paused seek lost');
        location.href = 'https://fixture.invalid/video-b'; v.currentSrc = 'https://fixture.invalid/b.mp4';
        pollContent({type:'poll'});
        check(reports.at(-1).track.identity !== first.identity, 'SPA identity unchanged');
        check(reports.at(-1).track.artworkURL === '', 'SPA reused old cover');
        v.poster = 'https://fixture.invalid/cover-b.png'; pollContent({type:'poll'});
        check(reports.at(-1).track.artworkURL.includes('cover-b'), 'new SPA cover rejected');
        v.poster = ''; v.duration = Infinity; v.paused = false; pollContent({type:'poll'});
        check(reports.at(-1).track.duration === null && reports.at(-1).track.artworkURL === '', 'live retained duration/image');
        """)
        precondition(error == nil, error ?? "")
        print("Zen: syntax, ownership and content checks passed (simulated JavaScript, not browser integration)")
    }
    static func json(_ value: String) -> String {
        String(data: try! JSONEncoder().encode(value), encoding: .utf8)!
    }
}
