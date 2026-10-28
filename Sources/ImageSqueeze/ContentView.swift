import AppKit
import SwiftUI

enum Format {
    /// Decimal units like Finder, but the same in both interface languages
    /// (ByteCountFormatter follows the system locale and would print "字节" in the English UI).
    static func bytes(_ n: Int64) -> String {
        let v = Double(n)
        switch v {
        case ..<1000: return "\(n) B"
        case ..<1_000_000: return String(format: "%.0f KB", v / 1000)
        case ..<1_000_000_000: return String(format: "%.1f MB", v / 1_000_000)
        default: return String(format: "%.2f GB", v / 1_000_000_000)
        }
    }

    static func percent(_ v: Double) -> String {
        String(format: "%.0f%%", v * 100)
    }
}

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var showInspector = true
    @State private var selection = Set<ImageItem.ID>()
    @State private var dropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if model.items.isEmpty {
                    DropZoneView(targeted: dropTargeted)
                } else {
                    FileTableView(selection: $selection)
                        .overlay {
                            if dropTargeted {
                                RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(Color.accentColor, lineWidth: 3)
                                    .padding(4)
                                    .allowsHitTesting(false)
                            }
                        }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .dropDestination(for: URL.self) { urls, _ in
                model.add(urls)
                return true
            } isTargeted: { dropTargeted = $0 }

            Divider()
            StatusBar()
        }
        .inspector(isPresented: $showInspector) {
            SettingsPanel()
                .inspectorColumnWidth(min: 310, ideal: 350, max: 460)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { model.openPanel() } label: { Label(L("添加", "Add"), systemImage: "plus") }
                    .help(L("添加图片或文件夹（⌘O）", "Add images or folders (⌘O)"))
                Button { model.clear(); selection.removeAll() } label: { Label(L("清空", "Clear"), systemImage: "trash") }
                    .help(L("清空列表", "Clear list"))
                    .disabled(model.items.isEmpty || model.isProcessing)
                if model.isProcessing {
                    Button { model.stop() } label: { Label(L("停止", "Stop"), systemImage: "stop.fill") }
                        .help(L("完成当前图片后停止", "Stop after the current images finish"))
                } else {
                    Button { model.start() } label: {
                        Label(model.allDone ? L("重新压缩", "Compress Again") : L("开始压缩", "Compress"), systemImage: "bolt.fill")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.items.isEmpty)
                    .keyboardShortcut(.return, modifiers: .command)
                    .help(L("开始压缩（⌘↩）", "Start compressing (⌘↩)"))
                }
                Button { showInspector.toggle() } label: { Label(L("设置", "Settings"), systemImage: "sidebar.right") }
                    .help(L("显示/隐藏设置面板", "Show/hide settings"))
            }
        }
        .navigationTitle("ImageSqueeze")
        .navigationSubtitle(model.items.isEmpty ? L("本地图片压缩", "Local image compression") : L("\(model.items.count) 张图片", "\(model.items.count) images"))
    }
}

struct DropZoneView: View {
    @Environment(AppModel.self) private var model
    let targeted: Bool

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "photo.stack")
                .font(.system(size: 54, weight: .light))
                .foregroundStyle(targeted ? Color.accentColor : .secondary)
            VStack(spacing: 6) {
                Text(L("拖放图片或文件夹到这里", "Drop images or folders here"))
                    .font(.title2.weight(.semibold))
                Text("JPEG · PNG · WebP · AVIF · HEIC · GIF · SVG · TIFF · BMP · RAW …")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Button(L("选择文件…", "Choose Files…")) { model.openPanel() }
                .controlSize(.large)
            Label(L("所有处理均在本机完成，图片不会上传给任何人", "Everything runs on this Mac — your images are never uploaded"), systemImage: "lock.shield")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                .foregroundStyle(targeted ? Color.accentColor : Color.secondary.opacity(0.35))
                .background(RoundedRectangle(cornerRadius: 16).fill(targeted ? Color.accentColor.opacity(0.06) : .clear))
                .padding(20)
        }
    }
}

struct FileTableView: View {
    @Environment(AppModel.self) private var model
    @Binding var selection: Set<ImageItem.ID>

