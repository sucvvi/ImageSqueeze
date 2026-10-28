import Foundation

enum OutputFormat: String, CaseIterable, Codable, Identifiable {
    case original, jpeg, png, webp, avif, heic, gif, tiff, svg

    var id: String { rawValue }

    /// Formats offered in the picker (SVG can only be kept as SVG).
    static let selectable: [OutputFormat] = [.original, .jpeg, .png, .webp, .avif, .heic, .gif, .tiff]

    var label: String {
        switch self {
        case .original: return L("保持原格式", "Keep Original")
        case .jpeg: return "JPEG"
        case .png: return "PNG"
        case .webp: return "WebP"
        case .avif: return "AVIF"
        case .heic: return "HEIC"
        case .gif: return "GIF"
        case .tiff: return "TIFF"
        case .svg: return "SVG"
        }
    }

    var ext: String {
        switch self {
        case .original: return ""
        case .jpeg: return "jpg"
        case .png: return "png"
        case .webp: return "webp"
        case .avif: return "avif"
        case .heic: return "heic"
        case .gif: return "gif"
        case .tiff: return "tiff"
        case .svg: return "svg"
        }
    }

    var hint: String {
        switch self {
        case .original: return L("按源文件格式输出：JPEG 用 MozJPEG，PNG 用 pngquant + OxiPNG，GIF 用 Gifsicle，SVG 用 SVGO。", "Each file keeps its format: JPEG via MozJPEG, PNG via pngquant + OxiPNG, GIF via Gifsicle, SVG via SVGO.")
        case .jpeg: return L("MozJPEG 编码，兼容性最好，适合照片。透明区域会填充背景色。", "MozJPEG encoder. Best compatibility, ideal for photos. Transparent areas are filled with the background color.")
        case .png: return L("pngquant 有损量化 + OxiPNG 无损优化，适合截图、图标、透明图。", "pngquant lossy quantization + OxiPNG lossless optimization. Ideal for screenshots, icons and transparent images.")
        case .webp: return L("libwebp 编码，体积通常比 JPEG 小 25–35%，支持透明。", "libwebp encoder. Usually 25–35% smaller than JPEG, supports transparency.")
        case .avif: return L("系统 ImageIO 编码，压缩率最高，较新的浏览器支持。", "macOS ImageIO encoder. Best compression, supported by modern browsers.")
        case .heic: return L("系统 ImageIO 编码，Apple 设备原生格式。", "macOS ImageIO encoder. Native format on Apple devices.")
        case .gif: return L("Gifsicle 优化，最多 256 色。", "Optimized with Gifsicle, up to 256 colors.")
        case .tiff: return L("LZW 无损压缩，适合印刷存档。", "LZW lossless compression, good for print and archiving.")
        case .svg: return L("SVGO 优化矢量图。", "Vector graphics optimized with SVGO.")
        }
    }
}

enum CompressMode: String, CaseIterable, Codable, Identifiable {
    case quality, targetSize, lossless
    var id: String { rawValue }
    var label: String {
        switch self {
        case .quality: return L("按质量", "Quality")
        case .targetSize: return L("指定大小", "Target Size")
        case .lossless: return L("无损", "Lossless")
        }
    }
}

enum ResizeMode: String, CaseIterable, Codable, Identifiable {
    case none, percent, fit, width, height, exact
    var id: String { rawValue }
    var label: String {
        switch self {
        case .none: return L("不调整", "Don't Resize")
        case .percent: return L("按百分比缩放", "Scale by Percentage")
        case .fit: return L("限制最大宽高", "Fit Within")
        case .width: return L("指定宽度", "Set Width")
        case .height: return L("指定高度", "Set Height")
        case .exact: return L("精确尺寸", "Exact Size")
        }
    }
}

enum OutputLocation: String, CaseIterable, Codable, Identifiable {
    case sameFolder, customFolder, overwrite
    var id: String { rawValue }
    var label: String {
        switch self {
        case .sameFolder: return L("原文件夹（添加后缀）", "Same Folder (add suffix)")
        case .customFolder: return L("指定文件夹", "Choose Folder")
        case .overwrite: return L("覆盖原文件", "Overwrite Original")
        }
    }
}

enum PNGEngine: String, CaseIterable, Codable, Identifiable {
    case oxipng, pngcrush
    var id: String { rawValue }
    var label: String { self == .oxipng ? "OxiPNG" : "pngcrush" }
}

enum SizeUnit: String, CaseIterable, Codable, Identifiable {
    case kb = "KB", mb = "MB"
    var id: String { rawValue }
}

struct Settings: Codable, Equatable {
    var format: OutputFormat = .original
    var compressMode: CompressMode = .quality
    var quality: Double = 80
    /// Upper quality bound for the target-size search; kept separate from `quality` so the search can use the whole budget.
    var targetQuality: Double = 95
    var targetSize: Double = 500
    var targetUnit: SizeUnit = .kb

    var resizeMode: ResizeMode = .none
    var resizeWidth: Int = 1920
    var resizeHeight: Int = 1080
    var resizePercent: Double = 50
    var allowUpscale = false
    var exactCrop = true

    var stripMetadata = true
    var progressiveJPEG = true
    var chromaSubsampling = true
    var pngLossy = true
    var pngColors = 256
    var pngEngine: PNGEngine = .oxipng
    var oxipngLevel = 3
    var webpMethod = 6
    var gifLossy = 30
    var svgPrecision = 3
    var backgroundRGB: [Double] = [1, 1, 1]
    var keepLargerOriginal = true
    var concurrency = max(1, ProcessInfo.processInfo.activeProcessorCount - 1)

