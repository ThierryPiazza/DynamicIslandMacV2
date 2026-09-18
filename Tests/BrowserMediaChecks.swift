import Foundation
import JavaScriptCore

@main
struct BrowserMediaChecks {
    static func main() throws {
        let source = try String(contentsOfFile: "DynamicIslandV2/System/Resources/BrowserMedia.js", encoding: .utf8)
        let context = JSContext()!
        context.exceptionHandler = { _, error in fatalError(error?.toString() ?? "JavaScript error") }
        context.evaluateScript("""
        var items = [];
        var document = {title: 'Pagina qualsiasi', querySelectorAll: function (q) {return q === 'iframe' ? [] : items;}};
        var location = {href:'https://example.org/listen',hostname:'example.org'};
        var navigator = {mediaSession:{metadata:null,playbackState:'none'}};
        var window = {document:document,location:location,navigator:navigator};
        var URL = function(src, base) {this.href=src;};
        var readMedia = (\(source));
        function media(paused, time, src) {return {paused:paused,ended:false,muted:false,volume:1,currentTime:time,
            currentSrc:src,duration:200,playbackRate:1,pause:function(){this.paused=true;},play:function(){this.paused=false;return {catch:function(){}};}};}
        """)
        check(context.evaluateScript("readMedia() === null")!.toBool(), "Una pagina normale non è una riproduzione")
        context.evaluateScript("items=[media(true,0,'intro'),media(false,40,'song')];")
        check(context.evaluateScript("readMedia().mediaURL === 'song' && readMedia().isPlaying")!.toBool(), "Sceglie l’elemento che suona, non il primo")
        context.evaluateScript(#"navigator.mediaSession.metadata={title:'Titolo | con "virgolette" 🎵',artist:'Artista',album:'Album',artwork:[]};"#)
        let json = context.evaluateScript("JSON.stringify(readMedia())")!.toString()!
        let tracks = BrowserObserver.parseTracks(raw: "10|2|\(json)\n", bundleID: "browser.one")
        check(tracks.count == 1 && tracks[0].artist == "Artista" && tracks[0].title.contains("|"), "Metadati JSON con separatori e Unicode")
        check(tracks[0].windowID == 10 && tracks[0].tabIndex == 2, "Mantiene l’identità del tab per i comandi")
        check(context.evaluateScript("readMedia({action:'pause',pageURL:location.href,frameURL:location.href,mediaURL:'wrong'}) === false && !items[1].paused")!.toBool(), "Non controlla un media diverso")
        check(context.evaluateScript("readMedia({action:'pause',pageURL:location.href,frameURL:location.href,mediaURL:'song'}) && items[1].paused")!.toBool(), "Pausa sul media rilevato")
        check(context.evaluateScript("readMedia({action:'play',pageURL:'https://different.test',frameURL:location.href,mediaURL:'song'}) === false")!.toBool(), "Un tab navigato non riceve comandi vecchi")
        check(context.evaluateScript("readMedia({action:'play',pageURL:location.href,frameURL:location.href,mediaURL:'song'}) && !items[1].paused")!.toBool(), "Riprende il media corretto")
        var paused = tracks[0]
        paused.isPlaying = false
        paused.bundleID = "browser.two"
        check(BrowserObserver.preferred([paused, tracks[0]], previousIdentity: paused.identity)?.isPlaying == true, "Un altro browser in riproduzione supera un tab in pausa")
        var second = tracks[0]
        second.bundleID = "browser.two"
        check(BrowserObserver.preferred([second, tracks[0]], previousIdentity: tracks[0].identity)?.identity == tracks[0].identity, "Non oscilla tra due sorgenti attive")
        check(BrowserObserver.parseTracks(raw: "bad|data|{}\n10|2|not json", bundleID: "test").isEmpty, "Scarta risposte incomplete")
        context.evaluateScript("items=[]; navigator.mediaSession.playbackState='playing';")
        check(context.evaluateScript("readMedia().isPlaying && !readMedia().canToggle")!.toBool(), "WebAudio con metadata non inventa controlli DOM")
        print("12 controlli browser superati: rilevamento, JSON, selezione e destinazione dei comandi.")
    }
    static func check(_ condition: Bool, _ description: String) { precondition(condition, description) }
}
