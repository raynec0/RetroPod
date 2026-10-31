import SwiftUI
import QuartzCore

// MARK: - Model (spring-driven, so dragging and wheel scrolling share one smooth motion)

final class CoverFlowModel: NSObject, ObservableObject {
    @Published var pos: Double = 0
    @Published var flip: Double = 0
    @Published var trackSel = 0
    @Published var trackTop = 0
    var target: Double = 0
    var flipTarget: Double = 0
    var dragging = false
    var count = 0

    private var vel: Double = 0
    private var flipVel: Double = 0
    private var link: CADisplayLink?

    var index: Int { max(0, min(count - 1, Int(target.rounded()))) }

    func go(by d: Int) { setTarget(target + Double(d)) }

    func setTarget(_ t: Double) {
        target = max(0, min(Double(max(0, count - 1)), t.rounded()))
        run()
    }

    func flipOpen() {
        flipTarget = 1
        trackSel = 0
        trackTop = 0
        run()
    }

    func unflip() {
        flipTarget = 0
        run()
    }

    func dragTo(_ p: Double) {
        pos = max(-0.45, min(Double(max(0, count - 1)) + 0.45, p))
        vel = 0
    }

    func endDrag(extra: Double) {
        dragging = false
        setTarget(pos + extra)
    }

    func run() {
        guard link == nil else { return }
        let l = CADisplayLink(target: self, selector: #selector(tick(_:)))
        l.add(to: .main, forMode: .common)
        link = l
    }

    @objc private func tick(_ l: CADisplayLink) {
        let dt = min(0.05, max(0.001, l.targetTimestamp - l.timestamp))
        if !dragging {
            let w = 15.0
            let a = -2 * w * vel - w * w * (pos - target)
            vel += a * dt
            pos += vel * dt
        }
        let wf = 12.0
        let af = -2 * wf * flipVel - wf * wf * (flip - flipTarget)
        flipVel += af * dt
        flip += flipVel * dt
        if !dragging && abs(pos - target) < 0.0005 && abs(vel) < 0.002
            && abs(flip - flipTarget) < 0.0005 && abs(flipVel) < 0.002 {
            pos = target
            flip = flipTarget
            vel = 0
            flipVel = 0
            link?.invalidate()
            link = nil
        }
    }
}

// MARK: - 3D helpers (row-vector matrices, same convention as Core Animation)

private func rotY(_ a: CGFloat) -> CATransform3D {
    var m = CATransform3DIdentity
    m.m11 = cos(a); m.m13 = -sin(a)
    m.m31 = sin(a); m.m33 = cos(a)
    return m
}

private func rotX(_ a: CGFloat) -> CATransform3D {
    var m = CATransform3DIdentity
    m.m22 = cos(a); m.m23 = sin(a)
    m.m32 = -sin(a); m.m33 = cos(a)
    return m
}

private func apply(_ m: CATransform3D, _ x: CGFloat, _ y: CGFloat, _ z: CGFloat, _ w: CGFloat) -> (x: CGFloat, y: CGFloat, z: CGFloat) {
    (x * m.m11 + y * m.m21 + z * m.m31 + w * m.m41,
     x * m.m12 + y * m.m22 + z * m.m32 + w * m.m42,
     x * m.m13 + y * m.m23 + z * m.m33 + w * m.m43)
}

private func cat(_ ms: CATransform3D...) -> CATransform3D {
    ms.dropFirst().reduce(ms[0]) { CATransform3DConcat($0, $1) }
}

struct Projected: GeometryEffect {
    var t: CATransform3D
    var animatableData: EmptyAnimatableData {
        get { EmptyAnimatableData() }
        set {}
    }
    func effectValue(size: CGSize) -> ProjectionTransform { ProjectionTransform(t) }
}

struct CFFace: Identifiable {
    enum Kind: String { case front, back, spine, edge, top, bottom, reflection }
    let id: String
    let kind: Kind
    let album: Int
    let w: CGFloat
    let h: CGFloat
    let m: CATransform3D
    let depth: CGFloat
    let alpha: Double
}

// MARK: - View

struct CoverFlowView: View {
    @ObservedObject var m: CoverFlowModel
    let k: CGFloat
    @EnvironmentObject var lib: Library
    @EnvironmentObject var nav: Navigator
    @EnvironmentObject var player: Player
    @State private var dragStart: Double? = nil

