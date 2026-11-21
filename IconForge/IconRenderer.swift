import AppKit
import ImageIO
import UniformTypeIdentifiers

enum IconRenderer {
    static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    /// macOS のアイコン用グリッド（1024 のキャンバスに 824 の本体）
    static let macContentScale: CGFloat = 824.0 / 1024.0

    static func makeContext(width: Int, height: Int) -> CGContext? {
        CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: sRGB,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }

    /// 指定サイズの正方形アイコン画像を描画する
    /// - Parameter contentScale: 1.0 で全面、`macContentScale` で macOS 風の余白付き
    static func render(_ source: SourceContent, size: Int, contentScale: CGFloat = 1.0) -> CGImage? {
        guard let ctx = makeContext(width: size, height: size) else { return nil }

        let canvas = CGFloat(size)
        let body = canvas * contentScale
        let rect = CGRect(x: (canvas - body) / 2, y: (canvas - body) / 2, width: body, height: body)

        ctx.clear(CGRect(x: 0, y: 0, width: canvas, height: canvas))
        ctx.interpolationQuality = .high

        switch source {
        case .bitmap(let image):
            // 一気に縮小すると細部が潰れるので、半分ずつ縮小してから最終サイズへ
            let reduced = downsample(image, toAtLeast: Int(body.rounded(.up)))
            ctx.draw(reduced, in: rect)

        case .vector(let image):
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
            image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
            NSGraphicsContext.restoreGraphicsState()
        }

        return ctx.makeImage()
    }

    /// 幅が target の 2 倍未満になるまで 1/2 ずつ縮小する
    static func downsample(_ image: CGImage, toAtLeast target: Int) -> CGImage {
        var current = image
        while current.width / 2 >= max(target, 1) {
            let w = current.width / 2
            let h = max(current.height / 2, 1)
            guard let ctx = makeContext(width: w, height: h) else { break }
            ctx.interpolationQuality = .high
            ctx.draw(current, in: CGRect(x: 0, y: 0, width: w, height: h))
            guard let next = ctx.makeImage() else { break }
            current = next
        }
        return current
    }

    /// 必要なサイズをまとめて描画する（同じサイズは 1 回だけ）
    static func renderAll(_ source: SourceContent, sizes: some Sequence<Int>, contentScale: CGFloat = 1.0) throws -> [Int: CGImage] {
        var result: [Int: CGImage] = [:]
        for size in Set(sizes) {
            guard let image = render(source, size: size, contentScale: contentScale) else {
                throw IconWriteError.renderFailed(size)
            }
            result[size] = image
        }
        return result
    }

    static func pngData(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }
}

enum IconWriteError: LocalizedError {
    case renderFailed(Int)
    case encodeFailed(Int)
    case missingSize(Int)

    var errorDescription: String? {
        switch self {
        case .renderFailed(let size):
            let px = String(size)
            return String(localized: "Failed to render the \(px) px image")
        case .encodeFailed(let size):
            let px = String(size)
            return String(localized: "Failed to encode the \(px) px image")
        case .missingSize(let size):
            let px = String(size)
            return String(localized: "The \(px) px image is missing")
        }
    }
}

extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }

    mutating func appendBE<T: FixedWidthInteger>(_ value: T) {
        Swift.withUnsafeBytes(of: value.bigEndian) { append(contentsOf: $0) }
    }
}
