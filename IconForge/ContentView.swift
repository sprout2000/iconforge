import SwiftUI

struct ContentView: View {
    /// ウィンドウの幅（高さは中身に合わせて決まる）
    static let windowWidth: CGFloat = 820
    static let outerPadding: CGFloat = 20
    static let columnSpacing: CGFloat = 20
    static let dropZoneWidth: CGFloat = 300
    /// 右側の欄の幅。幅を固定すると、長い文は折り返されてウィンドウからはみ出さない
    static let detailWidth: CGFloat = windowWidth - outerPadding * 2 - dropZoneWidth - columnSpacing

    @State private var model = ConverterViewModel()
    /// レイアウト用の見本。いちばん縦に長くなる状態を、表示中の言語で作っておく
    @State private var layoutTemplate = ConverterViewModel.layoutTemplate()
    @State private var isDropTargeted = false

    var body: some View {
        HStack(alignment: .top, spacing: Self.columnSpacing) {
            dropZone
                .frame(width: Self.dropZoneWidth)

            // 見本を見えない状態で重ねておくと、ウィンドウの高さが常に「最も長い状態」に合う。
            // そのため、どの言語・どの状態でもスクロールが不要になり、ウィンドウの大きさも変わらない。
            ZStack(alignment: .topLeading) {
                DetailColumn(model: layoutTemplate)
                    .hidden()
                    .accessibilityHidden(true)

                Group {
                    if model.source != nil, model.validation != nil {
                        DetailColumn(model: model)
                    } else {
                        emptyState
                    }
                }
            }
            .frame(width: Self.detailWidth, alignment: .topLeading)
        }
        .padding(Self.outerPadding)
        .frame(width: Self.windowWidth)
        .fixedSize(horizontal: false, vertical: true)
        .background(Brand.softGradient(opacity: 0.06).ignoresSafeArea())
        .onChange(of: model.addMacPadding) {
            model.refreshPreviews()
        }
    }

    // MARK: - ドロップ領域

    private var dropZone: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Brand.softGradient(opacity: isDropTargeted ? 0.18 : 0.10))
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        Brand.gradient.opacity(isDropTargeted ? 0.9 : 0.7),
                        style: StrokeStyle(lineWidth: isDropTargeted ? 3 : 2, dash: [8, 6])
                    )

                if let source = model.source {
                    CheckerboardView()
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            Image(nsImage: source.preview)
                                .resizable()
                                .interpolation(.high)
                                .aspectRatio(contentMode: .fit)
                        )
                        .padding(20)
                } else {
                    VStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(Brand.gradient)
                                .frame(width: 88, height: 88)
                                .shadow(color: Brand.slate.opacity(0.26), radius: 8, y: 4)
                            Image(systemName: "square.and.arrow.down")
                                .font(.system(size: 34, weight: .semibold))
                                .foregroundStyle(.white)
                                .offset(y: -2)
                        }
                        .scaleEffect(isDropTargeted ? 1.08 : 1.0)

                        Text("Drop a PNG or SVG\nhere")
                            .font(.headline)
                            .multilineTextAlignment(.center)
                    }
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .animation(.spring(duration: 0.25), value: isDropTargeted)
            .dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first else { return false }
                model.load(url: url)
                return true
            } isTargeted: { targeted in
                isDropTargeted = targeted
            }

            Button {
                model.chooseFile()
            } label: {
                Label("Choose File…", systemImage: "folder")
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .tint(Brand.slate)

            if let error = model.loadError {
                Label(error, systemImage: "xmark.octagon.fill")
                    .foregroundStyle(.red)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Create ICO and ICNS from PNG / SVG")
                    .font(.title.bold())
                    .foregroundStyle(.primary)
                HStack(spacing: 8) {
                    FormatChip(title: "ICO", subtitle: "Windows", color: Brand.slate)
                    FormatChip(title: "ICNS", subtitle: "macOS", color: Brand.plum)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Input Requirements")
                    .font(.headline)
                RequirementRow(symbol: "square", color: Brand.slate,
                               title: "Square",
                               detail: "Make the width and height equal")
                RequirementRow(symbol: "ruler", color: Brand.sand,
                               title: "1024 × 1024 px or Larger",
                               detail: "For PNG. 256 px or larger is enough for ICO only")
                RequirementRow(symbol: "circle.lefthalf.filled", color: Brand.plum,
                               title: "Transparency Recommended",
                               detail: "A PNG with an alpha channel")
                RequirementRow(symbol: "paintpalette.fill", color: Brand.rose,
                               title: "sRGB Recommended",
                               detail: "Other color spaces are converted to sRGB")
                RequirementRow(symbol: "scribble.variable", color: Brand.sage,
                               title: "SVG at Any Size",
                               detail: "Each size is drawn directly from the vector")
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.7))
                    .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
            )
        }
    }
}