    private var headerH: CGFloat { 34 * k }
    private var rowH: CGFloat { 20 * k }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: [.black, Color(hex: "16171A")], startPoint: .top, endPoint: .bottom)
                if lib.albums.isEmpty {
                    Text("还没有音乐\n在主菜单选「导入音乐」")
                        .font(.system(size: 12 * k))
                        .foregroundColor(Color(white: 0.7))
                        .multilineTextAlignment(.center)
                        .frame(width: size.width, height: size.height)
                } else {
                    ForEach(faces(in: size)) { f in
                        faceView(f)
                            .frame(width: f.w, height: f.h)
                            .modifier(Projected(t: f.m))
                    }
                    caption(size)
                }
            }
            .frame(width: size.width, height: size.height)
            .clipped()
            .contentShape(Rectangle())
            .gesture(drag(size))
        }
        .onAppear { sync() }
        .onChange(of: lib.albums.count) { _ in sync() }
        .onReceive(nav.events) { e in handle(e) }
    }

    private func sync() {
        m.count = lib.albums.count
        if m.count > 0 { m.setTarget(m.target) }
    }

    // MARK: input

    private func handle(_ e: WheelEvent) {
        guard nav.top == .coverFlow, !lib.albums.isEmpty else { return }
        let album = lib.albums[m.index]
        switch e {
        case .scroll(let d):
            if m.flipTarget > 0 {
                let n = max(0, min(album.tracks.count - 1, m.trackSel + d))
                m.trackSel = n
                if n < m.trackTop { m.trackTop = n }
                if n >= m.trackTop + 5 { m.trackTop = n - 4 }
            } else {
                m.go(by: d)
            }
        case .select:
            if m.flipTarget == 0 {
                m.flipOpen()
            } else if album.tracks.indices.contains(m.trackSel) {
                player.play(album.tracks, at: m.trackSel)
                nav.push(.nowPlaying)
            }
        }
    }

    private func drag(_ size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                guard m.flipTarget == 0, !lib.albums.isEmpty else { return }
                if dragStart == nil {
                    dragStart = m.pos
                    m.dragging = true
                    m.run()
                }
                if hypot(v.translation.width, v.translation.height) > 6, let s = dragStart {
                    let before = Int(m.pos.rounded())
                    m.dragTo(s - Double(v.translation.width / (30 * k)))
                    if Int(m.pos.rounded()) != before { Feedback.tick() }
                }
            }
            .onEnded { v in
                let moved = hypot(v.translation.width, v.translation.height)
                let started = dragStart != nil
                dragStart = nil
                if lib.albums.isEmpty { return }
                if m.flipTarget > 0 {
                    if moved < 8 { tapFlipped(v.location, size) }
                    return
                }
                m.dragging = false
                if moved < 8 {
                    tap(v.location, size)
                } else if started {
                    let fling = Double((v.predictedEndTranslation.width - v.translation.width) / (30 * k))
                    m.endDrag(extra: -fling * 0.6)
                }
            }
    }

    private func tap(_ p: CGPoint, _ size: CGSize) {
        let dx = Double((p.x - size.width / 2) / k)
        Feedback.tick()
        if abs(dx) < 50 { m.setTarget(m.target); m.flipOpen(); return }
        let s: Double = dx < 0 ? -1 : 1
        let steps = 1 + max(0, (abs(dx) - 68) / 27).rounded()
        m.setTarget(m.target + s * steps)
    }

    private func tapFlipped(_ p: CGPoint, _ size: CGSize) {
        let album = lib.albums[m.index]
        let left = size.width / 2 - 98 * k
        let topY = 4 * k
        guard p.x >= left, p.x <= left + 196 * k, p.y >= topY, p.y <= topY + 150 * k else {
            Feedback.tick(); m.unflip(); return
        }
        let row = Int(floor((p.y - topY - headerH) / rowH))
        let i = m.trackTop + row
        guard row >= 0, album.tracks.indices.contains(i) else { return }
        Feedback.tick()
        m.trackSel = i
        player.play(album.tracks, at: i)
        nav.push(.nowPlaying)
    }

    // MARK: geometry — each album is a CD jewel case (142 × 125 × 10 mm)

    private func faces(in size: CGSize) -> [CFFace] {
        let n = lib.albums.count
        guard n > 0 else { return [] }
        let T = 9 * k, W0 = 100 * k, H0 = 92 * k, W1 = 196 * k, H1 = 150 * k
        let D = 420 * k
        let cx = size.width / 2
        let flip = m.flip
        let center = m.index
        var out: [CFFace] = []
        var refl: [CFFace] = []
        let lo = max(0, Int(floor(m.pos)) - 6)
        let hi = min(n - 1, Int(ceil(m.pos)) + 6)
        guard lo <= hi else { return [] }

        for i in lo...hi {
            let d = Double(i) - m.pos
            if abs(d) > 6.5 { continue }
            let a = min(abs(d), 1)
            let s: Double = d < 0 ? -1 : 1
            let isC = i == center
            let f = isC ? flip * (1 - a) : 0
            let W = W0 + (W1 - W0) * CGFloat(f)
            let H = H0 + (H1 - H0) * CGFloat(f)
            let topY = 18 * k + (4 * k - 18 * k) * CGFloat(f)
            let cy = topY + H / 2
            let x = CGFloat(s * (68 * a + max(0, abs(d) - 1) * 27)) * k
            let z = CGFloat(24 * (1 - a) + 8 * f) * k
            let ang = CGFloat(-s * 66 * a * Double.pi / 180 + Double.pi * f)
            let caseM = CATransform3DConcat(rotY(ang), CATransform3DMakeTranslation(x, 0, z))
            var persp = CATransform3DIdentity
            persp.m34 = -1 / D
            let post = CATransform3DConcat(persp, CATransform3DMakeTranslation(cx, cy, 0))
            let alpha = isC ? 1.0 : (1 - 0.88 * flip)

            func add(_ kind: CFFace.Kind, _ fw: CGFloat, _ fh: CGFloat, _ local: CATransform3D) {
                let m0 = CATransform3DConcat(local, caseM)
                let p = apply(m0, 0, 0, 0, 1)
                let nrm = apply(m0, 0, 0, 1, 0)
                let tx = -p.x, ty = -p.y, tz = D - p.z
                let facing = nrm.x * tx + nrm.y * ty + nrm.z * tz
                guard facing > 0 else { return }
                let full = cat(CATransform3DMakeTranslation(-fw / 2, -fh / 2, 0), m0, post)
                let dist = sqrt(tx * tx + ty * ty + tz * tz)
                let face = CFFace(id: "\(i)-\(kind.rawValue)", kind: kind, album: i, w: fw, h: fh,
                                  m: full, depth: dist, alpha: alpha)
                if kind == .reflection { refl.append(face) } else { out.append(face) }
            }

            add(.front, W, H, CATransform3DMakeTranslation(0, 0, T / 2))
            if isC && f > 0.02 {
                add(.back, W, H, CATransform3DConcat(CATransform3DMakeTranslation(0, 0, T / 2), rotY(.pi)))
            }
            add(.spine, T, H, CATransform3DConcat(CATransform3DMakeTranslation(0, 0, W / 2), rotY(-.pi / 2)))
            add(.edge, T, H, CATransform3DConcat(CATransform3DMakeTranslation(0, 0, W / 2), rotY(.pi / 2)))
            add(.top, W, T, CATransform3DConcat(CATransform3DMakeTranslation(0, 0, H / 2), rotX(.pi / 2)))
            add(.bottom, W, T, CATransform3DConcat(CATransform3DMakeTranslation(0, 0, H / 2), rotX(-.pi / 2)))
            if f < 0.5 {
                add(.reflection, W, H, cat(CATransform3DMakeTranslation(0, 0, T / 2),
                                           CATransform3DMakeScale(1, -1, 1),
                                           CATransform3DMakeTranslation(0, H + 2 * k, 0)))
            }
        }
        out.sort { $0.depth > $1.depth }
        refl.sort { $0.depth > $1.depth }
        return refl + out
    }

    @ViewBuilder
    private func faceView(_ f: CFFace) -> some View {
        let al = lib.albums[f.album]
        switch f.kind {
        case .front:
            CaseFront(album: al, k: k).opacity(f.alpha)
        case .reflection:
            CaseFront(album: al, k: k)
                .overlay(LinearGradient(colors: [Color.black, Color.black.opacity(0.62)], startPoint: .top, endPoint: .bottom))
                .opacity(f.alpha)
        case .back:
            TrackPanel(album: al, sel: m.trackSel, top: m.trackTop, k: k, headerH: headerH, rowH: rowH)
        case .spine:
            spineColor(al)
                .overlay(
                    Text("\(al.artist)  ·  \(al.name)")
                        .font(.system(size: 5.5 * k, weight: .bold))
                        .foregroundColor(spineTextColor(al))
                        .lineLimit(1)
                        .fixedSize()
                        .rotationEffect(.degrees(90))
                )
                .clipped()
                .overlay(Rectangle().stroke(Color.white.opacity(0.22), lineWidth: 0.5))
                .opacity(f.alpha)
        case .edge:
            LinearGradient(colors: [Color(hex: "D6DDE4"), Color(hex: "969EA8"), Color(hex: "E9EDF1"),
                                    Color(hex: "8C949E"), Color(hex: "CDD4DC")],
                           startPoint: .leading, endPoint: .trailing)
                .opacity(f.alpha)
        case .top:
            LinearGradient(colors: [Color(hex: "D3D9DF"), Color(hex: "8F98A2")], startPoint: .top, endPoint: .bottom)
                .opacity(f.alpha)
        case .bottom:
            LinearGradient(colors: [Color(hex: "6F7882"), Color(hex: "3B4148")], startPoint: .top, endPoint: .bottom)
                .opacity(f.alpha)
        }
    }

    private func caption(_ size: CGSize) -> some View {
        let i = max(0, min(lib.albums.count - 1, Int(m.pos.rounded())))
        let al = lib.albums[i]
        return VStack(spacing: 1 * k) {
            Text(al.name).font(.system(size: 12.5 * k, weight: .bold)).lineLimit(1)
            Text(al.artist).font(.system(size: 11 * k)).foregroundColor(Color(hex: "A9ADB5")).lineLimit(1)
        }
        .foregroundColor(.white)
        .frame(width: size.width - 16 * k)
        .position(x: size.width / 2, y: size.height - 22 * k)
        .opacity(max(0, 1 - m.flip * 1.5))
    }
}

