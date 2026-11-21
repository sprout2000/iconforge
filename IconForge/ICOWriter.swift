import CoreGraphics
import Foundation

/// Windows 用マルチアイコン ICO を書き出す
///
/// - 256 px は PNG 圧縮で格納（Windows Vista 以降の標準）
/// - 256 px 未満は 32bit BMP（DIB + AND マスク）で格納し、古いツールとの互換性を確保
enum ICOWriter {
    static let sizes = [16, 24, 32, 48, 64, 128, 256]

    static func makeData(images: [Int: CGImage]) throws -> Data {
        var payloads: [(size: Int, data: Data)] = []

        for size in sizes {
            guard let image = images[size] else { throw IconWriteError.missingSize(size) }
            let encoded: Data?
            if size >= 256 {
                encoded = IconRenderer.pngData(image)
            } else {
                encoded = dibData(image)
            }
            guard let encoded else { throw IconWriteError.encodeFailed(size) }
            payloads.append((size, encoded))
        }

        var out = Data()
        // ICONDIR
        out.appendLE(UInt16(0))               // reserved
        out.appendLE(UInt16(1))               // type: 1 = icon
        out.appendLE(UInt16(payloads.count))  // count

        // ICONDIRENTRY × count
        var offset = 6 + 16 * payloads.count
        for payload in payloads {
            let dim = UInt8(payload.size >= 256 ? 0 : payload.size)  // 0 は 256 を意味する
            out.append(dim)                   // width
            out.append(dim)                   // height
            out.append(0)                     // color count
            out.append(0)                     // reserved
            out.appendLE(UInt16(1))           // planes
            out.appendLE(UInt16(32))          // bit count
            out.appendLE(UInt32(payload.data.count))
            out.appendLE(UInt32(offset))
            offset += payload.data.count
        }

        for payload in payloads {
            out.append(payload.data)
        }
        return out
    }

    /// 32bit BGRA の DIB（BITMAPINFOHEADER + ピクセル + AND マスク）を作る
    static func dibData(_ image: CGImage) -> Data? {
        let w = image.width
        let h = image.height
        var rgba = [UInt8](repeating: 0, count: w * h * 4)

        let drawn = rgba.withUnsafeMutableBytes { buffer -> Bool in
            guard let ctx = CGContext(
                data: buffer.baseAddress,
                width: w,
                height: h,
                bitsPerComponent: 8,
                bytesPerRow: w * 4,
                space: IconRenderer.sRGB,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return nil }

        let maskStride = ((w + 31) / 32) * 4
        let xorSize = w * h * 4
        let andSize = maskStride * h

        var out = Data()
        out.reserveCapacity(40 + xorSize + andSize)

        // BITMAPINFOHEADER（高さは XOR + AND の 2 枚分）
        out.appendLE(UInt32(40))
        out.appendLE(Int32(w))
        out.appendLE(Int32(h * 2))
        out.appendLE(UInt16(1))               // planes
        out.appendLE(UInt16(32))              // bit count
        out.appendLE(UInt32(0))               // BI_RGB
        out.appendLE(UInt32(xorSize + andSize))
        out.appendLE(Int32(0))                // x pixels per meter
        out.appendLE(Int32(0))                // y pixels per meter
        out.appendLE(UInt32(0))               // colors used
        out.appendLE(UInt32(0))               // colors important

        // ピクセル（下の行から、BGRA、ストレートアルファ）
        var mask = [UInt8](repeating: 0, count: andSize)
        for (row, y) in stride(from: h - 1, through: 0, by: -1).enumerated() {
            for x in 0..<w {
                let i = (y * w + x) * 4
                let a = rgba[i + 3]
                var r = rgba[i]
                var g = rgba[i + 1]
                var b = rgba[i + 2]
                if a > 0 && a < 255 {
                    r = unpremultiply(r, a)
                    g = unpremultiply(g, a)
                    b = unpremultiply(b, a)
                }
                out.append(b)
                out.append(g)
                out.append(r)
                out.append(a)

                if a == 0 {
                    mask[row * maskStride + x / 8] |= UInt8(0x80 >> (x % 8))
                }
            }
        }
        out.append(contentsOf: mask)
        return out
    }

    private static func unpremultiply(_ c: UInt8, _ a: UInt8) -> UInt8 {
        let value = (Int(c) * 255 + Int(a) / 2) / Int(a)
        return UInt8(min(value, 255))
    }
}
