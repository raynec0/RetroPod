import SwiftUI

struct ClickWheel: View {
    let size: CGFloat
    let theme: PodTheme
    var onScroll: (Int) -> Void
    var onMenu: () -> Void
    var onPlay: () -> Void
    var onNext: () -> Void
    var onPrev: () -> Void
    var onSelect: () -> Void

    @State private var lastAngle: Double? = nil
    @State private var acc: Double = 0
    @State private var moved: Double = 0
    @State private var start: CGPoint = .zero
    @State private var flash: String? = nil
    @State private var centerDown = false

    /// One click every 18 degrees, close to the feel of a real wheel.
    private let step = Double.pi / 10

    var body: some View {
        let c = size / 2
        ZStack {
            Circle()
                .fill(RadialGradient(colors: theme.wheelColors, center: UnitPoint(x: 0.5, y: 0.35),
                                     startRadius: 0, endRadius: size * 0.6))
                .overlay(Circle().stroke(theme.wheelEdge, lineWidth: 1))
                .shadow(color: .black.opacity(0.12), radius: 1, y: 1)
                .contentShape(Circle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            let p = v.location
                            let a = atan2(Double(p.y - c), Double(p.x - c))
                            if let la = lastAngle {
                                var d = a - la
                                if d > .pi { d -= 2 * .pi }
                                if d < -.pi { d += 2 * .pi }
                                var total = acc + d
                                moved += abs(d)
                                while total > step { total -= step; onScroll(1) }
                                while total < -step { total += step; onScroll(-1) }
                                acc = total
                            } else {
                                start = v.startLocation
                                acc = 0
                                moved = 0
                            }
                            lastAngle = a
                        }
                        .onEnded { v in
                            lastAngle = nil
                            let dist = hypot(v.translation.width, v.translation.height)
                            guard moved < 0.25, dist < 14 else { return }
                            let dx = start.x - c, dy = start.y - c
                            if abs(dy) >= abs(dx) {
                                if dy < 0 { press("menu"); onMenu() } else { press("play"); onPlay() }
                            } else if dx > 0 {
                                press("next"); onNext()
                            } else {
                                press("prev"); onPrev()
                            }
                        }
                )

            Text("MENU")
                .font(.system(size: size * 0.064, weight: .heavy))
                .tracking(1.2)
                .foregroundColor(theme.label)
                .opacity(flash == "menu" ? 0.4 : 1)
                .offset(y: -size * 0.385)
                .allowsHitTesting(false)
            Image(systemName: "forward.end.alt.fill")
                .font(.system(size: size * 0.07))
                .foregroundColor(theme.label)
                .opacity(flash == "next" ? 0.4 : 1)
                .offset(x: size * 0.385)
                .allowsHitTesting(false)
            Image(systemName: "backward.end.alt.fill")
                .font(.system(size: size * 0.07))
                .foregroundColor(theme.label)
                .opacity(flash == "prev" ? 0.4 : 1)
                .offset(x: -size * 0.385)
                .allowsHitTesting(false)
            Image(systemName: "playpause.fill")
                .font(.system(size: size * 0.07))
                .foregroundColor(theme.label)
                .opacity(flash == "play" ? 0.4 : 1)
                .offset(y: size * 0.385)
                .allowsHitTesting(false)

            Circle()
                .fill(LinearGradient(colors: theme.centerColors, startPoint: .top, endPoint: .bottom))
                .overlay(Circle().stroke(theme.centerEdge, lineWidth: 1))
                .brightness(centerDown ? -0.06 : 0)
                .frame(width: size * 0.38, height: size * 0.38)
                .contentShape(Circle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in if !centerDown { centerDown = true } }
                        .onEnded { v in
                            centerDown = false
                            if hypot(v.translation.width, v.translation.height) < 20 { onSelect() }
                        }
                )
        }
        .frame(width: size, height: size)
    }

    private func press(_ k: String) {
        flash = k
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            if flash == k { flash = nil }
        }
    }
}