// MARK: - Case faces

struct CaseFront: View {
    let album: Album
    let k: CGFloat

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            ZStack(alignment: .topLeading) {
                Color(hex: "20242A")
                AlbumArt(file: album.coverFile, name: album.name, artist: album.artist)
                    .frame(width: w * 0.92, height: h)
                    .clipped()
                    .offset(x: w * 0.08)
                // hinge strip with molded ridges
                ZStack {
                    LinearGradient(colors: [Color(hex: "3C424A"), Color(hex: "14171B")], startPoint: .leading, endPoint: .trailing)
                    HStack(spacing: w * 0.008) {
                        ForEach(0..<4, id: \.self) { _ in
                            Rectangle().fill(Color.white.opacity(0.2)).frame(width: max(0.5, w * 0.006))
                        }
                    }
                }
                .frame(width: w * 0.08, height: h)
                .overlay(Rectangle().fill(Color.white.opacity(0.35)).frame(width: 0.5), alignment: .trailing)
                // plastic sheen
                LinearGradient(stops: [.init(color: .white.opacity(0.42), location: 0),
                                       .init(color: .white.opacity(0.1), location: 0.34),
                                       .init(color: .clear, location: 0.35),
                                       .init(color: .clear, location: 0.72),
                                       .init(color: .white.opacity(0.08), location: 1)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                    .allowsHitTesting(false)
            }
            .overlay(Rectangle().stroke(Color.white.opacity(0.28), lineWidth: 1))
        }
    }
}