    var location: OutputLocation = .sameFolder
    var suffix = "_min"
    var customFolder: String?

    /// The preset the user picked; nil means "自定义". Editing any `tuning` field by hand clears it (see AppModel).
    var preset: Preset? = .balanced

    var targetBytes: Int64 {
        Int64(targetSize * (targetUnit == .kb ? 1024 : 1024 * 1024))
    }

    /// The compression parameters a preset controls. Output format, size and location are not part of a preset.
    struct Tuning: Equatable {
        var lossless: Bool
        var quality: Double
        var targetQuality: Double
        var progressiveJPEG: Bool
        var chromaSubsampling: Bool
        var pngLossy: Bool
        var pngColors: Int
        var pngEngine: PNGEngine
        var oxipngLevel: Int
        var webpMethod: Int
        var gifLossy: Int
        var svgPrecision: Int
    }

    var tuning: Tuning {
        get {
            Tuning(lossless: compressMode == .lossless, quality: quality, targetQuality: targetQuality,
                   progressiveJPEG: progressiveJPEG, chromaSubsampling: chromaSubsampling, pngLossy: pngLossy,
                   pngColors: pngColors, pngEngine: pngEngine, oxipngLevel: oxipngLevel, webpMethod: webpMethod,
                   gifLossy: gifLossy, svgPrecision: svgPrecision)
        }
        set {
            // Presets don't choose between 按质量 and 指定大小; they only switch into or out of 无损.
            if newValue.lossless { compressMode = .lossless } else if compressMode == .lossless { compressMode = .quality }
            quality = newValue.quality; targetQuality = newValue.targetQuality
            progressiveJPEG = newValue.progressiveJPEG; chromaSubsampling = newValue.chromaSubsampling
            pngLossy = newValue.pngLossy; pngColors = newValue.pngColors; pngEngine = newValue.pngEngine
            oxipngLevel = newValue.oxipngLevel; webpMethod = newValue.webpMethod
            gifLossy = newValue.gifLossy; svgPrecision = newValue.svgPrecision
        }
    }

    private static let key = "ImageSqueeze.settings.v1"

    static func load() -> Settings {
        var s = UserDefaults.standard.data(forKey: key).flatMap(decode) ?? Settings()
        // Settings saved before presets were stored (or edited elsewhere) may not match the recorded preset.
        if let p = s.preset, p.tuning != s.tuning { s.preset = nil }
        return s
    }

    /// Decodes JSON that may contain only some keys; missing keys keep their default values,
    /// so settings saved by an older version survive new fields being added.
    static func decode(_ data: Data) -> Settings? {
        guard let partial = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let defaults = try? JSONSerialization.jsonObject(with: JSONEncoder().encode(Settings())) as? [String: Any],
              let merged = try? JSONSerialization.data(withJSONObject: defaults.merging(partial) { _, new in new }) else { return nil }
        return try? JSONDecoder().decode(Settings.self, from: merged)
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}

enum Preset: String, CaseIterable, Codable, Identifiable {
    case balanced, smallest, highQuality, lossless
    var id: String { rawValue }
    var label: String {
        switch self {
        case .balanced: return L("均衡（推荐）", "Balanced (Recommended)")
        case .smallest: return L("极致压缩", "Smallest")
        case .highQuality: return L("高画质", "High Quality")
        case .lossless: return L("无损优化", "Lossless")
        }
    }

    var summary: String {
        switch self {
        case .balanced: return L("质量 80 · PNG 256 色 · GIF 有损 30", "Quality 80 · PNG 256 colors · GIF lossy 30")
        case .smallest: return L("质量 60 · PNG 128 色 · GIF 有损 80", "Quality 60 · PNG 128 colors · GIF lossy 80")
        case .highQuality: return L("质量 92 · 不做色度抽样 · GIF 有损 10", "Quality 92 · no chroma subsampling · GIF lossy 10")
        case .lossless: return L("不损失画质，仅无损优化", "No quality loss, lossless optimization only")
        }
    }

    var tuning: Settings.Tuning {
        switch self {
        case .balanced:
            return .init(lossless: false, quality: 80, targetQuality: 95, progressiveJPEG: true, chromaSubsampling: true,
                         pngLossy: true, pngColors: 256, pngEngine: .oxipng, oxipngLevel: 3, webpMethod: 6, gifLossy: 30, svgPrecision: 3)
        case .smallest:
            return .init(lossless: false, quality: 60, targetQuality: 85, progressiveJPEG: true, chromaSubsampling: true,
                         pngLossy: true, pngColors: 128, pngEngine: .oxipng, oxipngLevel: 4, webpMethod: 6, gifLossy: 80, svgPrecision: 2)
        case .highQuality:
            return .init(lossless: false, quality: 92, targetQuality: 100, progressiveJPEG: true, chromaSubsampling: false,
                         pngLossy: true, pngColors: 256, pngEngine: .oxipng, oxipngLevel: 3, webpMethod: 6, gifLossy: 10, svgPrecision: 4)
        case .lossless:
            return .init(lossless: true, quality: 80, targetQuality: 95, progressiveJPEG: true, chromaSubsampling: true,
                         pngLossy: false, pngColors: 256, pngEngine: .oxipng, oxipngLevel: 4, webpMethod: 6, gifLossy: 0, svgPrecision: 3)
        }
    }

    func apply(to s: inout Settings) {
        s.tuning = tuning
        s.preset = self
    }
}
