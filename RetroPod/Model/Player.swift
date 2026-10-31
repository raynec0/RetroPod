import Foundation
import AVFoundation
import MediaPlayer
import UIKit

final class Player: NSObject, ObservableObject, AVAudioPlayerDelegate {
    static let shared = Player()

    @Published private(set) var queue: [Track] = []
    @Published private(set) var index: Int = 0
    @Published private(set) var isPlaying = false
    @Published var volume: Float = (UserDefaults.standard.object(forKey: "volume") as? Float) ?? 0.8 {
        didSet {
            audio?.volume = volume
            UserDefaults.standard.set(volume, forKey: "volume")
        }
    }

    private var audio: AVAudioPlayer?

    var current: Track? { queue.indices.contains(index) ? queue[index] : nil }
    var currentTime: Double { audio?.currentTime ?? 0 }
    var duration: Double {
        if let a = audio, a.duration > 0 { return a.duration }
        return current?.duration ?? 0
    }

    private var shuffleOn: Bool { UserDefaults.standard.bool(forKey: "shuffle") }
    private var repeatMode: String { UserDefaults.standard.string(forKey: "repeatMode") ?? "off" }

    func setup() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.addTarget { [weak self] _ in self?.resume(); return .success }
        c.pauseCommand.addTarget { [weak self] _ in self?.pause(); return .success }
        c.togglePlayPauseCommand.addTarget { [weak self] _ in self?.toggle(); return .success }
        c.nextTrackCommand.addTarget { [weak self] _ in self?.next(); return .success }
        c.previousTrackCommand.addTarget { [weak self] _ in self?.previous(); return .success }
        c.changePlaybackPositionCommand.addTarget { [weak self] e in
            if let e = e as? MPChangePlaybackPositionCommandEvent { self?.seek(e.positionTime) }
            return .success
        }
        NotificationCenter.default.addObserver(self, selector: #selector(interrupted(_:)),
                                               name: AVAudioSession.interruptionNotification, object: nil)
    }

    @objc private func interrupted(_ n: Notification) {
        guard let raw = n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw), type == .began else { return }
        DispatchQueue.main.async {
            self.isPlaying = false
            self.updateInfo()
        }
    }

    // MARK: queue

    func play(_ list: [Track], at i: Int) {
        guard list.indices.contains(i) else { return }
        var q = list
        var idx = i
        if shuffleOn {
            let first = q.remove(at: i)
            q.shuffle()
            q.insert(first, at: 0)
            idx = 0
        }
        queue = q
        index = idx
        start(at: 0, autoplay: true)
    }

    func playShuffled(_ list: [Track]) {
        guard !list.isEmpty else { return }
        queue = list.shuffled()
        index = 0
        start(at: 0, autoplay: true)
    }

    private func start(at time: Double, autoplay: Bool) {
        audio?.stop()
        audio = nil
        guard let t = current else { isPlaying = false; updateInfo(); return }
        do {
            let a = try AVAudioPlayer(contentsOf: Library.shared.url(for: t))
            a.delegate = self
            a.volume = volume
            a.prepareToPlay()
            a.currentTime = time
            audio = a
            if autoplay {
                try? AVAudioSession.sharedInstance().setActive(true)
                a.play()
                isPlaying = true
                Library.shared.recordPlay(t.id)
            } else {
                isPlaying = false
            }
        } catch {
            isPlaying = false
            Library.shared.message = "无法播放「\(t.title)」"
        }
        updateInfo()
    }

    // MARK: transport

    func resume() {
        guard let a = audio else { toggle(); return }
        try? AVAudioSession.sharedInstance().setActive(true)
        a.play()
        isPlaying = true
        updateInfo()
    }

    func pause() {
        audio?.pause()
        isPlaying = false
        updateInfo()
    }

    func toggle() {
        if audio == nil {
            if current != nil { start(at: 0, autoplay: true) }
            else if let a = Library.shared.albums.first { play(a.tracks, at: 0) }
            return
        }
        if isPlaying { pause() } else { resume() }
    }

    private func go(_ i: Int) {
        let was = isPlaying
        index = i
        start(at: 0, autoplay: was)
    }

    func next(auto: Bool = false) {
        guard !queue.isEmpty else { return }
        if auto && repeatMode == "one" { start(at: 0, autoplay: true); return }
        if index < queue.count - 1 {
            go(index + 1)
        } else if !auto || repeatMode == "all" {
            go(0)
        } else {
            audio?.stop()
            audio?.currentTime = 0
            isPlaying = false
            updateInfo()
        }
    }

    func previous() {
        guard !queue.isEmpty else { return }
        if currentTime > 3 { seek(0); return }
        go(max(0, index - 1))
    }

    func seek(_ t: Double) {
        guard let a = audio else { return }
        a.currentTime = max(0, min(t, max(0, a.duration - 0.5)))
        updateInfo()
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { self.next(auto: true) }
    }

    // MARK: lock screen

    func updateInfo() {
        guard let t = current else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: t.title,
            MPMediaItemPropertyArtist: t.artist,
            MPMediaItemPropertyAlbumTitle: t.album,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
        if let img = Library.shared.coverImage(Library.shared.coverFile(for: t)) {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: img.size) { _ in img }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
