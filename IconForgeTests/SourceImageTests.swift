import CoreGraphics
import Foundation
import Testing
@testable import IconForge

@Suite("入力ファイルの読み込みと要件チェック")
struct SourceImageTests {
    struct SizeCase: CustomTestStringConvertible, Sendable {
        let size: Int
        let canMakeICO: Bool
        let canMakeICNS: Bool
        var testDescription: String { "\(size) px" }
    }

    private func hasLevel(_ result: ValidationResult, _ level: ValidationLevel) -> Bool {
        result.items.contains { $0.level == level }
    }

    // MARK: PNG

    @Test("要件を満たす PNG は警告もエラーもない")
    func validPNG() throws {
        let dir = try TempDirectory()
        let source = try SourceImage.load(from: dir.writePNG(TestImage.icon(size: 1024)))

        #expect(source.kind == .png)
        #expect(source.width == 1024)
        #expect(source.height == 1024)
        #expect(source.hasAlpha)
        #expect(source.isSRGB)

        let result = source.validate()
        #expect(result.canMakeICO)
        #expect(result.canMakeICNS)
        #expect(!hasLevel(result, .error))
        #expect(!hasLevel(result, .warning))
    }

    @Test(
        "PNG のサイズで作れる形式が決まる",
        arguments: [
            SizeCase(size: 2048, canMakeICO: true, canMakeICNS: true),
            SizeCase(size: 1024, canMakeICO: true, canMakeICNS: true),
            SizeCase(size: 1023, canMakeICO: true, canMakeICNS: false),
            SizeCase(size: 512, canMakeICO: true, canMakeICNS: false),
            SizeCase(size: 256, canMakeICO: true, canMakeICNS: false),
            SizeCase(size: 255, canMakeICO: false, canMakeICNS: false),
            SizeCase(size: 64, canMakeICO: false, canMakeICNS: false),
        ]
    )
    func sizeRules(_ testCase: SizeCase) throws {
        let dir = try TempDirectory()
        let source = try SourceImage.load(from: dir.writePNG(TestImage.icon(size: testCase.size)))
        let result = source.validate()
        #expect(result.canMakeICO == testCase.canMakeICO)
        #expect(result.canMakeICNS == testCase.canMakeICNS)
    }

    @Test("正方形でない PNG はエラー")
    func nonSquarePNG() throws {
        let dir = try TempDirectory()
        let image = TestImage.solid(width: 1024, height: 512)
        let result = try SourceImage.load(from: dir.writePNG(image)).validate()
        #expect(!result.canMakeICO)
        #expect(!result.canMakeICNS)
        #expect(hasLevel(result, .error))
    }

    @Test("透過のない PNG は警告だが変換はできる")
    func opaquePNG() throws {
        let dir = try TempDirectory()
        let image = TestImage.solid(width: 1024, height: 1024, alpha: false)
        let source = try SourceImage.load(from: dir.writePNG(image))
        #expect(!source.hasAlpha)

        let result = source.validate()
        #expect(result.canMakeICO)
        #expect(result.canMakeICNS)
        #expect(hasLevel(result, .warning))
        #expect(!hasLevel(result, .error))
    }

    @Test("sRGB 以外の PNG は警告だが変換はできる")
    func displayP3PNG() throws {
        let dir = try TempDirectory()
        let p3 = try #require(CGColorSpace(name: CGColorSpace.displayP3))
        let source = try SourceImage.load(from: dir.writePNG(TestImage.icon(size: 1024, colorSpace: p3)))
        #expect(!source.isSRGB)

        let result = source.validate()
        #expect(result.canMakeICO)
        #expect(result.canMakeICNS)
        #expect(hasLevel(result, .warning))
    }

    @Test("拡張子が大文字でも PNG として読める")
    func uppercaseExtension() throws {
        let dir = try TempDirectory()
        let source = try SourceImage.load(from: dir.writePNG(TestImage.icon(size: 256), name: "ICON.PNG"))
        #expect(source.kind == .png)
    }

    // MARK: SVG

    @Test("正方形の SVG はサイズに関係なく両方作れる")
    func squareSVG() throws {
        let dir = try TempDirectory()
        let source = try SourceImage.load(from: dir.writeSVG(width: 64, height: 64))
        #expect(source.kind == .svg)

        let result = source.validate()
        #expect(result.canMakeICO)
        #expect(result.canMakeICNS)
        #expect(!hasLevel(result, .error))
    }

    @Test("正方形でない SVG はエラー")
    func nonSquareSVG() throws {
        let dir = try TempDirectory()
        let result = try SourceImage.load(from: dir.writeSVG(width: 100, height: 50)).validate()
        #expect(!result.canMakeICO)
        #expect(!result.canMakeICNS)
        #expect(hasLevel(result, .error))
    }

    @Test("SVG から全サイズの ICO と ICNS を作れる")
    func svgEndToEnd() throws {
        let dir = try TempDirectory()
        let source = try SourceImage.load(from: dir.writeSVG(width: 64, height: 64))

        let icoImages = try IconRenderer.renderAll(source.content, sizes: ICOWriter.sizes)
        let ico = try ICOWriter.makeData(images: icoImages)
        #expect(Set(imageWidths(in: ico)) == Set(ICOWriter.sizes))

        let icnsImages = try IconRenderer.renderAll(source.content, sizes: ICNSWriter.sizes)
        let icns = try ICNSWriter.makeData(images: icnsImages)
        #expect(imageWidths(in: icns).max() == 1024)
    }

    // MARK: 読み込みエラー

    @Test("PNG・SVG 以外の拡張子は unsupportedType になる")
    func unsupportedType() throws {
        let dir = try TempDirectory()
        let url = try dir.writeText("dummy", name: "photo.jpg")
        do {
            _ = try SourceImage.load(from: url)
            Issue.record("エラーになるはず")
        } catch let error as SourceLoadError {
            guard case .unsupportedType("jpg") = error else {
                Issue.record("想定外のエラー: \(error)")
                return
            }
        }
    }

    @Test("壊れた PNG は unreadable になる")
    func corruptedPNG() throws {
        let dir = try TempDirectory()
        let url = try dir.writeText("これは PNG ではありません", name: "broken.png")
        do {
            _ = try SourceImage.load(from: url)
            Issue.record("エラーになるはず")
        } catch let error as SourceLoadError {
            guard case .unreadable = error else {
                Issue.record("想定外のエラー: \(error)")
                return
            }
        }
    }
}
