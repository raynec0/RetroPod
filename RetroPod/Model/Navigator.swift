import SwiftUI
import Combine
import UIKit
import AudioToolbox

enum Screen: Hashable {
    case main, music, albums, artists, songs, playlists, mostPlayed, recent
    case artistAlbums(String)
    case albumTracks(String)
    case coverFlow, nowPlaying, settings, about, spotify
}

enum WheelEvent {
    case scroll(Int)
    case select
}

struct ListState {
    var sel = 0
    var top = 0
}

final class Navigator: ObservableObject {
    @Published var stack: [Screen] = [.main]
    @Published var forward = true
    @Published var lists: [Screen: ListState] = [:]
    @Published var showImporter = false

    let events = PassthroughSubject<WheelEvent, Never>()
    let cover = CoverFlowModel()
    static let visibleRows = 7

    var top: Screen { stack.last ?? .main }

    func push(_ s: Screen) {
        forward = true
        withAnimation(.easeOut(duration: 0.24)) { stack.append(s) }
    }

    func pop() {
        guard stack.count > 1 else { return }
        forward = false
        withAnimation(.easeOut(duration: 0.24)) { _ = stack.removeLast() }
    }

    func menu() {
        if top == .coverFlow && cover.flipTarget > 0 { cover.unflip(); return }
        pop()
    }

    func listState(_ s: Screen) -> ListState { lists[s] ?? ListState() }

    func moveList(_ s: Screen, count: Int, by d: Int) {
        setListSel(s, listState(s).sel + d, count: count)
    }

    func setListSel(_ s: Screen, _ i: Int, count: Int) {
        guard count > 0 else { return }
        var st = listState(s)
        let n = max(0, min(count - 1, i))
        guard n != st.sel || lists[s] == nil else { return }
        st.sel = n
        let v = Navigator.visibleRows
        if st.sel < st.top { st.top = st.sel }
        if st.sel >= st.top + v { st.top = st.sel - v + 1 }
        lists[s] = st
    }
}

enum Feedback {
    static let gen = UISelectionFeedbackGenerator()
    static func tick() {
        gen.selectionChanged()
        let clicks = (UserDefaults.standard.object(forKey: "clicks") as? Bool) ?? true
        if clicks { AudioServicesPlaySystemSound(1104) }
    }
}

func screenTitle(_ s: Screen, _ lib: Library) -> String {
    switch s {
    case .main: return "iPod"
    case .music: return "音乐"
    case .albums: return "专辑"
    case .artists: return "艺人"
    case .songs: return "歌曲"
    case .playlists: return "播放列表"
    case .mostPlayed: return "最常播放"
    case .recent: return "最近播放"
    case .artistAlbums(let n): return n
    case .albumTracks(let id): return lib.albums.first { $0.id == id }?.name ?? "专辑"
    case .coverFlow: return "Cover Flow"
    case .nowPlaying: return "正在播放"
    case .settings: return "设置"
    case .about: return "关于"
    case .spotify: return "Spotify"
    }
}
