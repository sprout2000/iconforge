import AppKit
import ImageIO
import UniformTypeIdentifiers

enum SourceKind {
    case png
    case svg
}

/// Drawing source: a bitmap for PNG, an NSImage for SVG (drawn as vector)
enum SourceContent {
    case bitmap(CGImage)
    case vector(NSImage)
}

struct SourceImage {
    let url: URL
    let kind: SourceKind
    let content: SourceContent
    /// Pixels for PNG, points for SVG (width/height or viewBox)
    let width: CGFloat
    let height: CGFloat
    let hasAlpha: Bool
    let colorSpaceName: String?
    let isSRGB: Bool
    let bitsPerComponent: Int

    var preview: NSImage {
        switch content {
        case .bitmap(let cg):
            return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        case .vector(let image):
            return image
        }
    }

    var summary: String {
        switch kind {
        case .png:
            var parts = ["PNG", "\(Int(width)) × \(Int(height)) px"]
            if let colorSpaceName { parts.append(colorSpaceName) }
            parts.append(String(localized: "\(bitsPerComponent)-bit"))
            parts.append(hasAlpha ? String(localized: "Transparent") : String(localized: "Opaque"))
            return parts.joined(separator: " · ")
        case .svg:
            let w = Self.format(width)
            let h = Self.format(height)
            return String(localized: "SVG · \(w) × \(h) pt (vector)")
        }
    }

    static func format(_ value: CGFloat) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }
}

enum SourceLoadError: LocalizedError {
    case unsupportedType(String)
    case unreadable(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedType(let ext):
            return String(localized: "Unsupported format (.\(ext)). Choose a PNG or SVG file.")
        case .unreadable(let name):
            return String(localized: "Couldn’t read \(name). Make sure the file isn’t damaged.")
        }
    }
}

extension SourceImage {
    static func load(from url: URL) throws -> SourceImage {
        let ext = url.pathExtension.lowercased()
        let type = UTType(filenameExtension: ext)
        if type?.conforms(to: .png) == true {
            return try loadPNG(url)
        }
        if type?.conforms(to: .svg) == true {
            return try loadSVG(url)
        }
        throw SourceLoadError.unsupportedType(ext.isEmpty ? "?" : ext)
    }

    private static func loadPNG(_ url: URL) throws -> SourceImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw SourceLoadError.unreadable(url.lastPathComponent)
        }

        let opaque: [CGImageAlphaInfo] = [.none, .noneSkipFirst, .noneSkipLast]
        let hasAlpha = !opaque.contains(image.alphaInfo)
        let rawName = image.colorSpace?.name as String?
        let isSRGB = rawName == (CGColorSpace.sRGB as String)
        let displayName = rawName.map(Self.displayName(forColorSpace:))

        return SourceImage(
            url: url,
            kind: .png,
            content: .bitmap(image),
            width: CGFloat(image.width),
            height: CGFloat(image.height),
            hasAlpha: hasAlpha,
            colorSpaceName: displayName,
            isSRGB: isSRGB,
            bitsPerComponent: image.bitsPerComponent
        )
    }

    /// 色空間の内部名を表示用の名前にする（例: kCGColorSpaceSRGB → sRGB）
    static func displayName(forColorSpace rawName: String) -> String {
        let known: [String: String] = [
            CGColorSpace.sRGB as String: "sRGB",
            CGColorSpace.extendedSRGB as String: "Extended sRGB",
            CGColorSpace.linearSRGB as String: "Linear sRGB",
            CGColorSpace.displayP3 as String: "Display P3",
            CGColorSpace.adobeRGB1998 as String: "Adobe RGB (1998)",
            CGColorSpace.genericGrayGamma2_2 as String: "Gray",
            CGColorSpace.linearGray as String: "Linear Gray",
            CGColorSpace.itur_2020 as String: "Rec. 2020",
            CGColorSpace.itur_709 as String: "Rec. 709",
        ]
        if let name = known[rawName] {
            return name
        }
        return rawName.replacingOccurrences(of: "kCGColorSpace", with: "")
    }

    private static func loadSVG(_ url: URL) throws -> SourceImage {
        guard let image = NSImage(contentsOf: url),
              image.size.width > 0, image.size.height > 0
        else {
            throw SourceLoadError.unreadable(url.lastPathComponent)
        }
        return SourceImage(
            url: url,
            kind: .svg,
            content: .vector(image),
            width: image.size.width,
            height: image.size.height,
            hasAlpha: true,
            colorSpaceName: nil,
            isSRGB: true,
            bitsPerComponent: 8
        )
    }
}

// MARK: - Requirement checks

enum ValidationLevel {
    case ok, info, warning, error
}

struct ValidationItem: Identifiable {
    let id = UUID()
    let level: ValidationLevel
    let message: String

    init(_ level: ValidationLevel, _ message: String) {
        self.level = level
        self.message = message
    }
}

struct ValidationResult {
    var items: [ValidationItem]
    var canMakeICO: Bool
    var canMakeICNS: Bool
}

extension SourceImage {
    static let minimumICOSize = 256
    static let minimumICNSSize = 1024

    func validate() -> ValidationResult {
        var items: [ValidationItem] = []
        var ico = true
        var icns = true

        let diff = abs(width - height) / max(width, height)
        if diff > 0.005 {
            let w = Self.format(width)
            let h = Self.format(height)
            items.append(.init(.error, String(localized: "Not square (\(w) × \(h)). Make the width and height equal.")))
            ico = false
            icns = false
        } else {
            items.append(.init(.ok, String(localized: "The image is square")))
        }

        switch kind {
        case .svg:
            items.append(.init(.ok, String(localized: "SVG (vector): each size is drawn directly, without scaling down")))
            items.append(.init(.info, String(localized: "Some SVG features, such as filters, CSS and web fonts, may not render. Check the preview below.")))

        case .png:
            let px = Int(min(width, height))
            let pxText = String(px)  // 桁区切り（1,024）を付けない
            if px < Self.minimumICOSize {
                items.append(.init(.error, String(localized: "\(pxText) px is too small. ICO needs 256 px or more, and ICNS needs 1024 px or more.")))
                ico = false
                icns = false
            } else if px < Self.minimumICNSSize {
                items.append(.init(.warning, String(localized: "\(pxText) px is too small for ICNS (1024 px or more required). ICO can still be created.")))
                icns = false
            } else {
                items.append(.init(.ok, String(localized: "\(pxText) px (1024 px or more)")))
            }

            if hasAlpha {
                items.append(.init(.ok, String(localized: "Has an alpha channel (transparency)")))
            } else {
                items.append(.init(.warning, String(localized: "No alpha channel (transparency). The icon corners will appear square.")))
            }

            if isSRGB {
                items.append(.init(.ok, String(localized: "Color space is sRGB")))
            } else {
                let space = colorSpaceName ?? String(localized: "unknown")
                items.append(.init(.warning, String(localized: "Color space is not sRGB (\(space)). It will be converted to sRGB.")))
            }
        }

        return ValidationResult(items: items, canMakeICO: ico, canMakeICNS: icns)
    }
}
