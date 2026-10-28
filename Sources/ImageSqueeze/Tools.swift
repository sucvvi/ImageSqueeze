import Foundation

/// External command-line engines. They are bundled inside the app (Contents/Resources/bin);
/// Homebrew locations are only a fallback when running an unbundled debug build.
enum Tool: String, CaseIterable, Identifiable {
    case cjpeg, jpegtran, pngquant, oxipng, pngcrush, cwebp, gifsicle

    var id: String { rawValue }

    var project: String {
        switch self {
        case .cjpeg, .jpegtran: return "mozilla/mozjpeg"
        case .pngquant: return "kornelski/pngquant"
        case .oxipng: return "oxipng/oxipng"
        case .pngcrush: return "glennrp/pngcrush"
        case .cwebp: return "webmproject/libwebp"
        case .gifsicle: return "kohler/gifsicle"
        }
    }

    var url: URL? { Tools.locate(self) }
}

enum Tools {
    private static let searchDirs: [String] = {
        var dirs: [String] = []
        if let res = Bundle.main.resourceURL { dirs.append(res.appendingPathComponent("bin").path) }
        // mozjpeg is keg-only in Homebrew; check it before the generic bin dirs (which may hold libjpeg-turbo's cjpeg).
        dirs += ["/opt/homebrew/opt/mozjpeg/bin", "/usr/local/opt/mozjpeg/bin", "/opt/homebrew/bin", "/usr/local/bin"]
        return dirs
    }()

    static func locate(_ tool: Tool) -> URL? {
        for dir in searchDirs {
            let path = dir + "/" + tool.rawValue
            if FileManager.default.isExecutableFile(atPath: path) { return URL(fileURLWithPath: path) }
        }
        return nil
    }

    /// Runs a tool synchronously and returns its exit code. Throws if the code is not in `okCodes`.
    @discardableResult
    static func run(_ tool: Tool, _ args: [String], okCodes: Set<Int32> = [0]) throws -> Int32 {
        guard let exe = locate(tool) else { throw EngineError.toolMissing(tool.rawValue) }
        let p = Process()
        p.executableURL = exe
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        try p.run()
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let code = p.terminationStatus
        if !okCodes.contains(code) {
            throw EngineError.toolFailed(tool.rawValue, String(decoding: output, as: UTF8.self))
        }
        return code
    }
}
