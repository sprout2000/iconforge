import AppKit
import Observation
import UniformTypeIdentifiers

@MainActor
@Observable
final class ConverterViewModel {
    var source: SourceImage?
    var validation: ValidationResult?
    var loadError: String?

    var makeICO = true
    var makeICNS = true
    /// ICNS だけに macOS 風の余白（824/1024）を付ける
    var addMacPadding = false

    var status: StatusMessage?
    var lastOutputs: [URL] = []

    /// プレビュー用（実寸表示）
    var icoPreviews: [(size: Int, image: NSImage)] = []
    var icnsPreview: NSImage?

    static let previewSizes = [16, 24, 32, 48, 64, 128]

    struct StatusMessage {
        let isError: Bool
        let text: String
    }

    var canConvert: Bool {
        guard let validation else { return false }
        return (makeICO && validation.canMakeICO) || (makeICNS && validation.canMakeICNS)
    }

    // MARK: - 読み込み

    func load(url: URL) {
        do {
            let image = try SourceImage.load(from: url)
            let result = image.validate()
            source = image
            validation = result
            makeICO = result.canMakeICO
            makeICNS = result.canMakeICNS
            loadError = nil
            status = nil
            lastOutputs = []
            refreshPreviews()
        } catch {
            source = nil
            validation = nil
            icoPreviews = []
            icnsPreview = nil
            loadError = error.localizedDescription
        }
    }

    func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .svg]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = String(localized: "Choose a PNG or SVG to use as the icon source")
        if panel.runModal() == .OK, let url = panel.url {
            load(url: url)
        }
    }

    func refreshPreviews() {
        guard let source else { return }
        icoPreviews = Self.previewSizes.compactMap { size in
            guard let cg = IconRenderer.render(source.content, size: size) else { return nil }
            return (size, NSImage(cgImage: cg, size: NSSize(width: size, height: size)))
        }
        let scale = addMacPadding ? IconRenderer.macContentScale : 1.0
        if let cg = IconRenderer.render(source.content, size: 256, contentScale: scale) {
            icnsPreview = NSImage(cgImage: cg, size: NSSize(width: 128, height: 128))
        }
    }

    // MARK: - 変換

    func convert() {
        guard let source, let validation, canConvert else { return }

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = source.url.deletingLastPathComponent()
        panel.prompt = String(localized: "Save Here")
        panel.message = String(localized: "Choose a folder to save the ICO / ICNS files in")
        guard panel.runModal() == .OK, let folder = panel.url else { return }

        let baseName = source.url.deletingPathExtension().lastPathComponent
        let icoURL = folder.appendingPathComponent(baseName).appendingPathExtension("ico")
        let icnsURL = folder.appendingPathComponent(baseName).appendingPathExtension("icns")

        let wantICO = makeICO && validation.canMakeICO
        let wantICNS = makeICNS && validation.canMakeICNS

        let targets = [(wantICO, icoURL), (wantICNS, icnsURL)].filter { $0.0 }.map { $0.1 }
        let existing = targets.filter { FileManager.default.fileExists(atPath: $0.path) }
        if !existing.isEmpty, !confirmOverwrite(existing) { return }

        do {
            var outputs: [URL] = []

            if wantICO {
                let images = try IconRenderer.renderAll(source.content, sizes: ICOWriter.sizes)
                let data = try ICOWriter.makeData(images: images)
                try data.write(to: icoURL, options: .atomic)
                outputs.append(icoURL)
            }

            if wantICNS {
                let scale = addMacPadding ? IconRenderer.macContentScale : 1.0
                let images = try IconRenderer.renderAll(source.content, sizes: ICNSWriter.sizes, contentScale: scale)
                let data = try ICNSWriter.makeData(images: images)
                try data.write(to: icnsURL, options: .atomic)
                outputs.append(icnsURL)
            }

            lastOutputs = outputs
            let names = outputs.map(\.lastPathComponent).formatted(.list(type: .and))
            status = StatusMessage(isError: false, text: String(localized: "Saved: \(names)"))
        } catch {
            let reason = error.localizedDescription
            status = StatusMessage(isError: true, text: String(localized: "Conversion failed: \(reason)"))
        }
    }

    func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting(lastOutputs)
    }

    private func confirmOverwrite(_ urls: [URL]) -> Bool {
        let alert = NSAlert()
        alert.messageText = String(localized: "A file with the same name already exists")
        alert.informativeText = urls.map(\.lastPathComponent).joined(separator: "\n") + "\n\n" + String(localized: "Do you want to replace it?")
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "Replace"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        return alert.runModal() == .alertFirstButtonReturn
    }
}

// MARK: - レイアウト用の見本

extension ConverterViewModel {
    /// ウィンドウの高さを決めるための見本（画面には表示されない）
    ///
    /// 右側の欄がいちばん縦に長くなる状態を作る。
    /// - 要件チェックが 4 項目（正方形でない・ICNS には小さい・透過なし・sRGB 以外）
    /// - 保存結果のメッセージと「Finder で表示」ボタンがある
    /// 文言は表示中の言語で作られるので、どの言語でも中身がちょうど収まる高さになる。
    static func layoutTemplate() -> ConverterViewModel {
        let model = ConverterViewModel()
        guard let pixel = IconRenderer.makeContext(width: 1, height: 1)?.makeImage() else {
            return model
        }

        let baseName = "IconForge-Layout-Sample-Icon"
        let sample = SourceImage(
            url: URL(fileURLWithPath: "/\(baseName).png"),
            kind: .png,
            content: .bitmap(pixel),
            width: 1024,
            height: 600,
            hasAlpha: false,
            colorSpaceName: "Display P3",
            isSRGB: false,
            bitsPerComponent: 16
        )
        model.source = sample
        model.validation = sample.validate()

        let names = ["\(baseName).ico", "\(baseName).icns"].formatted(.list(type: .and))
        model.status = StatusMessage(isError: false, text: String(localized: "Saved: \(names)"))
        model.lastOutputs = [URL(fileURLWithPath: "/\(baseName).ico")]
        model.refreshPreviews()
        return model
    }
}
