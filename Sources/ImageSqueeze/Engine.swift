import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct ProcessResult {
    var outputURL: URL
    var bytes: Int64
    var width: Int
    var height: Int
    var note: String?
}

enum EngineError: LocalizedError {
    case cannotDecode
    case toolMissing(String)
    case toolFailed(String, String)
    case encodeFailed(String)
    case noOutputFolder

    var errorDescription: String? {
        switch self {
        case .cannotDecode: return L("无法读取该图片", "Can't read this image")
        case .toolMissing(let t): return L("缺少压缩引擎 \(t)", "Missing engine \(t)")
        case .toolFailed(let t, let m): return L("\(t) 处理失败：", "\(t) failed: ") + m.trimmingCharacters(in: .whitespacesAndNewlines).prefix(160)
        case .encodeFailed(let f): return L("无法编码为 \(f)", "Can't encode as \(f)")
        case .noOutputFolder: return L("未选择输出文件夹", "No output folder selected")
        }
    }
}

/// Format of the input file, decided by extension.
enum SourceKind: Equatable {
    case jpeg, png, gif, webp, svg, heic, avif, tiff, other

    init(url: URL) {
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg", "jpe", "jfif": self = .jpeg
        case "png": self = .png
        case "gif": self = .gif
        case "webp": self = .webp
        case "svg": self = .svg
        case "heic", "heif": self = .heic
        case "avif": self = .avif
        case "tif", "tiff": self = .tiff
        default: self = .other
        }
    }

    var sameFormat: OutputFormat? {
        switch self {
        case .jpeg: return .jpeg
        case .png: return .png
        case .gif: return .gif
        case .webp: return .webp
        case .svg: return .svg
        case .heic: return .heic
        case .avif: return .avif
        case .tiff: return .tiff
        case .other: return nil
        }
    }
}

/// Decoded raster input with EXIF orientation already applied.
struct RasterSource {
    var image: CGImage
    var hasAlpha: Bool
    var properties: [CFString: Any]
}

/// Processes one image entirely on this Mac: decode with ImageIO, resize with Core Graphics,
/// encode with the bundled engines (MozJPEG, pngquant, OxiPNG, pngcrush, libwebp, Gifsicle, SVGO) or ImageIO.
final class Engine {
    private let s: Settings
    private let work: URL
    private var counter = 0
    private let fm = FileManager.default