/// ファイル読み込み後の右側の欄
struct DetailColumn: View {
    @Bindable var model: ConverterViewModel

    var body: some View {
        if let source = model.source, let validation = model.validation {
            VStack(alignment: .leading, spacing: 16) {
                infoSection(source)
                validationSection(validation)
                Divider()
                optionsSection(validation)
                actionSection
                Divider()
                previewSection
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - 情報・要件チェック

    private func infoSection(_ source: SourceImage) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(source.url.lastPathComponent)
                .font(.title3.bold())
                .lineLimit(1)
                .truncationMode(.middle)
            Text(source.summary)
                .foregroundStyle(.secondary)
        }
    }

    private func validationSection(_ validation: ValidationResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(validation.items) { item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    icon(for: item.level)
                    Text(item.message)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.callout)
            }
        }
    }

    @ViewBuilder
    private func icon(for level: ValidationLevel) -> some View {
        switch level {
        case .ok:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .info:
            Image(systemName: "info.circle.fill").foregroundStyle(.blue)
        case .warning:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
        case .error:
            Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
        }
    }

    // MARK: - オプション・実行

    private func optionsSection(_ validation: ValidationResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            CheckboxRow(isOn: $model.makeICO, title: "ICO (Windows)") {
                Text(verbatim: ICOWriter.sizes.map(String.init).joined(separator: ", ") + " px")
            }
            .disabled(!validation.canMakeICO)

            CheckboxRow(isOn: $model.makeICNS, title: "ICNS (macOS)") {
                Text("16–1024 px (including @2x)")
            }
            .disabled(!validation.canMakeICNS)

            CheckboxRow(isOn: $model.addMacPadding, title: "Add macOS-style padding to ICNS (artwork fills 824 of 1024 px)")
                .font(.callout)
                .disabled(!validation.canMakeICNS || !model.makeICNS)
                .padding(.leading, 22)
        }
    }

    private var actionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button {
                    model.convert()
                } label: {
                    Label("Convert and Save…", systemImage: "arrow.down.doc")
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .disabled(!model.canConvert)
                .keyboardShortcut("s", modifiers: .command)

                if !model.lastOutputs.isEmpty {
                    Button("Show in Finder") { model.revealInFinder() }
                        .controlSize(.large)
                }
            }

            if let status = model.status {
                Label(status.text, systemImage: status.isError ? "xmark.octagon.fill" : "checkmark.circle.fill")
                    .foregroundStyle(status.isError ? .red : .green)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - プレビュー

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Preview (small sizes shown at actual size)")
                .font(.headline)
            HStack(alignment: .bottom, spacing: 14) {
                // 小さいサイズ（64 px まで）は実寸で並べる
                ForEach(model.icoPreviews.filter { $0.size <= 64 }, id: \.size) { item in
                    previewTile(item.image, side: CGFloat(item.size), label: "\(item.size)", pixelExact: true)
                }

                Divider().frame(height: 128)

                // 大きい枠は 1 つだけ。ICNS を作るときは ICNS の見た目、作らないときは ICO の 128 px
                if model.makeICNS, model.validation?.canMakeICNS == true, let icns = model.icnsPreview {
                    previewTile(icns, side: 128, label: "ICNS", pixelExact: false)
                } else if let large = model.icoPreviews.first(where: { $0.size == 128 }) {
                    previewTile(large.image, side: 128, label: "128", pixelExact: true)
                }
            }
        }
    }

    private func previewTile(_ image: NSImage, side: CGFloat, label: String, pixelExact: Bool) -> some View {
        VStack(spacing: 4) {
            Image(nsImage: image)
                .resizable()
                .interpolation(pixelExact ? .none : .high)
                .frame(width: side, height: side)
                .background(CheckerboardView())
            Text(verbatim: label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - 配色と部品

/// 落ち着いた中間色のパレット。色はここだけで決める
enum Brand {
    static let slate = Color(red: 0.28, green: 0.46, blue: 0.75)  // くすんだ青
    static let teal = Color(red: 0.24, green: 0.58, blue: 0.64)   // くすんだ青緑
    static let sand = Color(red: 0.85, green: 0.57, blue: 0.24)   // 砂色
    static let plum = Color(red: 0.54, green: 0.39, blue: 0.78)   // くすんだ紫
    static let rose = Color(red: 0.84, green: 0.41, blue: 0.52)   // くすんだ赤
    static let sage = Color(red: 0.33, green: 0.66, blue: 0.43)   // くすんだ緑

    /// 背景や枠に使うグラデーションの色
    static let colors: [Color] = [slate, teal]

    static var gradient: LinearGradient {
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static func softGradient(opacity: Double) -> LinearGradient {
        LinearGradient(
            colors: colors.map { $0.opacity(opacity) },
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

/// 色付きのアイコンバッジと説明の 1 行
struct RequirementRow: View {
    let symbol: String
    let color: Color
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 8).fill(color.opacity(0.22)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// 文が長くても折り返すチェックボックス
///
/// 標準の `Toggle` は、ラベルが長いと折り返さずに横へはみ出すことがあるため、
/// チェックボックスとラベルを分けて並べ、ラベルのクリックでも切り替わるようにしている。
struct CheckboxRow<Detail: View>: View {
    @Binding var isOn: Bool
    let title: LocalizedStringKey
    let detail: Detail

    @Environment(\.isEnabled) private var isEnabled

    init(isOn: Binding<Bool>, title: LocalizedStringKey, @ViewBuilder detail: () -> Detail) {
        _isOn = isOn
        self.title = title
        self.detail = detail()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Toggle(isOn: $isOn) { EmptyView() }
                .toggleStyle(.checkbox)
                .labelsHidden()
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .fixedSize(horizontal: false, vertical: true)
                detail
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(isEnabled ? .primary : .secondary)
            .contentShape(Rectangle())
            .onTapGesture {
                if isEnabled { isOn.toggle() }
            }
        }
    }
}

extension CheckboxRow where Detail == EmptyView {
    init(isOn: Binding<Bool>, title: LocalizedStringKey) {
        self.init(isOn: isOn, title: title) { EmptyView() }
    }
}

/// 出力形式を示す小さなラベル
struct FormatChip: View {
    let title: String
    let subtitle: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(color))
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(color)
        }
        .padding(.leading, 3)
        .padding(.trailing, 10)
        .padding(.vertical, 3)
        .background(Capsule().fill(color.opacity(0.18)))
    }
}

/// 透過部分がわかるようにする市松模様
struct CheckerboardView: View {
    var cell: CGFloat = 8

    var body: some View {
        Canvas { context, size in
            let cols = Int(ceil(size.width / cell))
            let rows = Int(ceil(size.height / cell))
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
            for r in 0..<rows {
                for c in 0..<cols where (r + c) % 2 == 1 {
                    let rect = CGRect(x: CGFloat(c) * cell, y: CGFloat(r) * cell, width: cell, height: cell)
                    context.fill(Path(rect), with: .color(Color(white: 0.85)))
                }
            }
        }
    }
}
