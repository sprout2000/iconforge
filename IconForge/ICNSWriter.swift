import CoreGraphics
import Foundation

/// macOS 用 ICNS を書き出す（全エントリを PNG で格納）
enum ICNSWriter {
    /// OSType とピクセルサイズ（@2x は同じピクセル数の画像を共有）
    static let entries: [(type: String, size: Int)] = [
        ("icp4", 16),    // 16
        ("icp5", 32),    // 32
        ("ic11", 32),    // 16@2x
        ("ic12", 64),    // 32@2x
        ("ic07", 128),   // 128
        ("ic13", 256),   // 128@2x
        ("ic08", 256),   // 256
        ("ic14", 512),   // 256@2x
        ("ic09", 512),   // 512
        ("ic10", 1024),  // 512@2x
    ]

    static var sizes: [Int] {
        Array(Set(entries.map(\.size))).sorted()
    }

    static func makeData(images: [Int: CGImage]) throws -> Data {
        var pngCache: [Int: Data] = [:]
        var body = Data()

        for entry in entries {
            let png: Data
            if let cached = pngCache[entry.size] {
                png = cached
            } else {
                guard let image = images[entry.size] else { throw IconWriteError.missingSize(entry.size) }
                guard let encoded = IconRenderer.pngData(image) else { throw IconWriteError.encodeFailed(entry.size) }
                pngCache[entry.size] = encoded
                png = encoded
            }
            body.append(contentsOf: Array(entry.type.utf8))
            body.appendBE(UInt32(png.count + 8))
            body.append(png)
        }

        var out = Data("icns".utf8)
        out.appendBE(UInt32(body.count + 8))
        out.append(body)
        return out
    }
}
