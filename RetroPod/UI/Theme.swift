import SwiftUI

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        let v = UInt64(s, radix: 16) ?? 0x2B2F35
        self.init(red: Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255)
    }
}

func hexLuminance(_ hex: String) -> Double {
    let v = UInt64(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0
    return (Double((v >> 16) & 0xFF) * 0.299 + Double((v >> 8) & 0xFF) * 0.587 + Double(v & 0xFF) * 0.114) / 255
}

let podSelection = LinearGradient(colors: [Color(hex: "6CB7F5"), Color(hex: "1D6FD6")], startPoint: .top, endPoint: .bottom)

struct PodTheme {
    let bodyColors: [Color]
    let bezel: Color
    let wheelColors: [Color]
    let wheelEdge: Color
    let label: Color
    let centerColors: [Color]
    let centerEdge: Color
    let dark: Bool

    static let names = ["white", "black", "u2"]
    static let displayNames = ["white": "经典白", "black": "黑色", "u2": "U2 特别版"]

    static func named(_ n: String) -> PodTheme {
        switch n {
        case "black":
            return PodTheme(bodyColors: [Color(hex: "36373A"), Color(hex: "141517"), Color(hex: "0A0A0B")],
                            bezel: .black,
                            wheelColors: [Color(hex: "3A3B3F"), Color(hex: "26272A")],
                            wheelEdge: Color(hex: "0D0D0E"), label: Color(hex: "8D9096"),
                            centerColors: [Color(hex: "222325"), Color(hex: "121314")],
                            centerEdge: .black, dark: true)
        case "u2":
            return PodTheme(bodyColors: [Color(hex: "2C2D30"), Color(hex: "0E0E0F"), Color(hex: "050505")],
                            bezel: .black,
                            wheelColors: [Color(hex: "E2263F"), Color(hex: "A80D24")],
                            wheelEdge: Color(hex: "5E0613"), label: Color(hex: "3A0610"),
                            centerColors: [Color(hex: "1C1C1E"), Color(hex: "0B0B0C")],
                            centerEdge: .black, dark: true)
        default:
            return PodTheme(bodyColors: [Color(hex: "FDFDFE"), Color(hex: "E6E8EC"), Color(hex: "D8DBE0")],
                            bezel: Color(hex: "D5D8DD"),
                            wheelColors: [Color(hex: "FFFFFF"), Color(hex: "EEF0F3")],
                            wheelEdge: Color(hex: "CFD3D9"), label: Color(hex: "A4A9B1"),
                            centerColors: [Color(hex: "F8F9FA"), Color(hex: "E3E6EA")],
                            centerEdge: Color(hex: "CBCFD5"), dark: false)
        }
    }
}

/// Album cover, or a generated one when the file has no artwork.
struct AlbumArt: View {
    let file: String?
    let name: String
    let artist: String
    @EnvironmentObject var lib: Library

    var body: some View {
        if let img = lib.coverImage(file) {
            Image(uiImage: img).resizable().scaledToFill()
        } else {
            PlaceholderArt(name: name, artist: artist)
        }
    }
}

func placeholderHue(_ name: String, _ artist: String) -> Double {
    Double(stableHash(name + artist) % 360) / 360
}

struct PlaceholderArt: View {
    let name: String
    let artist: String

    var body: some View {
        GeometryReader { g in
            let h = placeholderHue(name, artist)
            let w = g.size.width
            ZStack(alignment: .bottomLeading) {
                LinearGradient(colors: [Color(hue: h, saturation: 0.55, brightness: 0.32),
                                        Color(hue: (h + 0.1).truncatingRemainder(dividingBy: 1), saturation: 0.7, brightness: 0.72)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle()
                    .fill(Color(hue: (h + 0.5).truncatingRemainder(dividingBy: 1), saturation: 0.55, brightness: 0.95).opacity(0.85))
                    .frame(width: w * 0.55, height: w * 0.55)
                    .position(x: w * 0.64, y: g.size.height * 0.38)
                VStack(alignment: .leading, spacing: 1) {
                    Text(artist.uppercased()).font(.system(size: max(4, w * 0.07), weight: .semibold)).lineLimit(1)
                    Text(name).font(.system(size: max(5, w * 0.11), weight: .heavy)).lineLimit(2)
                }
                .foregroundColor(.white)
                .padding(w * 0.07)
            }
        }
    }
}

func spineColor(_ a: Album) -> Color {
    if let h = a.spineHex { return Color(hex: h) }
    return Color(hue: placeholderHue(a.name, a.artist), saturation: 0.55, brightness: 0.32)
}

func spineTextColor(_ a: Album) -> Color {
    if let h = a.spineHex { return hexLuminance(h) > 0.55 ? Color(hex: "141414") : .white }
    return .white
}
