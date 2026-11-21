import CoreGraphics
import Foundation
import Testing
@testable import IconForge

@Suite("ICO の書き出し")
struct ICOWriterTests {
    private func makeICO() throws -> [UInt8] {
        let source = TestImage.solid(width: 1024, height: 1024)
        let images = try IconRenderer.renderAll(.bitmap(source), sizes: ICOWriter.sizes)
        return Array(try ICOWriter.makeData(images: images))
    }

    @Test("ICONDIR ヘッダ（reserved=0, type=1, 枚数）")
    func header() throws {
        let bytes = try makeICO()
        #expect(bytes.le16(0) == 0)
        #expect(bytes.le16(2) == 1)
        #expect(Int(bytes.le16(4)) == ICOWriter.sizes.count)
    }

    @Test("各エントリのサイズ・ビット数・オフセットが正しい")
    func directoryEntries() throws {
        let bytes = try makeICO()
        var expectedOffset = 6 + 16 * ICOWriter.sizes.count

        for (index, size) in ICOWriter.sizes.enumerated() {
            let entry = 6 + 16 * index
            let dim = size >= 256 ? 0 : size
            #expect(Int(bytes[entry]) == dim, "幅 \(size)")
            #expect(Int(bytes[entry + 1]) == dim, "高さ \(size)")
            #expect(bytes.le16(entry + 4) == 1, "planes \(size)")
            #expect(bytes.le16(entry + 6) == 32, "bit count \(size)")

            let length = Int(bytes.le32(entry + 8))
            let offset = Int(bytes.le32(entry + 12))
            #expect(offset == expectedOffset, "オフセット \(size)")
            expectedOffset += length
        }
        #expect(expectedOffset == bytes.count, "最後のデータがファイル末尾で終わる")
    }

    @Test("256 px は PNG、それ未満は 32bit BMP で格納する")
    func payloadFormats() throws {
        let bytes = try makeICO()

        for (index, size) in ICOWriter.sizes.enumerated() {
            let entry = 6 + 16 * index
            let length = Int(bytes.le32(entry + 8))
            let offset = Int(bytes.le32(entry + 12))

            if size >= 256 {
                #expect(bytes.hasPNGSignature(at: offset), "\(size) px は PNG")
            } else {
                let maskStride = ((size + 31) / 32) * 4
                #expect(bytes.le32(offset) == 40, "BITMAPINFOHEADER のサイズ")
                #expect(Int(bytes.le32(offset + 4)) == size, "DIB の幅")
                #expect(Int(bytes.le32(offset + 8)) == size * 2, "DIB の高さは XOR + AND の 2 倍")
                #expect(bytes.le16(offset + 14) == 32, "DIB のビット数")
                #expect(length == 40 + size * size * 4 + maskStride * size, "DIB のデータ長")
            }
        }
    }

    @Test("ImageIO で全サイズを読み戻せる")
    func readableByImageIO() throws {
        let data = Data(try makeICO())
        #expect(Set(imageWidths(in: data)) == Set(ICOWriter.sizes))
    }

    @Test("サイズが欠けているとエラーになる")
    func missingSizeThrows() {
        #expect(throws: IconWriteError.self) {
            try ICOWriter.makeData(images: [:])
        }
    }
}

@Suite("ICO 内の BMP（DIB）")
struct DIBTests {
    /// 2×2 の画像
    /// 上段: 左＝赤（不透明）、右＝透明
    /// 下段: 左＝緑（半透明 128）、右＝青（不透明）
    private let image = TestImage.make(width: 2, height: 2) { x, y in
        switch (x, y) {
        case (0, 0): return RGBA(r: 255, g: 0, b: 0, a: 255)
        case (1, 0): return .clear
        case (0, 1): return RGBA(r: 0, g: 255, b: 0, a: 128)
        default: return RGBA(r: 0, g: 0, b: 255, a: 255)
        }
    }

    private let header = 40

    @Test("全体の長さ（ヘッダ + ピクセル + AND マスク）")
    func length() throws {
        let bytes = Array(try #require(ICOWriter.dibData(image)))
        #expect(bytes.count == 40 + 2 * 2 * 4 + 4 * 2)
    }

    @Test("ピクセルは下の行から BGRA の順で並ぶ")
    func bottomUpBGRA() throws {
        let bytes = Array(try #require(ICOWriter.dibData(image)))
        let p = header

        // 1 行目 = 画像の下段
        #expect(Array(bytes[(p + 4)..<(p + 8)]) == [255, 0, 0, 255], "下段右の青")
        // 2 行目 = 画像の上段
        #expect(Array(bytes[(p + 8)..<(p + 12)]) == [0, 0, 255, 255], "上段左の赤")
        #expect(bytes[p + 15] == 0, "上段右は透明")
    }

    @Test("半透明ピクセルはストレートアルファに戻す")
    func unpremultiplied() throws {
        let bytes = Array(try #require(ICOWriter.dibData(image)))
        let p = header  // 下段左の緑（半透明）
        #expect(bytes[p] == 0, "B")
        #expect(abs(Int(bytes[p + 1]) - 255) <= 2, "G はプリマルチプライド前の値に戻る")
        #expect(bytes[p + 2] == 0, "R")
        #expect(bytes[p + 3] == 128, "A")
    }

    @Test("AND マスクは完全に透明なピクセルだけ 1 になる")
    func andMask() throws {
        let bytes = Array(try #require(ICOWriter.dibData(image)))
        let mask = header + 2 * 2 * 4
        #expect(bytes[mask] == 0x00, "下段はどちらも不透明（半透明は 0）")
        #expect(bytes[mask + 4] == 0x40, "上段右（x = 1）だけ透明")
    }
}
