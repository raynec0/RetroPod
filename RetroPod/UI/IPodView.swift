import SwiftUI
import Combine
import UniformTypeIdentifiers

struct IPodView: View {
    @EnvironmentObject var lib: Library
    @EnvironmentObject var player: Player
    @EnvironmentObject var nav: Navigator
    @AppStorage("theme") private var themeName = "white"
    @State private var lastInput = Date()
    @State private var dim = false
    @State private var toast: String? = nil
    @State private var dragStep: CGFloat = 0

    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        let theme = PodTheme.named(themeName)
        GeometryReader { geo in
            let W = geo.size.width
            let H = geo.size.height
            let screenW = min(W - 36, H * 0.46 * 260 / 196)
            let k = screenW / 260
            let wheel = min(W * 0.74, H * 0.40)
            VStack(spacing: 0) {
                Spacer().frame(height: max(10, H * 0.035))
                screen(k: k)
                    .padding(5 * k)
                    .background(RoundedRectangle(cornerRadius: 9 * k).fill(theme.bezel))
                    .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                Spacer(minLength: 12)
                ClickWheel(size: wheel, theme: theme,
                           onScroll: { d in input(); Feedback.tick(); nav.events.send(.scroll(d)) },
                           onMenu: { input(); Feedback.tick(); nav.menu() },
                           onPlay: { input(); Feedback.tick(); player.toggle() },
                           onNext: { input(); Feedback.tick(); player.next() },
                           onPrev: { input(); Feedback.tick(); player.previous() },
                           onSelect: { input(); Feedback.tick(); nav.events.send(.select) })
                Spacer().frame(height: max(18, H * 0.07))
            }
            .frame(width: W, height: H)
        }
        .background(
            LinearGradient(colors: theme.bodyColors, startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
        )
        .statusBarHidden(true)
        .preferredColorScheme(theme.dark ? .dark : .light)
        .fileImporter(isPresented: $nav.showImporter, allowedContentTypes: [.audio], allowsMultipleSelection: true) { r in
            if case .success(let urls) = r { lib.importFiles(urls) }
        }
        .onReceive(clock) { now in
            if !dim && now.timeIntervalSince(lastInput) > 30 {
                withAnimation(.easeInOut(duration: 0.6)) { dim = true }
            }
        }
        .onReceive(lib.$message.compactMap { $0 }) { m in
            showToast(m)
            DispatchQueue.main.async { lib.message = nil }
        }
        .onAppear { UIDevice.current.isBatteryMonitoringEnabled = true }
    }

    private func input() {
        lastInput = Date()
        if dim { withAnimation(.easeOut(duration: 0.2)) { dim = false } }
    }

    private func showToast(_ m: String) {
        withAnimation { toast = m }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
            if toast == m { withAnimation { toast = nil } }
        }
    }

    private func screen(k: CGFloat) -> some View {
        ZStack(alignment: .top) {
            Color.white
            VStack(spacing: 0) {
                TitleBar(k: k)
                ZStack {
                    ForEach(nav.stack.suffix(1), id: \.self) { s in
                        ScreenView(screen: s, k: k)
                            .transition(.asymmetric(insertion: .move(edge: nav.forward ? .trailing : .leading),
                                                    removal: .move(edge: nav.forward ? .leading : .trailing)))
                    }
                }
                .frame(width: 260 * k, height: 175 * k)
                .clipped()
                .contentShape(Rectangle())
                .gesture(listDrag(k))
            }
            if dim {
                Color.black.opacity(0.55).allowsHitTesting(false)
            }
            if let t = toast {
                VStack {
                    Spacer()
                    Text(t)
                        .font(.system(size: 11.5 * k))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .padding(.horizontal, 10 * k)
                        .padding(.vertical, 5 * k)
                        .background(RoundedRectangle(cornerRadius: 6 * k).fill(Color(hex: "14161A").opacity(0.86)))
                        .padding(.bottom, 10 * k)
                }
                .allowsHitTesting(false)
                .transition(.opacity)
            }
        }
        .frame(width: 260 * k, height: 196 * k)
        .clipShape(RoundedRectangle(cornerRadius: 4 * k))
        .simultaneousGesture(TapGesture().onEnded { input() })
    }

    /// Vertical swipes on the screen scroll lists one row at a time.
    private func listDrag(_ k: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { v in
                guard nav.top != .coverFlow else { return }
                input()
                let rowH = 25 * k
                var s = dragStep
                while v.translation.height - s < -rowH { s -= rowH; Feedback.tick(); nav.events.send(.scroll(1)) }
                while v.translation.height - s > rowH { s += rowH; Feedback.tick(); nav.events.send(.scroll(-1)) }
                dragStep = s
            }
            .onEnded { _ in dragStep = 0 }
    }
}

struct TitleBar: View {
    let k: CGFloat
    @EnvironmentObject var nav: Navigator
    @EnvironmentObject var player: Player
    @EnvironmentObject var lib: Library

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: "FDFDFD"), Color(hex: "D3D7DD")], startPoint: .top, endPoint: .bottom)
            Text(screenTitle(nav.top, lib))
                .font(.system(size: 11.5 * k, weight: .bold))
                .foregroundColor(.black)
                .lineLimit(1)
                .frame(maxWidth: 150 * k)
            HStack {
                if player.current != nil {
                    Image(systemName: player.isPlaying ? "play.fill" : "pause.fill")
                        .font(.system(size: 8 * k))
                        .foregroundColor(Color(hex: "2A6FD6"))
                }
                Spacer()
                Battery(k: k)
            }
            .padding(.horizontal, 6 * k)
        }
        .frame(height: 21 * k)
        .overlay(Rectangle().fill(Color(hex: "8E959E")).frame(height: 1), alignment: .bottom)
    }
}

struct Battery: View {
    let k: CGFloat
    var body: some View {
        let lv = UIDevice.current.batteryLevel
        let f = lv < 0 ? 1 : CGFloat(lv)
        HStack(spacing: 0.5 * k) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1.5 * k)
                    .stroke(Color(hex: "3A3F46"), lineWidth: 1)
                    .frame(width: 17 * k, height: 9 * k)
                RoundedRectangle(cornerRadius: 0.5 * k)
                    .fill(f < 0.2 ? Color.red : Color(hex: "57B937"))
                    .frame(width: max(1, 14 * k * f), height: 6 * k)
                    .padding(.leading, 1.5 * k)
            }
            Rectangle().fill(Color(hex: "3A3F46")).frame(width: 1.6 * k, height: 4 * k)
        }
    }
}
