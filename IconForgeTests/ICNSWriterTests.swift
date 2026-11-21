import CoreGraphics
import Foundation
import Testing
@testable import IconForge

@Suite("ICNS の書き出し")
struct ICNSWriterTests {
    private func makeICNS() throws -> [UInt8] {
        let source = TestImage.solid(width: 1024, height: 1024)
        let images = try IconRenderer.renderAll(.bitmap(source), sizes: ICNSWriter.sizes)
        return Array(try ICNSWriter.makeData(images: images))
    }

    /// OSType ごとの PNG データ
    private func payloads(_ bytes: [UInt8]) -> [String: [UInt8]] {
        var result: [String: [UInt8]] = [:]
        var offset = 8
        while offset + 8 <= bytes.count {
            let type = bytes.ascii(offset, 4)
            let length = Int(bytes.be32(offset + 4))
            result[type] = Array(bytes[(offset + 8)..<(offset + length)])
            offset += length
        }
        return result
    }

    @Test("描画が必要なピクセルサイズ")
    func requiredSizes() {
        #expect(ICNSWriter.sizes == [16, 32, 64, 128, 256, 512, 1024])
    }

    @Test("ヘッダ（'icns' + ファイル全体の長さ）")
    func header() throws {
        let bytes = try makeICNS()
        #expect(bytes.ascii(0, 4) == "icns")
        #expect(Int(bytes.be32(4)) == bytes.count)
    }

    @Test("全エントリが順番どおりで、中身は指定サイズの PNG")
    func entries() throws {
        let bytes = try makeICNS()
        var offset = 8

        for entry in ICNSWriter.entries {
            #expect(bytes.ascii(offset, 4) == entry.type)
            let length = Int(bytes.be32(offset + 4))
            let png = offset + 8
            #expect(bytes.hasPNGSignature(at: png), "\(entry.type) は PNG")
            // PNG の IHDR にある幅と高さ（シグネチャ 8 + 長さ 4 + "IHDR" 4 の後）
            #expect(Int(bytes.be32(png + 16)) == entry.size, "\(entry.type) の幅")
            #expect(Int(bytes.be32(png + 20)) == entry.size, "\(entry.type) の高さ")
            offset += length
        }
        #expect(offset == bytes.count, "最後のエントリがファイル末尾で終わる")
    }

    @Test("同じピクセル数の @1x と @2x は同じ PNG を使う")
    func sharedPayloads() throws {
        let p = payloads(try makeICNS())
        #expect(p["icp5"] == p["ic11"], "32 px")
        #expect(p["ic08"] == p["ic13"], "256 px")
        #expect(p["ic09"] == p["ic14"], "512 px")
    }

    @Test("ImageIO で読み戻せて、最大 1024 px を含む")
    func readableByImageIO() throws {
        let widths = imageWidths(in: Data(try makeICNS()))
        #expect(!widths.isEmpty)
        #expect(widths.max() == 1024)
    }

    @Test("サイズが欠けているとエラーになる")
    func missingSizeThrows() {
        #expect(throws: IconWriteError.self) {
            try ICNSWriter.makeData(images: [:])
        }
    }
}