    var body: some View {
        Table(model.items, selection: $selection) {
            TableColumn(L("文件", "File")) { item in
                HStack(spacing: 10) {
                    Thumbnail(image: item.thumbnail)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name).lineLimit(1).truncationMode(.middle)
                        Text(dimensions(item))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .help(item.url.path)
            }
            .width(min: 220, ideal: 320)

            TableColumn(L("原始大小", "Original")) { item in
                Text(Format.bytes(item.originalBytes)).monospacedDigit().foregroundStyle(.secondary)
            }
            .width(min: 70, ideal: 85)

            TableColumn(L("压缩后", "Compressed")) { item in
                Text(item.outputBytes.map(Format.bytes) ?? "—").monospacedDigit()
            }
            .width(min: 70, ideal: 85)

            TableColumn(L("节省", "Saved")) { item in
                SavingBadge(saving: item.saving)
            }
            .width(min: 60, ideal: 70)

            TableColumn(L("状态", "Status")) { item in
                StatusCell(item: item)
            }
            .width(min: 90, ideal: 160)
        }
        .contextMenu(forSelectionType: ImageItem.ID.self) { ids in
            let picked = model.items.filter { ids.contains($0.id) }
            Button(L("在 Finder 中显示结果", "Show Result in Finder")) {
                NSWorkspace.shared.activateFileViewerSelecting(picked.compactMap(\.outputURL))
            }
            .disabled(picked.allSatisfy { $0.outputURL == nil })
            Button(L("在 Finder 中显示原图", "Show Original in Finder")) {
                NSWorkspace.shared.activateFileViewerSelecting(picked.map(\.url))
            }
            Divider()
            Button(L("从列表移除", "Remove from List")) {
                model.remove(ids)
                selection.subtract(ids)
            }
            .disabled(model.isProcessing)
        } primaryAction: { ids in
            for item in model.items where ids.contains(item.id) {
                NSWorkspace.shared.open(item.outputURL ?? item.url)
            }
        }
        .onDeleteCommand {
            model.remove(selection)
            selection.removeAll()
        }
    }

    private func dimensions(_ item: ImageItem) -> String {
        guard item.width > 0 else { return item.url.pathExtension.uppercased() }
        var s = "\(item.width)×\(item.height)"
        if item.status == .done, item.outputWidth > 0, item.outputWidth != item.width || item.outputHeight != item.height {
            s += " → \(item.outputWidth)×\(item.outputHeight)"
        }
        return s
    }
}

struct Thumbnail: View {
    let image: NSImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5).fill(.quaternary)
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "photo").foregroundStyle(.secondary)
            }
        }
        .frame(width: 32, height: 32)
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}

struct SavingBadge: View {
    let saving: Double?

    var body: some View {
        if let saving {
            Text(saving >= 0 ? "-" + Format.percent(saving) : "+" + Format.percent(-saving))
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(saving > 0.005 ? Color.green : (saving < -0.005 ? Color.orange : .secondary))
        } else {
            Text("—").foregroundStyle(.tertiary)
        }
    }
}

struct StatusCell: View {
    let item: ImageItem

    var body: some View {
        switch item.status {
        case .pending:
            Text(L("等待中", "Waiting")).foregroundStyle(.secondary)
        case .processing:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(L("处理中…", "Processing…")).foregroundStyle(.secondary)
            }
        case .done:
            HStack(spacing: 4) {
                Image(systemName: item.note == nil ? "checkmark.circle.fill" : "info.circle.fill")
                    .foregroundStyle(item.note == nil ? .green : .blue)
                Text(item.note ?? L("完成", "Done")).lineLimit(1).foregroundStyle(item.note == nil ? .primary : .secondary)
            }
            .help(item.note ?? (item.outputURL?.path ?? ""))
        case .failed(let message):
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                Text(message).lineLimit(1).foregroundStyle(.secondary)
            }
            .help(message)
        }
    }
}

struct StatusBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 14) {
            Label(L("本地处理", "On-device"), systemImage: "lock.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
                .help(L("所有图片处理均在本机完成，不会联网上传", "All processing happens on this Mac; nothing is uploaded"))

            if model.isProcessing {
                ProgressView(value: Double(model.completedCount), total: Double(max(1, model.items.count)))
                    .frame(maxWidth: 220)
                Text("\(model.completedCount)/\(model.items.count)")
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }

            Spacer()

            if model.totalOriginal > 0 {
                let saved = 1 - Double(model.totalOutput) / Double(model.totalOriginal)
                Text("\(Format.bytes(model.totalOriginal)) → \(Format.bytes(model.totalOutput))")
                    .font(.callout).monospacedDigit()
                Text(L("节省 ", "Saved ") + "\(Format.bytes(model.totalOriginal - model.totalOutput)) (\(Format.percent(saved)))")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(saved > 0 ? .green : .orange)
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting(model.doneItems.compactMap(\.outputURL))
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.borderless)
                .help(L("在 Finder 中显示输出文件", "Show output files in Finder"))
            } else if !model.items.isEmpty {
                Text(L("共 \(model.items.count) 张", "\(model.items.count) images") + " · \(Format.bytes(model.items.reduce(0) { $0 + $1.originalBytes }))")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.bar)
    }
}