    init(settings: Settings) throws {
        s = settings
        work = fm.temporaryDirectory.appendingPathComponent("ImageSqueeze-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
    }

    deinit { try? fm.removeItem(at: work) }

    private func tmp(_ ext: String) -> URL {
        counter += 1
        return work.appendingPathComponent("t\(counter).\(ext)")
    }

    private func size(_ url: URL) -> Int64 {
        ((try? fm.attributesOfItem(atPath: url.path)[.size]) as? NSNumber)?.int64Value ?? 0
    }

    // MARK: - Entry point

    func process(_ input: URL, relativeDir: String) throws -> ProcessResult {
        let originalBytes = size(input)
        let kind = SourceKind(url: input)
        let frames = Self.frameCount(input)

        var produced: URL
        var target: OutputFormat
        var width = 0, height = 0
        var resized = false
        var notes: [String] = []

        if kind == .svg && (s.format == .original || s.format == .svg) {
            target = .svg
            let (out, usedSVGO) = try processSVG(input)
            produced = out
            if !usedSVGO { notes.append(L("SVGO 不可用，已使用基础精简", "SVGO unavailable, used basic minification")) }
        } else if kind == .gif && frames > 1 && (s.format == .original || s.format == .gif) {
            target = .gif
            let r = try processAnimatedGIF(input)
            produced = r.url; width = r.width; height = r.height; resized = r.resized
            if let n = r.note { notes.append(n) }
        } else {
            let src = try loadRaster(input, kind: kind)
            target = s.format == .original ? (kind.sameFormat ?? (src.hasAlpha ? .png : .jpeg)) : s.format
            if frames > 1 { notes.append(L("动图仅保留首帧", "Animation: first frame only")) }
            let r = try processRaster(src, input: input, kind: kind, target: target)
            produced = r.url; width = r.width; height = r.height; resized = r.resized
            if let n = r.note { notes.append(n) }
        }

        var bytes = size(produced)
        let sameFormat = kind.sameFormat == target
        if s.keepLargerOriginal && sameFormat && !resized && bytes >= originalBytes {
            notes = [L("已是最优，保留原图", "Already optimal, kept original")]
            if s.location == .overwrite {
                let (w, h) = Self.pixelSize(input)
                return ProcessResult(outputURL: input, bytes: originalBytes, width: w, height: h, note: notes.first)
            }
            let copy = tmp(input.pathExtension)
            try fm.copyItem(at: input, to: copy)
            produced = copy
            bytes = originalBytes
        }

        if width == 0 { (width, height) = Self.pixelSize(produced) }
        let ext = sameFormat ? input.pathExtension : target.ext
        let dest = try place(produced, input: input, ext: ext, relativeDir: relativeDir)
        return ProcessResult(outputURL: dest, bytes: bytes, width: width, height: height,
                             note: notes.isEmpty ? nil : notes.joined(separator: "；"))
    }

    // MARK: - Output placement

    private func place(_ produced: URL, input: URL, ext: String, relativeDir: String) throws -> URL {
        let base = input.deletingPathExtension().lastPathComponent
        var dest: URL
        switch s.location {
        case .sameFolder:
            dest = input.deletingLastPathComponent().appendingPathComponent(base + s.suffix + "." + ext)
        case .customFolder:
            guard let folder = s.customFolder else { throw EngineError.noOutputFolder }
            let dir = URL(fileURLWithPath: folder, isDirectory: true).appendingPathComponent(relativeDir, isDirectory: true)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            dest = dir.appendingPathComponent(base + s.suffix + "." + ext)
        case .overwrite:
            dest = input.deletingLastPathComponent().appendingPathComponent(base + "." + ext)
            if dest.standardizedFileURL != input.standardizedFileURL && fm.fileExists(atPath: dest.path) {
                // Format changed and a file with the new name already exists: never clobber an unrelated file.
                dest = input.deletingLastPathComponent().appendingPathComponent(base + (s.suffix.isEmpty ? "_min" : s.suffix) + "." + ext)
            }
            try fm.trashItem(at: input, resultingItemURL: nil)
        }
        if s.location != .overwrite && dest.standardizedFileURL == input.standardizedFileURL {
            dest = dest.deletingLastPathComponent().appendingPathComponent(base + "_min." + ext)
        }
        if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
        try fm.moveItem(at: produced, to: dest)
        return dest
    }

    // MARK: - SVG

    private func processSVG(_ input: URL) throws -> (URL, Bool) {
        let data = try Data(contentsOf: input)
        let text = String(decoding: data, as: UTF8.self)
        let (out, usedSVGO) = SVGOptimizer.optimize(text, precision: s.svgPrecision)
        let url = tmp("svg")
        try Data(out.utf8).write(to: url)
        return (url, usedSVGO)
    }

    // MARK: - Animated GIF

    private struct Output { var url: URL; var width: Int; var height: Int; var resized: Bool; var note: String? }

    private func processAnimatedGIF(_ input: URL) throws -> Output {
        let (w, h) = Self.pixelSize(input)
        let t = targetDimensions(w, h)
        var geometry: [String] = []
        if t.width != w || t.height != h {
            if t.crop {
                let scale = max(Double(t.width) / Double(w), Double(t.height) / Double(h))
                let cw = Int((Double(t.width) / scale).rounded()), ch = Int((Double(t.height) / scale).rounded())
                geometry += ["--crop", "\((w - cw) / 2),\((h - ch) / 2)+\(cw)x\(ch)"]
            }
            geometry += ["--resize-method", "lanczos3", "--resize", "\(t.width)x\(t.height)"]
        }
        let resized = !geometry.isEmpty

        func run(lossy: Int, colors: Int, extra: [String]) throws -> URL {
            let out = tmp("gif")
            var args = ["-O3", "--no-warnings"]
            if lossy > 0 { args.append("--lossy=\(lossy)") }
            if colors < 256 { args += ["--colors", "\(colors)"] }
            if s.stripMetadata { args += ["--no-comments", "--no-names", "--no-extensions"] }
            args += extra + [input.path, "-o", out.path]
            try Tools.run(.gifsicle, args)
            return out
        }

        switch s.compressMode {
        case .lossless:
            let out = try run(lossy: 0, colors: 256, extra: geometry)
            return Output(url: out, width: t.width, height: t.height, resized: resized)
        case .quality:
            let out = try run(lossy: s.gifLossy, colors: 256, extra: geometry)
            return Output(url: out, width: t.width, height: t.height, resized: resized)
        case .targetSize:
            let limit = s.targetBytes
            var best: URL?
            for (lossy, colors) in [(s.gifLossy, 256), (60, 256), (100, 192), (150, 128), (200, 64), (200, 32)] {
                let out = try run(lossy: lossy, colors: colors, extra: geometry)
                if best == nil || size(out) < size(best!) { best = out }
                if size(out) <= limit {
                    return Output(url: out, width: t.width, height: t.height, resized: resized)
                }
            }
            // Still too big: scale the animation down.
            var scale = 1.0
            for _ in 0..<6 {
                scale *= max(0.4, min(0.9, sqrt(Double(limit) / Double(size(best!))) * 0.95))
                let sw = max(1, Int(Double(t.width) * scale)), sh = max(1, Int(Double(t.height) * scale))
                // Keep any --crop, replace the resize target.
                let extra: [String] = Array(geometry.prefix(while: { $0 != "--resize-method" }))
                    + ["--resize-method", "lanczos3", "--resize", "\(sw)x\(sh)"]
                let out = try run(lossy: 200, colors: 64, extra: extra)
                best = out
                if size(out) <= limit {
                    return Output(url: out, width: sw, height: sh, resized: true)
                }
            }
            let (bw, bh) = Self.pixelSize(best!)
            return Output(url: best!, width: bw, height: bh, resized: true, note: L("未能达到目标大小", "Couldn't reach target size"))
        }
    }

    // MARK: - Raster pipeline

    private func processRaster(_ src: RasterSource, input: URL, kind: SourceKind, target: OutputFormat) throws -> Output {
        let w = src.image.width, h = src.image.height
        let t = targetDimensions(w, h)
        let resized = t.width != w || t.height != h
        var image = src.image
        if resized {
            image = try render(src.image, width: t.width, height: t.height, crop: t.crop, opaque: false, sRGB: false)
        }

        switch s.compressMode {
        case .lossless:
            if !resized, kind.sameFormat == target, let out = try losslessOptimize(input, kind: kind, src: src) {
                return Output(url: out, width: w, height: h, resized: false)
            }
            let out = try encode(image, as: target, quality: 100, lossless: true, src: src, input: input)
            let note = target == .jpeg ? L("JPEG 不支持无损，已使用最高质量", "JPEG can't be lossless, used maximum quality") : nil
            return Output(url: out, width: image.width, height: image.height, resized: resized, note: note)

        case .quality:
            let out = try encode(image, as: target, quality: Int(s.quality), lossless: false, src: src, input: input)
            return Output(url: out, width: image.width, height: image.height, resized: resized)

        case .targetSize:
            return try fitToSize(image, target: target, src: src, input: input, resized: resized)
        }
    }

    /// Re-optimizes a file in its own format without re-encoding pixels.
    private func losslessOptimize(_ input: URL, kind: SourceKind, src: RasterSource) throws -> URL? {
        switch kind {
        case .jpeg:
            let out = tmp("jpg")
            let orientation = (src.properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
            // Stripping EXIF from a rotated photo would lose its orientation, so keep metadata in that case.
            let copy = (s.stripMetadata && orientation == 1) ? "none" : "all"
            var args = ["-copy", copy, "-optimize"]
            if s.progressiveJPEG { args.append("-progressive") }
            args += ["-outfile", out.path, input.path]
            try Tools.run(.jpegtran, args)
            return out
        case .png:
            return try optimizePNG(input, lossy: false, quality: 100, colors: 256)
        default:
            return nil
        }
    }

    /// Finds the best-looking encoding whose size fits `targetBytes`: binary-search quality first,
    /// then shrink dimensions if even the lowest quality is too large.
    private func fitToSize(_ start: CGImage, target: OutputFormat, src: RasterSource, input: URL, resized: Bool) throws -> Output {
        let limit = s.targetBytes
        var image = start
        var didResize = resized
        var smallest: URL?

        for _ in 0..<8 {
            if let hit = try searchCandidates(image, target: target, src: src, input: input, limit: limit, smallest: &smallest) {
                return Output(url: hit, width: image.width, height: image.height, resized: didResize)
            }
            let ratio = max(0.5, min(0.9, sqrt(Double(limit) / Double(max(1, size(smallest!)))) * 0.95))
            let nw = Int(Double(image.width) * ratio), nh = Int(Double(image.height) * ratio)
            if nw < 16 || nh < 16 { break }
            image = try render(image, width: nw, height: nh, crop: false, opaque: false, sRGB: false)
            didResize = true
        }
        let url = smallest!
        let (w, h) = Self.pixelSize(url)
        return Output(url: url, width: w, height: h, resized: didResize, note: L("未能达到目标大小，已输出最小结果", "Couldn't reach target size, saved smallest result"))
    }

    private func searchCandidates(_ image: CGImage, target: OutputFormat, src: RasterSource, input: URL,
                                  limit: Int64, smallest: inout URL?) throws -> URL? {
        func consider(_ url: URL) {
            if smallest == nil || size(url) < size(smallest!) { smallest = url }
        }
        switch target {
        case .jpeg, .webp, .avif, .heic:
            var lo = 5, hi = max(5, Int(s.targetQuality))
            let top = try encode(image, as: target, quality: hi, lossless: false, src: src, input: input)
            consider(top)
            if size(top) <= limit { return top }
            hi -= 1
            var best: URL?
            while lo <= hi {
                let mid = (lo + hi) / 2
                let out = try encode(image, as: target, quality: mid, lossless: false, src: src, input: input)
                consider(out)
                if size(out) <= limit { best = out; lo = mid + 1 } else { hi = mid - 1 }
            }
            return best

        case .png:
            let rgba = try render(image, width: image.width, height: image.height, crop: false, opaque: false, sRGB: true)
            let raw = tmp("png")
            try writeImageIO(rgba, to: raw, type: .png)
            // Candidates are measured cheaply (fast lossless pass / raw pngquant output); the full
            // optimizer only shrinks files, so it runs once on the winner.
            func finish(_ url: URL) throws -> URL {
                let full = try losslessPNG(url, level: s.oxipngLevel)
                return size(full) < size(url) ? full : url
            }
            // Lossless rarely saves more than ~2× over ImageIO's PNG, so skip the probe when it can't fit.
            if size(raw) <= limit * 3 {
                let lossless = try losslessPNG(raw, level: min(1, s.oxipngLevel))
                consider(lossless)
                if size(lossless) <= limit { return try finish(lossless) }
            } else {
                consider(raw)
            }
            for (q, colors) in [(90, 256), (75, 256), (60, 256), (45, 128), (30, 64), (20, 32), (10, 16)] {
                guard let out = try quantizePNG(raw, quality: q, colors: colors, speed: 8) else { continue }
                consider(out)
                if size(out) <= limit {
                    // Redo the winning settings at pngquant's careful speed; keep it if it still fits.
                    if let careful = try quantizePNG(raw, quality: q, colors: colors), size(careful) <= limit {
                        return try finish(careful)
                    }
                    return try finish(out)
                }
                // Fewer colours won't close a gap this large; shrinking the image is the better trade.
                if size(out) > limit * 3 { break }
            }
            return nil

        case .gif:
            for lossy in [s.gifLossy, 80, 150, 200] {
                let out = try encode(image, as: .gif, quality: 0, lossless: false, src: src, input: input, gifLossy: lossy)
                consider(out)
                if size(out) <= limit { return out }
            }
            return nil

        default:
            let out = try encode(image, as: target, quality: 100, lossless: true, src: src, input: input)
            consider(out)
            return size(out) <= limit ? out : nil
        }
    }

    // MARK: - Encoders

    private func encode(_ image: CGImage, as target: OutputFormat, quality: Int, lossless: Bool,
                        src: RasterSource, input: URL, gifLossy: Int? = nil) throws -> URL {
        let q = min(100, max(1, quality))
        switch target {
        case .jpeg:
            let flat = try render(image, width: image.width, height: image.height, crop: false, opaque: true, sRGB: true)
            let ppm = tmp("ppm")
            try writePPM(flat, to: ppm)
            defer { try? fm.removeItem(at: ppm) }
            let out = tmp("jpg")
            var args = ["-quality", "\(q)", "-optimize", s.progressiveJPEG ? "-progressive" : "-baseline"]
            if !s.chromaSubsampling || q >= 95 { args += ["-sample", "1x1"] }
            args += ["-outfile", out.path, ppm.path]
            try Tools.run(.cjpeg, args)
            if !s.stripMetadata { injectMetadata(from: input, into: out, type: .jpeg) }
            return out

        case .png:
            let rgba = try render(image, width: image.width, height: image.height, crop: false, opaque: false, sRGB: true)
            let raw = tmp("png")
            try writeImageIO(rgba, to: raw, type: .png)
            let out = try optimizePNG(raw, lossy: !lossless && s.pngLossy, quality: q, colors: s.pngColors)
            if !s.stripMetadata { injectMetadata(from: input, into: out, type: .png) }
            return out

        case .webp:
            let rgba = try render(image, width: image.width, height: image.height, crop: false, opaque: false, sRGB: true)
            let raw = tmp("png")
            try writeImageIO(rgba, to: raw, type: .png)
            defer { try? fm.removeItem(at: raw) }
            let out = tmp("webp")
            var args = ["-quiet", "-mt", "-m", "\(s.webpMethod)", "-metadata", "none"]
            if lossless { args += ["-lossless", "-z", "\(min(9, s.webpMethod + 3))"] } else { args += ["-q", "\(q)", "-sharp_yuv"] }
            args += [raw.path, "-o", out.path]
            try Tools.run(.cwebp, args)
            return out

        case .avif, .heic:
            let out = tmp(target.ext)
            var opts: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: lossless ? 1.0 : Double(q) / 100]
            if !s.stripMetadata { opts.merge(metadataProperties(src)) { a, _ in a } }
            try writeImageIO(image, to: out, type: target == .avif ? UTType("public.avif")! : .heic, options: opts)
            return out

        case .tiff:
            let out = tmp("tiff")
            var opts: [CFString: Any] = [kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFCompression: 5]] // LZW
            if !s.stripMetadata {
                var meta = metadataProperties(src)
                if var tiff = meta[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
                    tiff[kCGImagePropertyTIFFCompression] = 5
                    meta[kCGImagePropertyTIFFDictionary] = tiff
                }
                opts.merge(meta) { _, b in b }
            }
            try writeImageIO(image, to: out, type: .tiff, options: opts)
            return out

        case .gif:
            let rgba = try render(image, width: image.width, height: image.height, crop: false, opaque: false, sRGB: true)
            let raw = tmp("gif")
            try writeImageIO(rgba, to: raw, type: .gif)
            let out = tmp("gif")
            var args = ["-O3", "--no-warnings"]
            let lossyLevel = lossless ? 0 : (gifLossy ?? s.gifLossy)
            if lossyLevel > 0 { args.append("--lossy=\(lossyLevel)") }
            args += [raw.path, "-o", out.path]
            try Tools.run(.gifsicle, args)
            return out

        case .original, .svg:
            throw EngineError.encodeFailed(target.label)
        }
    }

