import CoreGraphics
import Foundation
import Testing
@testable import IconForge

@MainActor
@Suite("画面の状態（ViewModel）")
struct ConverterViewModelTests {
    @Test("1024 px の PNG を読み込むと ICO と ICNS の両方がオンになる")
    func loadLargePNG() throws {
        let dir = try TempDirectory()
        let model = ConverterViewModel()
        model.load(url: try dir.writePNG(TestImage.icon(size: 1024)))

        #expect(model.source != nil)
        #expect(model.loadError == nil)
        #expect(model.makeICO)
        #expect(model.makeICNS)
        #expect(model.canConvert)
        #expect(model.icoPreviews.map { $0.size } == ConverterViewModel.previewSizes)
        #expect(model.icnsPreview != nil)
    }

    @Test("512 px の PNG では ICNS がオフになる")
    func loadSmallPNG() throws {
        let dir = try TempDirectory()
        let model = ConverterViewModel()
        model.load(url: try dir.writePNG(TestImage.icon(size: 512)))

        #expect(model.makeICO)
        #expect(!model.makeICNS)
        #expect(model.canConvert)
    }

    @Test("正方形でない画像は変換できない")
    func loadNonSquare() throws {
        let dir = try TempDirectory()
        let model = ConverterViewModel()
        model.load(url: try dir.writePNG(TestImage.solid(width: 1024, height: 600)))

        #expect(model.source != nil)
        #expect(!model.makeICO)
        #expect(!model.makeICNS)
        #expect(!model.canConvert)
    }

    @Test("ICO だけ選んでいても変換できる")
    func canConvertWithICOOnly() throws {
        let dir = try TempDirectory()
        let model = ConverterViewModel()
        model.load(url: try dir.writePNG(TestImage.icon(size: 1024)))
        model.makeICNS = false
        #expect(model.canConvert)

        model.makeICO = false
        #expect(!model.canConvert, "どちらも選んでいなければ変換できない")
    }

    @Test("レイアウト用の見本は、実際のどの入力よりも要件チェックの項目が多いか同じ")
    func layoutTemplateIsWorstCase() throws {
        let template = ConverterViewModel.layoutTemplate()
        let templateItems = try #require(template.validation).items
        #expect(templateItems.count == 4)
        #expect(template.status != nil, "保存結果のメッセージも含む")
        #expect(!template.lastOutputs.isEmpty, "「Finder で表示」ボタンも含む")
        #expect(template.icoPreviews.count == ConverterViewModel.previewSizes.count)

        // 実際に起こりうる入力の項目数は、見本を超えない
        let dir = try TempDirectory()
        let p3 = try #require(CGColorSpace(name: CGColorSpace.displayP3))
        let inputs: [URL] = [
            try dir.writePNG(TestImage.icon(size: 1024), name: "a.png"),
            try dir.writePNG(TestImage.solid(width: 300, height: 200, alpha: false), name: "b.png"),
            try dir.writePNG(TestImage.icon(size: 128, colorSpace: p3), name: "c.png"),
            try dir.writeSVG(width: 64, height: 64),
            try dir.writeSVG(width: 100, height: 50, name: "d.svg"),
        ]
        for url in inputs {
            let items = try SourceImage.load(from: url).validate().items
            #expect(items.count <= templateItems.count, "\(url.lastPathComponent)")
        }
    }

    @Test("読み込めないファイルはエラーを表示し、前の画像をクリアする")
    func loadInvalidFile() throws {
        let dir = try TempDirectory()
        let model = ConverterViewModel()
        model.load(url: try dir.writePNG(TestImage.icon(size: 1024)))
        model.load(url: try dir.writeText("dummy", name: "photo.jpg"))

        #expect(model.source == nil)
        #expect(model.validation == nil)
        #expect(model.loadError != nil)
        #expect(model.icoPreviews.isEmpty)
        #expect(!model.canConvert)
    }
}
