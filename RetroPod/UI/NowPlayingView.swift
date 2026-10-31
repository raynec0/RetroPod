import SwiftUI

struct PodBar: View {
    let fraction: Double
    var diamond = false
    let k: CGFloat

    var body: some View {
        let f = fraction.isFinite ? max(0, min(1, fraction)) : 0
        GeometryReader { g in
            ZStack(alignment: .leading) {
                LinearGradient(colors: [.white, Color(hex: "E2E5E9")], startPoint: .top, endPoint: .bottom)
                LinearGradient(colors: [Color(hex: "8FC5F7"), Color(hex: "2A7BE0")], startPoint: .top, endPoint: .bottom)
                    .frame(width: g.size.width * CGFloat(f))
                    .opacity(diamond ? 0.25 : 1)
                if diamond {
                    Rectangle()
                        .fill(Color(hex: "1D6FD6"))
                        .frame(width: 7 * k, height: 7 * k)
                        .overlay(Rectangle().stroke(Color.white, lineWidth: 1))
                        .rotationEffect(.degrees(45))
                        .position(x: g.size.width * CGFloat(f), y: g.size.height / 2)
                }
            }
        }
        .frame(height: 9 * k)
        .overlay(Rectangle().stroke(Color(hex: "6B7280"), lineWidth: 1))
    }
}

struct NowPlayingView: View {
    let k: CGFloat
    @EnvironmentObject var player: Player
    @EnvironmentObject var lib: Library
    @EnvironmentObject var nav: Navigator
    @State private var scrub = false
    @State private var scrubAt = Date.distantPast
    @State private var volAt = Date.distantPast

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { ctx in
            content(now: ctx.date)
        }
        .onReceive(nav.events) { e in
            guard nav.top == .nowPlaying, player.current != nil else { return }
            let scrubbing = scrub && Date().timeIntervalSince(scrubAt) < 3.5
            switch e {
            case .scroll(let d):
                if scrubbing {
                    player.seek(player.currentTime + Double(d) * 3)
                    scrubAt = Date()
                } else {
                    scrub = false
                    player.volume = max(0, min(1, player.volume + Float(d) * 0.04))
                    volAt = Date()
                }
            case .select:
                scrub = !scrubbing
                scrubAt = Date()
            }
        }
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        if let t = player.current {
            let scrubbing = scrub && now.timeIntervalSince(scrubAt) < 3.5
            let showVol = !scrubbing && now.timeIntervalSince(volAt) < 1.6
            let pos = player.currentTime
            let dur = player.duration
            VStack(alignment: .leading, spacing: 0) {
                Text("\(player.index + 1) / \(player.queue.count)")
                    .font(.system(size: 10.5 * k))
                    .monospacedDigit()
                    .foregroundColor(Color(white: 0.33))
                HStack(alignment: .top, spacing: 10 * k) {
                    AlbumArt(file: lib.coverFile(for: t), name: t.album, artist: t.artist)
                        .frame(width: 84 * k, height: 84 * k)
                        .clipped()
                        .shadow(color: .black.opacity(0.35), radius: 1.5 * k, y: 1)
                    VStack(alignment: .leading, spacing: 3 * k) {
                        Text(t.title).font(.system(size: 13 * k, weight: .bold)).lineLimit(2)
                        Text(t.artist).font(.system(size: 11.5 * k)).lineLimit(1)
                        Text(t.album).font(.system(size: 11.5 * k)).lineLimit(1)
                    }
                    .padding(.top, 6 * k)
                    Spacer(minLength: 0)
                }
                .padding(.top, 5 * k)
                Spacer(minLength: 0)
                if showVol {
                    HStack(spacing: 6 * k) {
                        Image(systemName: "speaker.fill").font(.system(size: 9 * k))
                        PodBar(fraction: Double(player.volume), k: k)
                        Image(systemName: "speaker.wave.3.fill").font(.system(size: 9 * k))
                    }
                    .foregroundColor(Color(white: 0.27))
                    .frame(height: 24 * k)
                } else {
                    VStack(spacing: 3 * k) {
                        PodBar(fraction: dur > 0 ? pos / dur : 0, diamond: scrubbing, k: k)
                        HStack {
                            Text(fmt(pos))
                            Spacer()
                            Text("-" + fmt(max(0, dur - pos)))
                        }
                        .font(.system(size: 10.5 * k))
                        .monospacedDigit()
                    }
                    .frame(height: 24 * k)
                }
            }
            .padding(.horizontal, 10 * k)
            .padding(.top, 6 * k)
            .padding(.bottom, 8 * k)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(LinearGradient(colors: [.white, Color(hex: "ECEFF3")], startPoint: .top, endPoint: .bottom))
            .foregroundColor(.black)
        } else {
            VStack(spacing: 4 * k) {
                Text("还没有播放任何歌曲")
                Text("按 ⏯ 开始播放")
            }
            .font(.system(size: 12 * k))
            .foregroundColor(Color(hex: "6B7280"))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white)
        }
    }
}
