import SwiftUI

struct MenuItem {
    let label: String
    var value: String? = nil
    var arrow = false
    let action: () -> Void
}

struct MenuList: View {
    let screen: Screen
    let items: [MenuItem]
    let k: CGFloat
    var empty = "这里还没有内容"
    @EnvironmentObject var nav: Navigator

    var body: some View {
        let st = nav.listState(screen)
        let v = Navigator.visibleRows
        let sel = min(st.sel, max(0, items.count - 1))
        let top = max(0, min(st.top, max(0, items.count - v)))
        let end = min(items.count, top + v)
        ZStack(alignment: .topLeading) {
            Color.white
            if items.isEmpty {
                Text(empty)
                    .font(.system(size: 12 * k))
                    .foregroundColor(Color(hex: "6B7280"))
                    .multilineTextAlignment(.center)
                    .padding(16 * k)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            VStack(spacing: 0) {
                ForEach(top..<end, id: \.self) { i in
                    row(items[i], selected: i == sel)
                        .onTapGesture {
                            nav.setListSel(screen, i, count: items.count)
                            Feedback.tick()
                            items[i].action()
                        }
                }
            }
            .padding(.trailing, items.count > v ? 10 * k : 0)
            if items.count > v {
                scrollbar(top: top, count: items.count, visible: v)
            }
        }
        .onReceive(nav.events) { e in
            guard nav.top == screen else { return }
            switch e {
            case .scroll(let d):
                nav.moveList(screen, count: items.count, by: d)
            case .select:
                let s = min(nav.listState(screen).sel, items.count - 1)
                if items.indices.contains(s) { items[s].action() }
            }
        }
    }

    private func row(_ it: MenuItem, selected: Bool) -> some View {
        HStack(spacing: 6 * k) {
            Text(it.label).lineLimit(1)
            Spacer(minLength: 4 * k)
            if let v = it.value {
                Text(v)
                    .font(.system(size: 12 * k))
                    .monospacedDigit()
                    .foregroundColor(selected ? Color.white.opacity(0.88) : Color(hex: "6B7280"))
            }
            if it.arrow {
                Image(systemName: "chevron.right").font(.system(size: 11 * k, weight: .heavy))
            }
        }
        .font(.system(size: 13 * k))
        .padding(.horizontal, 8 * k)
        .frame(maxWidth: .infinity)
        .frame(height: 25 * k)
        .foregroundColor(selected ? .white : .black)
        .background(selected ? AnyView(podSelection) : AnyView(Color.white))
        .contentShape(Rectangle())
    }

    private func scrollbar(top: Int, count: Int, visible: Int) -> some View {
        GeometryReader { g in
            let h = g.size.height - 6 * k
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 3 * k).stroke(Color(hex: "9AA1AA"), lineWidth: 1)
                RoundedRectangle(cornerRadius: 2 * k)
                    .fill(LinearGradient(colors: [Color(hex: "A7CDF6"), Color(hex: "3B80D9")], startPoint: .leading, endPoint: .trailing))
                    .frame(height: h * CGFloat(visible) / CGFloat(count))
                    .offset(y: h * CGFloat(top) / CGFloat(count))
            }
            .frame(width: 6 * k, height: h)
            .position(x: g.size.width - 5 * k, y: g.size.height / 2)
        }
    }
}

struct InfoView: View {
    let k: CGFloat
    var body: some View {
        VStack(alignment: .leading, spacing: 6 * k) {
            HStack {
                Text("Spotify").font(.system(size: 14 * k, weight: .bold))
                Spacer()
                Image(systemName: "music.note")
                    .font(.system(size: 13 * k, weight: .bold))
                    .foregroundColor(.black)
                    .frame(width: 28 * k, height: 28 * k)
                    .background(Circle().fill(Color(hex: "1ED760")))
            }
            Text("Spotify 会在后续版本接入：连接你的账户后，可以浏览歌单和专辑封面，用转盘遥控 Spotify 播放。")
                .font(.system(size: 12 * k))
                .foregroundColor(Color(white: 0.2))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14 * k)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(LinearGradient(colors: [.white, Color(hex: "EEF1F4")], startPoint: .top, endPoint: .bottom))
        .foregroundColor(.black)
    }
}

struct ScreenView: View {
    let screen: Screen
    let k: CGFloat
    @EnvironmentObject var lib: Library
    @EnvironmentObject var player: Player
    @EnvironmentObject var nav: Navigator
    @AppStorage("theme") private var theme = "white"
    @AppStorage("shuffle") private var shuffle = false
    @AppStorage("repeatMode") private var repeatMode = "off"
    @AppStorage("clicks") private var clicks = true

