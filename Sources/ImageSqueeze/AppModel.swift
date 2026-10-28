import AppKit
import Foundation
import ImageIO
import Observation
import UniformTypeIdentifiers

@MainActor
@Observable
final class ImageItem: Identifiable {
    enum Status: Equatable {
        case pending, processing, done, failed(String)
    }

    let id = UUID()
    var url: URL
    let relativeDir: String
    var originalBytes: Int64
    var width = 0
    var height = 0
    var thumbnail: NSImage?
    var status: Status = .pending
    var outputURL: URL?
    var outputBytes: Int64?
    var outputWidth = 0
    var outputHeight = 0
    var note: String?

    init(url: URL, relativeDir: String) {
        self.url = url
        self.relativeDir = relativeDir
        originalBytes = ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? NSNumber)?.int64Value ?? 0
    }

    var name: String { url.lastPathComponent }

    var saving: Double? {
        guard let o = outputBytes, originalBytes > 0 else { return nil }
        return 1 - Double(o) / Double(originalBytes)
    }

    func reset() {
        status = .pending
        outputURL = nil
        outputBytes = nil
        note = nil
    }
}

@MainActor
@Observable
final class AppModel {
    var items: [ImageItem] = []
    var settings: Settings {
        didSet {
            // A hand edit of any compression parameter (without picking a preset) turns the preset into 自定义.
            if settings.preset != nil && settings.preset == oldValue.preset && settings.tuning != oldValue.tuning {
                settings.preset = nil
            }
            settings.save()
        }
    }
    var isProcessing = false
    var language = AppLanguage.load() {
        didSet {
            language.save()
            L10n.isChinese = language.isChinese
        }
    }
    private var runTask: Task<Void, Never>?

    static let supportedExtensions: Set<String> = [
        "jpg", "jpeg", "jpe", "jfif", "png", "gif", "webp", "svg", "heic", "heif", "avif", "tif", "tiff",
        "bmp", "ico", "icns", "psd", "jp2", "j2k", "tga", "exr", "hdr",
        "dng", "cr2", "cr3", "nef", "arw", "raf", "orf", "rw2",
    ]

    init() {
        settings = Settings.load()
    }

    // MARK: Stats

    var doneItems: [ImageItem] { items.filter { $0.status == .done } }
    var completedCount: Int { items.filter { $0.status == .done || { if case .failed = $0.status { return true }; return false }($0) }.count }
    var totalOriginal: Int64 { doneItems.reduce(0) { $0 + $1.originalBytes } }
    var totalOutput: Int64 { doneItems.reduce(0) { $0 + ($1.outputBytes ?? 0) } }
    var allDone: Bool { !items.isEmpty && items.allSatisfy { $0.status == .done } }

    // MARK: Adding files