    private func optimizePNG(_ input: URL, lossy: Bool, quality: Int, colors: Int) throws -> URL {
        var current = input
        if lossy, let quantized = try quantizePNG(input, quality: quality, colors: colors) { current = quantized }
        return try losslessPNG(current, level: s.oxipngLevel)
    }

    /// pngquant palette reduction; nil when pngquant declines (exit 98/99: result would be larger / quality not reached).
    private func quantizePNG(_ input: URL, quality: Int, colors: Int, speed: Int = 3) throws -> URL? {
        let out = tmp("png")
        let code = try Tools.run(.pngquant, ["--force", "--speed", "\(speed)", "--strip", "--quality", "0-\(quality)",
                                             "\(min(256, max(2, colors)))", "--output", out.path, "--", input.path],
                                 okCodes: [0, 98, 99])
        return code == 0 && fm.fileExists(atPath: out.path) ? out : nil
    }

    private func losslessPNG(_ input: URL, level: Int) throws -> URL {
        let out = tmp("png")
        switch s.pngEngine {
        case .oxipng:
            var args = ["-q", "-o", "\(level)", "-a"]
            if s.stripMetadata { args += ["--strip", "safe"] }
            args += ["--out", out.path, input.path]
            try Tools.run(.oxipng, args)
        case .pngcrush:
            var args = ["-q", "-reduce"]
            if s.stripMetadata { args += ["-rem", "alla"] }
            args += [input.path, out.path]
            try Tools.run(.pngcrush, args)
        }
        return out
    }