    private let noMusic = "还没有音乐\n在主菜单选「导入音乐」，\n或用「文件」App 把歌放进\n「我的 iPhone › iPod」"

    var body: some View {
        switch screen {
        case .coverFlow:
            CoverFlowView(m: nav.cover, k: k)
        case .nowPlaying:
            NowPlayingView(k: k)
        case .spotify:
            InfoView(k: k)
        default:
            MenuList(screen: screen, items: items(), k: k, empty: emptyText())
        }
    }

    private func emptyText() -> String {
        switch screen {
        case .mostPlayed, .recent: return "播放过的歌曲会出现在这里"
        default: return noMusic
        }
    }

    private func trackItems(_ tr: [Track]) -> [MenuItem] {
        tr.enumerated().map { pair in
            MenuItem(label: pair.element.title, value: fmt(pair.element.duration)) {
                player.play(tr, at: pair.offset)
                nav.push(.nowPlaying)
            }
        }
    }

    private func albumItems(_ list: [Album]) -> [MenuItem] {
        list.map { a in MenuItem(label: a.name, arrow: true) { nav.push(.albumTracks(a.id)) } }
    }

    private func items() -> [MenuItem] {
        switch screen {
        case .main:
            var a: [MenuItem] = [
                MenuItem(label: "Cover Flow", arrow: true) { nav.push(.coverFlow) },
                MenuItem(label: "音乐", arrow: true) { nav.push(.music) },
                MenuItem(label: "Spotify", arrow: true) { nav.push(.spotify) },
                MenuItem(label: "随机播放歌曲") {
                    if lib.tracks.isEmpty {
                        lib.message = "资料库是空的，先导入音乐"
                    } else {
                        player.playShuffled(lib.tracks)
                        nav.push(.nowPlaying)
                    }
                },
                MenuItem(label: "导入音乐", arrow: true) { nav.showImporter = true },
                MenuItem(label: "设置", arrow: true) { nav.push(.settings) }
            ]
            if player.current != nil {
                a.append(MenuItem(label: "正在播放", arrow: true) { nav.push(.nowPlaying) })
            }
            return a
        case .music:
            return [
                MenuItem(label: "专辑", arrow: true) { nav.push(.albums) },
                MenuItem(label: "艺人", arrow: true) { nav.push(.artists) },
                MenuItem(label: "歌曲", arrow: true) { nav.push(.songs) },
                MenuItem(label: "播放列表", arrow: true) { nav.push(.playlists) }
            ]
        case .albums:
            return albumItems(lib.albums)
        case .artists:
            return lib.artists.map { n in MenuItem(label: n, arrow: true) { nav.push(.artistAlbums(n)) } }
        case .artistAlbums(let n):
            return albumItems(lib.albums.filter { $0.artist == n })
        case .albumTracks(let id):
            return trackItems(lib.albums.first { $0.id == id }?.tracks ?? [])
        case .songs:
            return trackItems(lib.tracks.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending })
        case .playlists:
            return [
                MenuItem(label: "最常播放", arrow: true) { nav.push(.mostPlayed) },
                MenuItem(label: "最近播放", arrow: true) { nav.push(.recent) }
            ]
        case .mostPlayed:
            return trackItems(Array(lib.tracks.filter { $0.playCount > 0 }.sorted { $0.playCount > $1.playCount }.prefix(25)))
        case .recent:
            return trackItems(Array(lib.tracks.filter { $0.lastPlayed != nil }
                .sorted { ($0.lastPlayed ?? .distantPast) > ($1.lastPlayed ?? .distantPast) }.prefix(25)))
        case .settings:
            return [
                MenuItem(label: "机身外观", value: PodTheme.displayNames[theme] ?? "经典白") {
                    let n = PodTheme.names
                    theme = n[((n.firstIndex(of: theme) ?? 0) + 1) % n.count]
                },
                MenuItem(label: "随机播放", value: shuffle ? "歌曲" : "关") { shuffle.toggle() },
                MenuItem(label: "重复", value: ["off": "关", "one": "一首", "all": "全部"][repeatMode] ?? "关") {
                    repeatMode = ["off": "all", "all": "one", "one": "off"][repeatMode] ?? "off"
                },
                MenuItem(label: "点按声", value: clicks ? "开" : "关") { clicks.toggle() },
                MenuItem(label: "关于", arrow: true) { nav.push(.about) }
            ]
        case .about:
            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1"
            return [
                MenuItem(label: "歌曲", value: "\(lib.tracks.count)") {},
                MenuItem(label: "专辑", value: "\(lib.albums.count)") {},
                MenuItem(label: "艺人", value: "\(lib.artists.count)") {},
                MenuItem(label: "版本", value: version) {}
            ]
        default:
            return []
        }
    }
}
