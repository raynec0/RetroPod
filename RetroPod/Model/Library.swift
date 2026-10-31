import Foundation
import AVFoundation
import UIKit

struct Track: Codable, Identifiable, Hashable {
    var id: UUID
    var fileName: String
    var title: String
    var artist: String
    var album: String
    var trackNumber: Int
    var duration: Double
    var coverFile: String?
    var spineHex: String?
    var playCount: Int
    var lastPlayed: Date?
    var addedAt: Date
}

struct Album: Identifiable, Hashable {
    let id: String
    let name: String
    let artist: String
    var tracks: [Track]
    var coverFile: String?
    var spineHex: String?
}

func stableHash(_ s: String) -> UInt32 {
    var h: UInt32 = 2166136261
    for b in s.utf8 { h ^= UInt32(b); h = h &* 16777619 }
    return h
}

func fmt(_ s: Double) -> String {
    guard s.isFinite, s > 0 else { return "0:00" }
    let i = Int(s)
    return "\(i / 60):" + String(format: "%02d", i % 60)
}

final class Library: ObservableObject {
    static let shared = Library()

    @Published private(set) var tracks: [Track] = []
    @Published private(set) var albums: [Album] = []
    @Published var busy = false
    @Published var message: String? = nil

    let docs: URL
    let musicDir: URL
    let coverDir: URL
    let dbURL: URL
    private let cache = NSCache<NSString, UIImage>()

    static let audioExts: Set<String> = ["mp3", "m4a", "aac", "wav", "aif", "aiff", "aifc", "flac", "caf", "m4b", "alac", "mp4"]

    init() {
        let fm = FileManager.default
        docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        musicDir = docs.appendingPathComponent("Music", isDirectory: true)
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        coverDir = support.appendingPathComponent("Covers", isDirectory: true)
        dbURL = support.appendingPathComponent("library.json")
        try? fm.createDirectory(at: musicDir, withIntermediateDirectories: true)
        try? fm.createDirectory(at: coverDir, withIntermediateDirectories: true)
        load()
        Task { await self.scan() }
    }

    // MARK: storage

    private func load() {
        guard let data = try? Data(contentsOf: dbURL),
              let list = try? JSONDecoder().decode([Track].self, from: data) else { return }
        tracks = list
        rebuild()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(tracks) {
            try? data.write(to: dbURL, options: .atomic)
        }
    }