    // MARK: - Decode / render helpers

    private func loadRaster(_ url: URL, kind: SourceKind) throws -> RasterSource {
        if let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
           CGImageSourceGetCount(source) > 0 {
            let props = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]) ?? [:]
            let w = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
            let h = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
            let opts: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: max(w, h, 1),
                kCGImageSourceShouldCacheImmediately: true,
            ]
            if let img = CGImageSourceCreateThumbnailAtIndex(source, 0, opts as CFDictionary)
                ?? CGImageSourceCreateImageAtIndex(source, 0, nil) {
                return RasterSource(image: img, hasAlpha: Self.hasAlpha(img), properties: props)
            }
        }
        // SVG and anything else NSImage understands: rasterize at its natural size (or the resize target).
        if let ns = NSImage(contentsOf: url), ns.size.width > 0, ns.size.height > 0 {
            let t = targetDimensions(Int(ns.size.width.rounded()), Int(ns.size.height.rounded()), forceUpscale: true)
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: t.width, pixelsHigh: t.height, bitsPerSample: 8,
                                       samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                       bytesPerRow: 0, bitsPerPixel: 0)
            if let rep {
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
                ns.draw(in: NSRect(x: 0, y: 0, width: t.width, height: t.height))
                NSGraphicsContext.restoreGraphicsState()
                if let img = rep.cgImage {
                    return RasterSource(image: img, hasAlpha: true, properties: [:])
                }
            }
        }
        throw EngineError.cannotDecode
    }

    private struct Dimensions { var width: Int; var height: Int; var crop: Bool }

    private func targetDimensions(_ w: Int, _ h: Int, forceUpscale: Bool = false) -> Dimensions {
        guard w > 0, h > 0 else { return Dimensions(width: w, height: h, crop: false) }
        let up = s.allowUpscale || forceUpscale
        func scaled(_ factor: Double) -> Dimensions {
            let f = up ? factor : min(factor, 1)
            return Dimensions(width: max(1, Int((Double(w) * f).rounded())), height: max(1, Int((Double(h) * f).rounded())), crop: false)
        }
        let W = Double(max(1, s.resizeWidth)), H = Double(max(1, s.resizeHeight))
        switch s.resizeMode {
        case .none: return Dimensions(width: w, height: h, crop: false)
        case .percent: return scaled(max(1, s.resizePercent) / 100)
        case .fit: return scaled(min(W / Double(w), H / Double(h)))
        case .width: return scaled(W / Double(w))
        case .height: return scaled(H / Double(h))
        case .exact: return Dimensions(width: Int(W), height: Int(H), crop: s.exactCrop)
        }
    }

    private func render(_ image: CGImage, width: Int, height: Int, crop: Bool, opaque: Bool, sRGB: Bool) throws -> CGImage {
        let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
        var space = srgb
        if !sRGB, let cs = image.colorSpace, cs.model == .rgb { space = cs }
        let info = opaque ? CGImageAlphaInfo.noneSkipLast.rawValue : CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: info)
                ?? CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: srgb, bitmapInfo: info)
        else { throw EngineError.cannotDecode }
        ctx.interpolationQuality = .high
        let full = CGRect(x: 0, y: 0, width: width, height: height)
        if opaque {
            let c = s.backgroundRGB + [1, 1, 1]
            ctx.setFillColor(CGColor(srgbRed: c[0], green: c[1], blue: c[2], alpha: 1))
            ctx.fill(full)
        }
        var rect = full
        if crop {
            let scale = max(Double(width) / Double(image.width), Double(height) / Double(image.height))
            let dw = Double(image.width) * scale, dh = Double(image.height) * scale
            rect = CGRect(x: (Double(width) - dw) / 2, y: (Double(height) - dh) / 2, width: dw, height: dh)
        }
        ctx.draw(image, in: rect)
        guard let out = ctx.makeImage() else { throw EngineError.cannotDecode }
        return out
    }

    /// Writes an opaque RGBX 8-bit image (as produced by `render(opaque: true)`) as binary PPM for cjpeg.
    private func writePPM(_ image: CGImage, to url: URL) throws {
        guard let cf = image.dataProvider?.data, let ptr = CFDataGetBytePtr(cf) else { throw EngineError.encodeFailed("PPM") }
        let w = image.width, h = image.height, bpr = image.bytesPerRow, bpp = image.bitsPerPixel / 8
        var data = Data("P6\n\(w) \(h)\n255\n".utf8)
        data.reserveCapacity(data.count + w * h * 3)
        var row = [UInt8](repeating: 0, count: w * 3)
        for y in 0..<h {
            let base = ptr + y * bpr
            for x in 0..<w {
                let p = base + x * bpp
                row[x * 3] = p[0]; row[x * 3 + 1] = p[1]; row[x * 3 + 2] = p[2]
            }
            data.append(contentsOf: row)
        }
        try data.write(to: url)
    }

    private func writeImageIO(_ image: CGImage, to url: URL, type: UTType, options: [CFString: Any] = [:]) throws {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
            throw EngineError.encodeFailed(type.preferredFilenameExtension ?? type.identifier)
        }
        CGImageDestinationAddImage(dest, image, options as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            throw EngineError.encodeFailed(type.preferredFilenameExtension ?? type.identifier)
        }
    }

    // MARK: - Metadata

    /// Source metadata for ImageIO encoders, with orientation reset because pixels are already rotated.
    private func metadataProperties(_ src: RasterSource) -> [CFString: Any] {
        var props: [CFString: Any] = [:]
        for key in [kCGImagePropertyExifDictionary, kCGImagePropertyGPSDictionary, kCGImagePropertyIPTCDictionary, kCGImagePropertyTIFFDictionary] {
            if let v = src.properties[key] { props[key] = v }
        }
        props[kCGImagePropertyOrientation] = 1
        if var tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            tiff[kCGImagePropertyTIFFOrientation] = 1
            props[kCGImagePropertyTIFFDictionary] = tiff
        }
        return props
    }

    /// Copies EXIF/GPS/IPTC/XMP from the original into an already-compressed file without re-encoding pixels.
    private func injectMetadata(from original: URL, into file: URL, type: UTType) {
        guard let src = CGImageSourceCreateWithURL(original as CFURL, nil),
              let meta = CGImageSourceCopyMetadataAtIndex(src, 0, nil),
              let mutable = CGImageMetadataCreateMutableCopy(meta),
              let target = CGImageSourceCreateWithURL(file as CFURL, nil) else { return }
        CGImageMetadataSetValueMatchingImageProperty(mutable, kCGImagePropertyTIFFDictionary, kCGImagePropertyTIFFOrientation, 1 as CFNumber)
        let out = tmp(file.pathExtension)
        guard let dest = CGImageDestinationCreateWithURL(out as CFURL, type.identifier as CFString, 1, nil) else { return }
        let opts: [CFString: Any] = [kCGImageDestinationMetadata: mutable, kCGImageDestinationMergeMetadata: true]
        if CGImageDestinationCopyImageSource(dest, target, opts as CFDictionary, nil) {
            _ = try? fm.replaceItemAt(file, withItemAt: out)
        }
    }

    // MARK: - Static helpers

    static func hasAlpha(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .first, .last, .premultipliedFirst, .premultipliedLast, .alphaOnly: return true
        default: return false
        }
    }

    static func frameCount(_ url: URL) -> Int {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return 0 }
        return CGImageSourceGetCount(src)
    }

    static func pixelSize(_ url: URL) -> (Int, Int) {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let p = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else { return (0, 0) }
        var w = (p[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
        var h = (p[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
        if let o = (p[kCGImagePropertyOrientation] as? NSNumber)?.intValue, o >= 5 { swap(&w, &h) }
        return (w, h)
    }
}
