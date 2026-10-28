import AppKit
import SwiftUI

struct SettingsPanel: View {
    @Environment(AppModel.self) private var model
    @State private var showAdvanced = false
    @State private var showEngines = false

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                Picker(L("输出格式", "Output Format"), selection: $model.settings.format) {
                    ForEach(OutputFormat.selectable) { Text($0.label).tag($0) }
                }
                Picker(L("预设", "Preset"), selection: presetSelection) {
                    ForEach(Preset.allCases) { Text($0.label).tag(Optional($0)) }
                    Divider()
                    Text(L("自定义", "Custom")).tag(Preset?.none)
                }
                LabeledContent {
                    Button(L("恢复默认", "Reset")) { model.settings = Settings() }
                        .disabled(model.settings == Settings())
                } label: {
                    Text(model.settings.preset?.summary ?? L("已手动调整参数", "Parameters adjusted manually"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text(model.settings.format.hint).font(.caption).foregroundStyle(.secondary)
            }

            Section(L("压缩方式", "Compression")) {
                Picker(L("方式", "Mode"), selection: $model.settings.compressMode) {
                    ForEach(CompressMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                switch model.settings.compressMode {
                case .quality:
                    QualitySlider(title: L("质量", "Quality"), value: $model.settings.quality)
                case .targetSize:
                    HStack {
                        Text(L("目标大小 ≤", "Target size ≤"))
                        LiveNumberField(label: "", value: $model.settings.targetSize)
                            .frame(width: 80)
                        Picker("", selection: $model.settings.targetUnit) {
                            ForEach(SizeUnit.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                    QualitySlider(title: L("最高质量", "Max quality"), value: $model.settings.targetQuality)
                    Text(L("在最高质量以内，自动搜索不超过目标大小的最高质量；仍然过大时会自动缩小尺寸。", "Finds the highest quality (up to the max) that fits the target size; shrinks the image if it still doesn't fit."))
                        .font(.caption).foregroundStyle(.secondary)
                case .lossless:
                    Text(L("不损失任何画质：JPEG 用 jpegtran 重新优化编码，PNG 用 OxiPNG 无损压缩，GIF 用 Gifsicle 优化，WebP 使用无损模式。", "No quality loss: JPEG is re-optimized with jpegtran, PNG compressed losslessly with OxiPNG, GIF optimized with Gifsicle, WebP uses lossless mode."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section(L("尺寸调整", "Resize")) {
                Picker(L("模式", "Mode"), selection: $model.settings.resizeMode) {
                    ForEach(ResizeMode.allCases) { Text($0.label).tag($0) }
                }
                switch model.settings.resizeMode {
                case .none:
                    EmptyView()
                case .percent:
                    HStack {
                        Slider(value: $model.settings.resizePercent, in: 5...200, step: 5)
                        Text("\(Int(model.settings.resizePercent))%").monospacedDigit().frame(width: 44, alignment: .trailing)
                    }
                case .fit, .exact:
                    HStack {
                        NumberField(label: L("宽", "W"), value: $model.settings.resizeWidth)
                        Text("×").foregroundStyle(.secondary)
                        NumberField(label: L("高", "H"), value: $model.settings.resizeHeight)
                        Text("px").foregroundStyle(.secondary)
                    }
                case .width:
                    HStack { NumberField(label: L("宽度", "Width"), value: $model.settings.resizeWidth); Text("px").foregroundStyle(.secondary) }
                case .height:
                    HStack { NumberField(label: L("高度", "Height"), value: $model.settings.resizeHeight); Text("px").foregroundStyle(.secondary) }
                }
                if model.settings.resizeMode == .exact {
                    Picker(L("比例不符时", "If ratio differs"), selection: $model.settings.exactCrop) {
                        Text(L("居中裁剪", "Crop to Fill")).tag(true)
                        Text(L("拉伸填满", "Stretch")).tag(false)
                    }
                } else if model.settings.resizeMode != .none {
                    Toggle(L("允许放大小图", "Allow upscaling"), isOn: $model.settings.allowUpscale)
                }
            }

            Section(L("输出位置", "Output")) {
                Picker(L("保存到", "Save to"), selection: $model.settings.location) {
                    ForEach(OutputLocation.allCases) { Text($0.label).tag($0) }
                }
                if model.settings.location != .overwrite {
                    TextField(L("文件名后缀", "Filename suffix"), text: $model.settings.suffix, prompt: Text(L("无", "None")))
                }
                if model.settings.location == .customFolder {
                    HStack {
                        Text(model.settings.customFolder.map { ($0 as NSString).abbreviatingWithTildeInPath } ?? L("未选择", "Not selected"))
                            .lineLimit(1).truncationMode(.middle)
                            .foregroundStyle(model.settings.customFolder == nil ? .secondary : .primary)
                        Spacer()
                        Button(L("选择…", "Choose…")) { model.chooseOutputFolder() }
                    }
                }
                if model.settings.location == .overwrite {
                    Label(L("原文件会被移到废纸篓", "Originals will be moved to the Trash"), systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }
            }

            Section(L("高级设置", "Advanced"), isExpanded: $showAdvanced) {
                Toggle(L("移除元数据（EXIF、GPS 定位等）", "Remove metadata (EXIF, GPS location…)"), isOn: $model.settings.stripMetadata)
                Toggle(L("结果更大时保留原图", "Keep original if result is larger"), isOn: $model.settings.keepLargerOriginal)
                Stepper(L("并行任务：", "Parallel jobs: ") + "\(model.settings.concurrency)", value: $model.settings.concurrency,
                        in: 1...max(2, ProcessInfo.processInfo.activeProcessorCount))
                ColorPicker(L("透明区域背景色（JPEG）", "Background for transparency (JPEG)"), selection: backgroundColor, supportsOpacity: false)

                LabeledContent("JPEG") {
                    VStack(alignment: .trailing) {
                        Toggle(L("渐进式加载", "Progressive"), isOn: $model.settings.progressiveJPEG)
                        Toggle(L("色度抽样 4:2:0", "Chroma subsampling 4:2:0"), isOn: $model.settings.chromaSubsampling)
                    }
                }
                LabeledContent("PNG") {
                    VStack(alignment: .trailing) {
                        Toggle(L("有损量化（pngquant）", "Lossy quantization (pngquant)"), isOn: $model.settings.pngLossy)
                        Picker(L("最多颜色", "Max colors"), selection: $model.settings.pngColors) {
                            ForEach([256, 128, 64, 32, 16], id: \.self) { Text("\($0)").tag($0) }
                        }
                        .disabled(!model.settings.pngLossy)
                        Picker(L("无损引擎", "Lossless engine"), selection: $model.settings.pngEngine) {
                            ForEach(PNGEngine.allCases) { Text($0.label).tag($0) }
                        }
                        if model.settings.pngEngine == .oxipng {
                            Stepper(L("优化级别：", "Level: ") + "\(model.settings.oxipngLevel)", value: $model.settings.oxipngLevel, in: 0...6)
                        }
                    }
                }
                LabeledContent("WebP") {
                    Stepper(L("压缩方法：", "Method: ") + "\(model.settings.webpMethod)", value: $model.settings.webpMethod, in: 0...6)
                }
                LabeledContent("GIF") {
                    HStack {
                        Slider(value: gifLossy, in: 0...200, step: 10)
                        Text(L("有损 ", "Lossy ") + "\(model.settings.gifLossy)").monospacedDigit().frame(width: 58, alignment: .trailing)
                    }
                }
                LabeledContent("SVG") {
                    Stepper(L("小数精度：", "Precision: ") + "\(model.settings.svgPrecision)", value: $model.settings.svgPrecision, in: 0...6)
                }
            }

            Section(L("压缩引擎", "Engines"), isExpanded: $showEngines) {
                ForEach(Tool.allCases) { tool in
                    EngineRow(name: tool.rawValue, project: tool.project, available: tool.url != nil)
                }
                EngineRow(name: "svgo", project: "svg/svgo", available: SVGOptimizer.isAvailable)
                EngineRow(name: "ImageIO", project: "macOS ImageIO (AVIF / HEIC / TIFF)", available: true)
            }

            Section {
                // Bilingual label so it can be found whichever language is active.
                Picker("语言 / Language", selection: $model.language) {
                    ForEach(AppLanguage.allCases) { Text($0.label).tag($0) }
                }
            }

            Section {
                Label {
                    Text(L("隐私保护：所有图片处理均在本机完成，图片不会被上传给任何人。", "Privacy: all image processing happens on this Mac. Your images are never uploaded to anyone."))
                } icon: {
                    Image(systemName: "lock.shield.fill").foregroundStyle(.green)
                }
                .font(.caption)
            }
        }
        .formStyle(.grouped)
        .disabled(model.isProcessing)
    }

    private var backgroundColor: Binding<Color> {
        Binding {
            let c = model.settings.backgroundRGB + [1, 1, 1]
            return Color(.sRGB, red: c[0], green: c[1], blue: c[2])
        } set: { color in
            guard let ns = NSColor(color).usingColorSpace(.sRGB) else { return }
            model.settings.backgroundRGB = [Double(ns.redComponent), Double(ns.greenComponent), Double(ns.blueComponent)]
        }
    }

    /// Picking a preset applies it; picking 自定义 keeps the current values.
    private var presetSelection: Binding<Preset?> {
        Binding {
            model.settings.preset
        } set: { preset in
            if let preset { preset.apply(to: &model.settings) } else { model.settings.preset = nil }
        }
    }

    private var gifLossy: Binding<Double> {
        Binding { Double(model.settings.gifLossy) } set: { model.settings.gifLossy = Int($0) }
    }
}

struct QualitySlider: View {
    let title: String
    @Binding var value: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int(value))").monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: $value, in: 1...100, step: 1) {
                EmptyView()
            } minimumValueLabel: {
                Text(L("小", "Small")).font(.caption2)
            } maximumValueLabel: {
                Text(L("清晰", "Sharp")).font(.caption2)
            }
        }
    }
}

struct NumberField: View {
    let label: String
    @Binding var value: Int

    var body: some View {
        LiveNumberField(label: label, value: Binding { Double(value) } set: { value = max(1, Int($0)) })
            .frame(minWidth: 60)
    }
}

/// Number field that applies every keystroke immediately. SwiftUI's `TextField(value:format:)`
/// only commits on Return or focus loss, so clicking "开始压缩" right after typing used the old value.
struct LiveNumberField: View {
    let label: String
    @Binding var value: Double
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField(label, text: $text)
            .multilineTextAlignment(.trailing)
            .focused($focused)
            .onAppear { text = Self.format(value) }
            .onChange(of: text) { _, new in
                if let v = Double(new.replacingOccurrences(of: ",", with: "")), v > 0, v != value { value = v }
            }
            .onChange(of: value) { _, new in
                if Double(text.replacingOccurrences(of: ",", with: "")) != new { text = Self.format(new) }
            }
            .onChange(of: focused) { _, isFocused in
                if !isFocused { text = Self.format(value) }
            }
    }

    private static func format(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(v)
    }
}

struct EngineRow: View {
    let name: String
    let project: String
    let available: Bool

    var body: some View {
        HStack {
            Image(systemName: available ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(available ? .green : .red)
            Text(name).font(.body.monospaced())
            Spacer()
            Text(project).font(.caption).foregroundStyle(.secondary)
        }
    }
}
