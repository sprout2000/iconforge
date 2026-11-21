import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
@testable import IconForge

enum TestError: Error {
    case setup(String)
}

// MARK: - テスト用画像

struct RGBA: Equatable, CustomStringConvertible {
    var r: UInt8
    var g: UInt8
    var b: UInt8
    var a: UInt8

    static let red = RGBA(r: 255, g: 0, b: 0, a: 255)
    static let clear = RGBA(r: 0, g: 0, b: 0, a: 0)

    var description: String { "RGBA(\(r), \(g), \(b), \(a))" }
}

enum TestImage {
    /// ピクセルごとに色を指定して画像を作る（y = 0 が上の行、色はストレートアルファ）
    static func make(
        width: Int,
        height: Int,
        alpha: Bool = true,
        colorSpace: CGColorSpace = IconRenderer.sRGB,
        _ color: (_ x: Int, _ y: Int) -> RGBA
    ) -> CGImage {
        let info: CGImageAlphaInfo = alpha ? .premultipliedLast : .noneSkipLast
        let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: info.rawValue
        )!
        let buffer = ctx.data!.bindMemory(to: UInt8.self, capacity: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let c = color(x, y)
                let a = alpha ? c.a : 255
                let i = (y * width + x) * 4
                buffer[i] = premultiply(c.r, a)
                buffer[i + 1] = premultiply(c.g, a)
                buffer[i + 2] = premultiply(c.b, a)
                buffer[i + 3] = a
            }
        }
        return ctx.makeImage()!
    }

    /// 単色の画像
    static func solid(width: Int, height: Int, color: RGBA = .red, alpha: Bool = true) -> CGImage {
        make(width: width, height: height, alpha: alpha) { _, _ in color }
    }

    /// 左上の 1 ピクセルだけ透明な赤い正方形（PNG に確実にアルファを持たせるため）
    static func icon(size: Int, colorSpace: CGColorSpace = IconRenderer.sRGB) -> CGImage {
        make(width: size, height: size, colorSpace: colorSpace) { x, y in
            (x == 0 && y == 0) ? .clear : .red
        }
    }

    /// 画像を sRGB・プリマルチプライドの RGBA 配列にする（y = 0 が上の行）
    static func rgba(of image: CGImage) -> [UInt8] {
        let w = image.width
        let h = image.height
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        bytes.withUnsafeMutableBytes { buffer in
            let ctx = CGContext(
                data: buffer.baseAddress,
                width: w,
                height: h,
                bitsPerComponent: 8,
                bytesPerRow: w * 4,
                space: IconRenderer.sRGB,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return bytes
    }

    static func pixel(_ image: CGImage, x: Int, y: Int) -> RGBA {
        let bytes = rgba(of: image)
        let i = (y * image.width + x) * 4
        return RGBA(r: bytes[i], g: bytes[i + 1], b: bytes[i + 2], a: bytes[i + 3])
    }

    private static func premultiply(_ c: UInt8, _ a: UInt8) -> UInt8 {
        UInt8((Int(c) * Int(a) + 127) / 255)
    }
}

/// 2 つの色がほぼ同じか（縮小時の丸め誤差を許容）
func isClose(_ lhs: RGBA, _ rhs: RGBA, tolerance: Int = 2) -> Bool {
    abs(Int(lhs.r) - Int(rhs.r)) <= tolerance
        && abs(Int(lhs.g) - Int(rhs.g)) <= tolerance
        && abs(Int(lhs.b) - Int(rhs.b)) <= tolerance
        && abs(Int(lhs.a) - Int(rhs.a)) <= tolerance
}

// MARK: - 一時フォルダ

final class TempDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("IconForgeTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    func writePNG(_ image: CGImage, name: String = "icon.png") throws -> URL {
        let fileURL = url.appendingPathComponent(name)
        guard let dest = CGImageDestinationCreateWithURL(fileURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw TestError.setup("PNG の書き出し先を作れません")
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw TestError.setup("PNG を書き出せません")
        }
        return fileURL
    }

    func writeText(_ text: String, name: String) throws -> URL {
        let fileURL = url.appendingPathComponent(name)
        try Data(text.utf8).write(to: fileURL)
        return fileURL
    }

    func writeSVG(width: Int, height: Int, name: String = "icon.svg") throws -> URL {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="\(width)" height="\(height)" viewBox="0 0 \(width) \(height)">
          <rect width="\(width)" height="\(height)" fill="#ff0000"/>
        </svg>
        """
        return try writeText(svg, name: name)
    }
}

// MARK: - バイト列の読み取り

extension Array where Element == UInt8 {
    func le16(_ offset: Int) -> UInt16 {
        UInt16(self[offset]) | UInt16(self[offset + 1]) << 8
    }

    func le32(_ offset: Int) -> UInt32 {
        (0..<4).reduce(UInt32(0)) { $0 | UInt32(self[offset + $1]) << (8 * $1) }
    }

    func be32(_ offset: Int) -> UInt32 {
        (0..<4).reduce(UInt32(0)) { $0 << 8 | UInt32(self[offset + $1]) }
    }

    func ascii(_ offset: Int, _ length: Int) -> String {
        String(decoding: self[offset..<(offset + length)], as: UTF8.self)
    }

    func hasPNGSignature(at offset: Int) -> Bool {
        Array(self[offset..<(offset + 8)]) == [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
    }
}

/// ImageIO で読み込んで、含まれる画像の幅を返す
func imageWidths(in data: Data) -> [Int] {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return [] }
    return (0..<CGImageSourceGetCount(source)).compactMap {
        CGImageSourceCreateImageAtIndex(source, $0, nil)?.width
    }
}
