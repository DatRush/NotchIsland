import AppKit
import SwiftUI

struct MusicArtwork: View {
    @ObservedObject var music: MusicPlayback
    var body: some View {
        Group {
            if let image = music.artwork { Image(nsImage: image).resizable().scaledToFill() }
            else { ZStack { Color.white.opacity(0.12); Image(systemName: "music.note").font(.system(size: 17)).foregroundColor(.white) } }
        }.clipped().clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
struct MusicWaveform: View {
    var playing: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.18, paused: !playing || reduceMotion)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 3) {
                ForEach(0..<5) { index in
                    Capsule().fill(Color.white.opacity(0.85))
                        .frame(width: 3, height: playing && !reduceMotion ? 5 + 15 * abs(sin(time * 3 + Double(index) * 1.3)) : CGFloat([8, 14, 20, 14, 8][index]))
                }
            }.frame(width: 28, height: 24)
        }.accessibilityHidden(true)
    }
}
struct MusicPlayerView: View {
    @ObservedObject var music: MusicPlayback
    @State private var position = 0.0
    @State private var dragging = false
    private func time(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let value = max(0, Int(seconds)); return String(format: "%d:%02d", value / 60, value % 60)
    }
    var body: some View {
        if let track = music.track {
            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    MusicArtwork(music: music).frame(width: 62, height: 62)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(track.title).font(.system(size: 15, weight: .semibold)).lineLimit(2)
                        Text(track.artist).font(.system(size: 12)).foregroundColor(.gray).lineLimit(1)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    MusicWaveform(playing: track.playing)
                }
                if track.duration > 0 {
                    VStack(spacing: 0) {
                        if track.canSeek {
                        Slider(value: Binding(get: { dragging ? position : min(track.duration, max(0, track.elapsed)) }, set: { position = $0 }), in: 0...max(1, track.duration), onEditingChanged: { editing in
                            dragging = editing
                            if !editing { music.send(.seek(position)) }
                        }).tint(.white).accessibilityLabel(L("Позиция воспроизведения", "Playback position"))
                        } else {
                            ProgressView(value: min(track.duration, max(0, track.elapsed)), total: track.duration)
                                .tint(.white).padding(.vertical, 7).accessibilityLabel(L("Позиция воспроизведения", "Playback position"))
                        }
                        HStack {
                            Text(time(dragging ? position : track.elapsed)); Spacer(); Text("−" + time(track.duration - (dragging ? position : track.elapsed)))
                        }.font(.system(size: 10).monospacedDigit()).foregroundColor(.gray)
                    }
                } else { Spacer(minLength: 0).frame(height: 20) }
                HStack(spacing: 36) {
                    Button { music.send(.previous) } label: { Image(systemName: "backward.fill").font(.system(size: 22)) }
                        .accessibilityLabel(L("Предыдущий трек", "Previous track")).disabled(track.source != "com.apple.Music" && track.source != "ru.yandex.desktop.music")
                    Button { if track.playing { music.send(.toggle) } else { music.resumeLast() } } label: { Image(systemName: track.playing ? "pause.fill" : "play.fill").font(.system(size: 28)) }
                        .accessibilityLabel(track.playing ? L("Пауза", "Pause") : L("Воспроизвести", "Play"))
                    Button { music.send(.next) } label: { Image(systemName: "forward.fill").font(.system(size: 22)) }
                        .accessibilityLabel(L("Следующий трек", "Next track"))
                }.buttonStyle(.plain).frame(maxWidth: .infinity)
                if let message = music.resumeMessage { Text(message).font(.caption).foregroundColor(.gray) }
            }.padding(.top, 5)
        } else {
            VStack(spacing: 18) {
                Image(systemName: "music.note").font(.system(size: 30))
                Text(L("Включите музыку в любимом плеере", "Start music in your favorite player")).font(.system(size: 13)).foregroundColor(.gray)
                HStack {
                    Button("Apple Music") { music.resumeLast(source: "com.apple.Music") }
                    Button(L("Яндекс Музыка", "Yandex Music")) { music.resumeLast(source: "ru.yandex.desktop.music") }
                }
                if let message = music.resumeMessage { Text(message).font(.caption).foregroundColor(.gray) }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
