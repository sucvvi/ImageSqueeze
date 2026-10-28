import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: AppModel?
    private var pending: [URL] = []

    /// Files dropped on the Dock icon or opened with "Open With".
    func application(_ application: NSApplication, open urls: [URL]) {
        MainActor.assumeIsolated {
            if let model { model.add(urls) } else { pending += urls }
        }
    }

    @MainActor
    func attach(_ model: AppModel) {
        self.model = model
        if !pending.isEmpty { model.add(pending); pending.removeAll() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct ImageSqueezeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()

    init() {
        // Headless mode for scripting/testing: ImageSqueeze --cli '<settings json>' file...
        let args = CommandLine.arguments
        if args.count >= 3, args[1] == "--cli" {
            var settings = Settings()
            if let s = Settings.decode(Data(args[2].utf8)) { settings = s }
            var failed = false
            for path in args.dropFirst(3) {
                let url = URL(fileURLWithPath: path)
                do {
                    let r = try Engine(settings: settings).process(url, relativeDir: "")
                    print("OK\t\(url.lastPathComponent)\t\(r.outputURL.lastPathComponent)\t\(r.bytes)\t\(r.width)x\(r.height)\t\(r.note ?? "")")
                } catch {
                    failed = true
                    print("FAIL\t\(url.lastPathComponent)\t\(error.localizedDescription)")
                }
            }
            exit(failed ? 1 : 0)
        }
    }

    var body: some Scene {
        Window("ImageSqueeze", id: "main") {
            ContentView()
                .environment(model)
                // Rebuild the whole window when the interface language changes.
                .id(model.language)
                .frame(minWidth: 900, minHeight: 540)
                .onAppear { delegate.attach(model) }
        }
        .defaultSize(width: 1180, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(L("添加图片…", "Add Images…")) { model.openPanel() }
                    .keyboardShortcut("o")
            }
            CommandGroup(after: .appSettings) {
                Picker("语言 / Language", selection: $model.language) {
                    ForEach(AppLanguage.allCases) { Text($0.label).tag($0) }
                }
            }
        }
    }
}