struct TrackPanel: View {
    let album: Album
    let sel: Int
    let top: Int
    let k: CGFloat
    let headerH: CGFloat
    let rowH: CGFloat

    var body: some View {
        let start = max(0, min(top, album.tracks.count))
        let end = min(album.tracks.count, start + 5)
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 1 * k) {
                Text(album.name).font(.system(size: 11.5 * k, weight: .bold)).lineLimit(1)
                Text("\(album.artist) · \(album.tracks.count) 首").font(.system(size: 10.5 * k))
                    .foregroundColor(Color(white: 0.33)).lineLimit(1)
            }
            .padding(.horizontal, 8 * k)
            .frame(maxWidth: .infinity, minHeight: headerH, maxHeight: headerH, alignment: .leading)
            .background(LinearGradient(colors: [.white, Color(hex: "D6DBE1")], startPoint: .top, endPoint: .bottom))
            .overlay(Rectangle().fill(Color(hex: "A3AAB3")).frame(height: 1), alignment: .bottom)

            ForEach(start..<end, id: \.self) { i in
                let t = album.tracks[i]
                let on = i == sel
                HStack(spacing: 6 * k) {
                    Text(t.title).lineLimit(1)
                    Spacer(minLength: 4 * k)
                    Text(fmt(t.duration)).monospacedDigit()
                        .foregroundColor(on ? Color.white.opacity(0.88) : Color(white: 0.4))
                }
                .font(.system(size: 11 * k))
                .padding(.horizontal, 8 * k)
                .frame(height: rowH)
                .foregroundColor(on ? .white : .black)
                .background(on ? AnyView(podSelection) : AnyView(Color.clear))
            }
            Spacer(minLength: 0)
        }
        .background(LinearGradient(colors: [Color(hex: "F7F8FA"), Color(hex: "DFE3E8")], startPoint: .top, endPoint: .bottom))
        .overlay(Rectangle().stroke(Color(hex: "777777"), lineWidth: 1))
    }
}