    private func rebuild() {
        var order: [String] = []
        var map: [String: Album] = [:]
        for t in tracks {
            let key = t.album + "\u{1}" + t.artist
            if map[key] == nil {
                order.append(key)
                map[key] = Album(id: key, name: t.album, artist: t.artist, tracks: [], coverFile: nil, spineHex: nil)
            }
            map[key]!.tracks.append(t)
            if map[key]!.coverFile == nil, let c = t.coverFile {
                map[key]!.coverFile = c
                map[key]!.spineHex = t.spineHex
            }
        }
        albums = order.compactMap { map[$0] }
            .map { a -> Album in
                var a = a
                a.tracks.sort { ($0.trackNumber, $0.title) < ($1.trackNumber, $1.title) }
                return a
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    // MARK: lookups

    var artists: [String] {
        Array(Set(albums.map { $0.artist })).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    func url(for t: Track) -> URL { musicDir.appendingPathComponent(t.fileName) }

    func coverFile(for t: Track) -> String? {
        t.coverFile ?? albums.first { $0.name == t.album && $0.artist == t.artist }?.coverFile
    }

    func coverImage(_ file: String?) -> UIImage? {
        guard let file = file else { return nil }
        if let img = cache.object(forKey: file as NSString) { return img }
        guard let img = UIImage(contentsOfFile: coverDir.appendingPathComponent(file).path) else { return nil }
        cache.setObject(img, forKey: file as NSString)
        return img
    }

    func recordPlay(_ id: UUID) {
        guard let i = tracks.firstIndex(where: { $0.id == id }) else { return }
        tracks[i].playCount += 1
        tracks[i].lastPlayed = Date()
        save()
    }

    // MARK: import

    func importFiles(_ urls: [URL]) {
        Task { await self.importURLs(urls) }
    }

    @MainActor
    func importURLs(_ urls: [URL]) async {
        busy = true
        message = "正在导入…"
        var added = 0
        for u in urls {
            let ok = u.startAccessingSecurityScopedResource()
            defer { if ok { u.stopAccessingSecurityScopedResource() } }
            guard Library.audioExts.contains(u.pathExtension.lowercased()) else { continue }
            let dest = uniqueDestination(for: u.lastPathComponent)
            do { try FileManager.default.copyItem(at: u, to: dest) } catch { continue }
            if let t = await makeTrack(fileName: dest.lastPathComponent) {
                tracks.append(t)
                added += 1
            }
        }
        rebuild()
        save()
        busy = false
        message = added > 0 ? "已导入 \(added) 首歌曲" : "没有可以导入的音频文件"
    }

    /// Picks up files the user dropped in with the Files app, and drops entries whose files were deleted.
    @MainActor
    func scan() async {
        let fm = FileManager.default
        if let root = try? fm.contentsOfDirectory(at: docs, includingPropertiesForKeys: nil) {
            for u in root where Library.audioExts.contains(u.pathExtension.lowercased()) {
                try? fm.moveItem(at: u, to: uniqueDestination(for: u.lastPathComponent))
            }
        }
        let files = (try? fm.contentsOfDirectory(atPath: musicDir.path)) ?? []
        let fileSet = Set(files)
        var changed = false
        let before = tracks.count
        tracks.removeAll { !fileSet.contains($0.fileName) }
        if tracks.count != before { changed = true }
        let known = Set(tracks.map { $0.fileName })
        var added = 0
        for f in files.sorted() where !known.contains(f) && Library.audioExts.contains((f as NSString).pathExtension.lowercased()) {
            if let t = await makeTrack(fileName: f) {
                tracks.append(t)
                added += 1
                changed = true
            }
        }
        if changed { rebuild(); save() }
        if added > 0 { message = "找到 \(added) 首新歌曲" }
    }

    private func uniqueDestination(for name: String) -> URL {
        let fm = FileManager.default
        var url = musicDir.appendingPathComponent(name)
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var n = 2
        while fm.fileExists(atPath: url.path) {
            url = musicDir.appendingPathComponent("\(base) \(n).\(ext)")
            n += 1
        }
        return url
    }

    private func clean(_ s: String?) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }

    @MainActor
    private func makeTrack(fileName: String) async -> Track? {
        let url = musicDir.appendingPathComponent(fileName)
        let asset = AVURLAsset(url: url)
        var title: String? = nil
        var artist: String? = nil
        var album: String? = nil
        var art: Data? = nil
        var number = 0

        if let items = try? await asset.load(.commonMetadata) {
            for item in items {
                guard let key = item.commonKey else { continue }
                if key == .commonKeyTitle {
                    title = try? await item.load(.stringValue)
                } else if key == .commonKeyArtist {
                    artist = try? await item.load(.stringValue)
                } else if key == .commonKeyAlbumName {
                    album = try? await item.load(.stringValue)
                } else if key == .commonKeyArtwork, art == nil {
                    art = try? await item.load(.dataValue)
                }
            }
        }
        if let items = try? await asset.load(.metadata) {
            for item in items {
                if item.identifier == .id3MetadataTrackNumber, let s = try? await item.load(.stringValue) {
                    let first = s.split(separator: "/").first.map(String.init) ?? ""
                    number = Int(first.trimmingCharacters(in: .whitespaces)) ?? number
                } else if item.identifier == .iTunesMetadataTrackNumber, let d = try? await item.load(.dataValue) {
                    let b = [UInt8](d)
                    if b.count >= 4 { number = Int(b[2]) << 8 | Int(b[3]) }
                }
            }
        }
        var duration: Double = 0
        if let d = try? await asset.load(.duration), d.seconds.isFinite { duration = d.seconds }

        var coverFile: String? = nil
        var spine: String? = nil
        if let art = art, let img = UIImage(data: art) {
            let small = img.resized(maxSide: 600)
            let name = UUID().uuidString + ".jpg"
            if let jpg = small.jpegData(compressionQuality: 0.85) {
                try? jpg.write(to: coverDir.appendingPathComponent(name))
                coverFile = name
                spine = small.averageHex()
            }
        }
        let base = (fileName as NSString).deletingPathExtension
        return Track(id: UUID(), fileName: fileName,
                     title: clean(title) ?? base,
                     artist: clean(artist) ?? "未知艺人",
                     album: clean(album) ?? "未知专辑",
                     trackNumber: number, duration: duration,
                     coverFile: coverFile, spineHex: spine,
                     playCount: 0, lastPlayed: nil, addedAt: Date())
    }
}

extension UIImage {
    func resized(maxSide: CGFloat) -> UIImage {
        let s = max(size.width, size.height)
        guard s > maxSide else { return self }
        let r = maxSide / s
        let ns = CGSize(width: size.width * r, height: size.height * r)
        let f = UIGraphicsImageRendererFormat()
        f.scale = 1
        return UIGraphicsImageRenderer(size: ns, format: f).image { _ in
            self.draw(in: CGRect(origin: .zero, size: ns))
        }
    }

    /// Average color of the cover, darkened a little, for the jewel-case spine.
    func averageHex() -> String {
        guard let cg = cgImage else { return "2B2F35" }
        var px = [UInt8](repeating: 0, count: 8 * 8 * 4)
        let ok: Bool = px.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 32,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 8, height: 8))
            return true
        }
        guard ok else { return "2B2F35" }
        var r = 0, g = 0, b = 0
        for i in stride(from: 0, to: px.count, by: 4) {
            r += Int(px[i]); g += Int(px[i + 1]); b += Int(px[i + 2])
        }
        return String(format: "%02X%02X%02X", r / 64 * 8 / 10, g / 64 * 8 / 10, b / 64 * 8 / 10)
    }
}
