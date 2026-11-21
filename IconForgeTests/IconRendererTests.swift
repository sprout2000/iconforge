import AppKit
import CoreGraphics
import Testing
@testable import IconForge

@Suite("アイコンの描画")
struct IconRendererTests {
    private let opaqueRed = TestImage.solid(width: 1024, height: 1024)

    @Test("指定したサイズの正方形で描画される", arguments: [16, 24, 48, 256, 1024])
    func renderedSize(size: Int) throws {
        let image = try #require(IconRenderer.render(.bitmap(opaqueRed), size: size))
        #expect(image.width == size)
        #expect(image.height == size)
    }

    @Test("余白なしでは角まで塗られる")
    func fullBleed() throws {
        let image = try #require(IconRenderer.render(.bitmap(opaqueRed), size: 64))
        #expect(isClose(TestImage.pixel(image, x: 0, y: 0), .red))
        #expect(isClose(TestImage.pixel(image, x: 32, y: 32), .red))
    }

    @Test("macOS 風の余白を付けると周囲が透明になる")
    func macPadding() throws {
        let image = try #require(
            IconRenderer.render(.bitmap(opaqueRed), size: 1024, contentScale: IconRenderer.macContentScale)
        )
        // 本体は (1024 - 824) / 2 = 100 px 内側から始まる
        #expect(TestImage.pixel(image, x: 0, y: 0).a == 0, "角")
        #expect(TestImage.pixel(image, x: 90, y: 512).a == 0, "左の余白")
        #expect(isClose(TestImage.pixel(image, x: 110, y: 512), .red), "本体の左端")
        #expect(isClose(TestImage.pixel(image, x: 512, y: 512), .red), "中央")
    }

    @Test("macOS 風の余白では 1024 px 中 824 px が本体になる")
    func macPaddingBodyWidth() throws {
        let image = try #require(
            IconRenderer.render(.bitmap(opaqueRed), size: 1024, contentScale: IconRenderer.macContentScale)
        )
        let bytes = TestImage.rgba(of: image)
        let row = 512
        // 中央の行で、不透明なピクセルの x 座標を集める
        let opaque = (0..<1024).filter { x in bytes[(row * 1024 + x) * 4 + 3] > 127 }

        #expect(opaque.count == 824)
        #expect(opaque.first == 100)
        #expect(opaque.last == 923)
    }

    @Test("ベクター（NSImage）からも描画できる")
    func vectorSource() throws {
        let vector = NSImage(size: NSSize(width: 10, height: 10), flipped: false) { rect in
            NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1).setFill()
            rect.fill()
            return true
        }
        let image = try #require(IconRenderer.render(.vector(vector), size: 32))
        #expect(image.width == 32)
        #expect(isClose(TestImage.pixel(image, x: 16, y: 16), .red))
    }

    @Test("透明部分は透明のまま描画される")
    func keepsTransparency() throws {
        // 左半分が透明、右半分が赤
        let half = TestImage.make(width: 256, height: 256) { x, _ in x < 128 ? .clear : .red }
        let image = try #require(IconRenderer.render(.bitmap(half), size: 32))
        #expect(TestImage.pixel(image, x: 4, y: 16).a == 0)
        #expect(isClose(TestImage.pixel(image, x: 28, y: 16), .red))
    }

    @Test("1/2 ずつ縮小し、目標の 2 倍未満で止まる")
    func downsampleSteps() {
        let reduced = IconRenderer.downsample(opaqueRed, toAtLeast: 100)
        // 1024 → 512 → 256 → 128（次の 64 は 100 未満なので止まる）
        #expect(reduced.width == 128)
        #expect(reduced.height == 128)
    }

    @Test("目標以下の画像は縮小しない")
    func downsampleNoop() {
        let small = TestImage.solid(width: 64, height: 64)
        #expect(IconRenderer.downsample(small, toAtLeast: 64).width == 64)
        #expect(IconRenderer.downsample(small, toAtLeast: 256).width == 64)
    }

    @Test("同じサイズは 1 回だけ描画される")
    func renderAllDeduplicates() throws {
        let images = try IconRenderer.renderAll(.bitmap(opaqueRed), sizes: [16, 32, 32, 16])
        #expect(Set(images.keys) == [16, 32])
    }

    @Test("PNG にエンコードできる")
    func pngData() throws {
        let data = try #require(IconRenderer.pngData(opaqueRed))
        #expect(Array(data).hasPNGSignature(at: 0))
        #expect(imageWidths(in: data) == [1024])
    }
}

@Suite("Data へのバイト追加")
struct DataEndianTests {
    @Test("リトルエンディアン")
    func littleEndian() {
        var data = Data()
        data.appendLE(UInt16(0x0102))
        data.appendLE(UInt32(0x0304_0506))
        #expect(Array(data) == [0x02, 0x01, 0x06, 0x05, 0x04, 0x03])
    }

    @Test("ビッグエンディアン")
    func bigEndian() {
        var data = Data()
        data.appendBE(UInt32(0x0102_0304))
        #expect(Array(data) == [0x01, 0x02, 0x03, 0x04])
    }

    @Test("負の値（Int32）も 2 の補数で書かれる")
    func signed() {
        var data = Data()
        data.appendLE(Int32(-1))
        #expect(Array(data) == [0xFF, 0xFF, 0xFF, 0xFF])
    }
}