    func add(_ urls: [URL]) {
        var known = Set(items.map { $0.url.standardizedFileURL.path })
        var added: [ImageItem] = []
        let fm = FileManager.default

        func append(_ url: URL, rel: String) {
            let key = url.standardizedFileURL.path
            guard !known.contains(key) else { return }
            known.insert(key)
            added.append(ImageItem(url: url, relativeDir: rel))
        }

        for url in urls {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                let parent = url.deletingLastPathComponent().resolvingSymlinksInPath().path
                let en = fm.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey],
                                       options: [.skipsHiddenFiles, .skipsPackageDescendants])
                while let file = en?.nextObject() as? URL {
                    guard isSupported(file) else { continue }
                    // Skip our own previous outputs when re-scanning a folder.
                    if !settings.suffix.isEmpty && file.deletingPathExtension().lastPathComponent.hasSuffix(settings.suffix) { continue }
                    let dir = file.deletingLastPathComponent().resolvingSymlinksInPath().path
                    let rel = dir.hasPrefix(parent + "/") ? String(dir.dropFirst(parent.count + 1)) : url.lastPathComponent
                    append(file, rel: rel)
                }
            } else if isSupported(url) {
                append(url, rel: "")
            }
        }
        items.append(contentsOf: added)
        for item in added { loadThumbnail(item) }
    }

    private func isSupported(_ url: URL) -> Bool {
        Self.supportedExtensions.contains(url.pathExtension.lowercased())
    }

    private func loadThumbnail(_ item: ImageItem) {
        let url = item.url
        Task.detached(priority: .utility) {
            let (thumb, w, h) = Self.makeThumbnail(url)
            await MainActor.run {
                item.width = w
                item.height = h
                if let thumb { item.thumbnail = NSImage(cgImage: thumb, size: .zero) }
            }
        }
    }

    nonisolated static func makeThumbnail(_ url: URL) -> (CGImage?, Int, Int) {
        if let src = CGImageSourceCreateWithURL(url as CFURL, nil) {
            let opts: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 96,
            ]
            let thumb = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
            let (w, h) = Engine.pixelSize(url)
            if thumb != nil || w > 0 { return (thumb, w, h) }
        }
        if let ns = NSImage(contentsOf: url) {
            var rect = CGRect(origin: .zero, size: CGSize(width: 96, height: 96 * ns.size.height / max(1, ns.size.width)))
            return (ns.cgImage(forProposedRect: &rect, context: nil, hints: nil), Int(ns.size.width), Int(ns.size.height))
        }
        return (nil, 0, 0)
    }

    func openPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = Self.supportedExtensions.compactMap { UTType(filenameExtension: $0) } + [.folder]
        panel.prompt = L("添加", "Add")
        if panel.runModal() == .OK { add(panel.urls) }
    }

    @discardableResult
    func chooseOutputFolder() -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = L("选择", "Choose")
        panel.message = L("选择压缩后图片的保存位置", "Choose where to save compressed images")
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        settings.customFolder = url.path
        return true
    }

    func remove(_ ids: Set<ImageItem.ID>) {
        guard !isProcessing else { return }
        items.removeAll { ids.contains($0.id) }
    }

    func clear() {
        guard !isProcessing else { return }
        items.removeAll()
    }

    // MARK: Processing

    func start() {
        guard !isProcessing, !items.isEmpty else { return }
        if settings.location == .customFolder && settings.customFolder == nil && !chooseOutputFolder() { return }
        if settings.location == .overwrite {
            let alert = NSAlert()
            alert.messageText = L("覆盖原文件？", "Overwrite original files?")
            alert.informativeText = L("压缩后的图片将替换原文件，原文件会被移到废纸篓，可以从废纸篓恢复。", "Compressed images will replace the originals. Originals are moved to the Trash and can be restored from there.")
            alert.addButton(withTitle: L("覆盖", "Overwrite"))
            alert.addButton(withTitle: L("取消", "Cancel"))
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }

        // Run pending/failed items; if everything is already done, re-run all with the current settings.
        var todo = items.filter { $0.status != .done }
        if todo.isEmpty { todo = items }
        todo.forEach { $0.reset() }

        isProcessing = true
        let settings = self.settings
        let limit = max(1, settings.concurrency)
        runTask = Task {
            await withTaskGroup(of: Void.self) { group in
                var next = 0
                while next < min(limit, todo.count) {
                    let item = todo[next]
                    group.addTask { await Self.run(item, settings) }
                    next += 1
                }
                while await group.next() != nil {
                    if Task.isCancelled { continue }
                    if next < todo.count {
                        let item = todo[next]
                        group.addTask { await Self.run(item, settings) }
                        next += 1
                    }
                }
            }
            isProcessing = false
            if !NSApp.isActive { NSApp.requestUserAttention(.informationalRequest) }
        }
    }

    func stop() {
        runTask?.cancel()
    }

    nonisolated private static func run(_ item: ImageItem, _ settings: Settings) async {
        let (url, rel) = await MainActor.run { () -> (URL, String) in
            item.status = .processing
            return (item.url, item.relativeDir)
        }
        let result: Result<ProcessResult, Error> = await Task.detached(priority: .userInitiated) {
            Result { try Engine(settings: settings).process(url, relativeDir: rel) }
        }.value
        await MainActor.run {
            switch result {
            case .success(let r):
                item.outputURL = r.outputURL
                item.outputBytes = r.bytes
                item.outputWidth = r.width
                item.outputHeight = r.height
                item.note = r.note
                item.status = .done
                if settings.location == .overwrite { item.url = r.outputURL }
            case .failure(let e):
                item.status = .failed(e.localizedDescription)
            }
        }
    }
}
