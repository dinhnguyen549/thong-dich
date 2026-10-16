import Foundation

/// Finds the AI model files that the user copied onto the iPhone.
///
/// The app never downloads anything. Models arrive in the app's Documents folder through
/// Apple Devices (Windows) / Finder file sharing, or the Files app, or the in-app
/// "Import from Files" button. Expected layout (made by the PC download script):
///
///     Documents/ThongDichModels/
///         speech/parakeet-ultra-coreml/   (Preprocessor/Encoder/Decoder/JointDecisionv3 .mlmodelc + parakeet_vocab.json)
///         speech/silero-vad/silero-vad-unified-256ms-v6.2.1.mlmodelc
///         translator/gemma-4-e2b-it-4bit/
///         translator/translategemma-4b-it-4bit/
///         translator/gemma-4-e4b-it-4bit/          (optional)
///
/// To be forgiving, each component is also found if its folder sits anywhere up to
/// four levels deep inside Documents (e.g. the user dropped only `translator/`).
struct ModelLibrary: Sendable {
    static let rootFolderName = "ThongDichModels"
    static let parakeetFolder = "parakeet-ultra-coreml"
    static let vadModelName = "silero-vad-unified-256ms-v6.2.1.mlmodelc"
    static let parakeetRequired = [
        "Preprocessor.mlmodelc", "Encoder.mlmodelc", "Decoder.mlmodelc",
        "JointDecisionv3.mlmodelc", "parakeet_vocab.json",
    ]
    static let llmRequired = ["config.json", "tokenizer.json"]

    var parakeetDirectory: URL?
    var vadModelURL: URL?
    var translators: [TranslatorModelID: URL] = [:]

    var speechReady: Bool { parakeetDirectory != nil && vadModelURL != nil }

    static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static var modelsRoot: URL { documents.appendingPathComponent(rootFolderName, isDirectory: true) }

    /// Scans the Documents folder (local disk only).
    static func scan() -> ModelLibrary {
        let fm = FileManager.default
        try? fm.createDirectory(at: modelsRoot, withIntermediateDirectories: true)
        excludeFromBackup(modelsRoot)

        var library = ModelLibrary()
        let folders = allDirectories(under: documents, maxDepth: 4)

        if let p = folders.first(where: {
            $0.lastPathComponent == parakeetFolder && containsAll(parakeetRequired, in: $0)
        }) {
            library.parakeetDirectory = p
        }
        if let vad = folders.first(where: { $0.lastPathComponent == vadModelName }) {
            library.vadModelURL = vad
        }
        for model in TranslatorModelID.allCases {
            if let dir = folders.first(where: {
                $0.lastPathComponent == model.folderName && containsAll(llmRequired, in: $0)
                    && hasWeights($0)
            }) {
                library.translators[model] = dir
            }
        }
        // Anything the user placed in Documents should not be uploaded to iCloud backup.
        for url in [library.parakeetDirectory, library.vadModelURL].compactMap({ $0 }) + Array(library.translators.values) {
            excludeFromBackup(url)
        }
        return library
    }

    /// Which translator to use: the user's choice if present, otherwise the best installed one.
    func activeTranslator(preferred: TranslatorModelID?) -> TranslatorModelID? {
        let supported = TranslatorModelID.supportedOnThisDevice
        if let preferred, translators[preferred] != nil, supported.contains(preferred) { return preferred }
        let recommended = TranslatorModelID.recommendedForThisDevice
        if translators[recommended] != nil { return recommended }
        let order: [TranslatorModelID] = [.gemma4E2B, .gemma4E4B, .translateGemma4B]
        return order.first { translators[$0] != nil && supported.contains($0) }
    }

    // MARK: - Import a folder the user picked in the Files app (USB drive, iCloud Drive, …)

    /// Copies a picked folder into Documents/ThongDichModels. Works entirely on local storage.
    static func importFolder(_ source: URL, progress: @escaping @Sendable (Double) -> Void) throws {
        let fm = FileManager.default
        let accessing = source.startAccessingSecurityScopedResource()
        defer { if accessing { source.stopAccessingSecurityScopedResource() } }

        // If the user picked "ThongDichModels" itself, merge its contents; otherwise copy the folder inside.
        let destinationBase: URL
        let itemsToCopy: [URL]
        if source.lastPathComponent == rootFolderName {
            destinationBase = modelsRoot
            itemsToCopy = (try? fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)) ?? []
        } else {
            destinationBase = modelsRoot
            itemsToCopy = [source]
        }
        try fm.createDirectory(at: destinationBase, withIntermediateDirectories: true)

        let total = max(1, itemsToCopy.reduce(0) { $0 + directorySize($1) })
        var done: Int64 = 0
        for item in itemsToCopy where !item.lastPathComponent.hasPrefix(".") {
            let target = destinationBase.appendingPathComponent(item.lastPathComponent)
            try copyMerging(item, to: target) { bytes in
                done += bytes
                progress(min(1, Double(done) / Double(total)))
            }
        }
        excludeFromBackup(modelsRoot)
    }

    private static func copyMerging(_ source: URL, to target: URL, onBytes: (Int64) -> Void) throws {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        fm.fileExists(atPath: source.path, isDirectory: &isDir)
        if isDir.boolValue && source.pathExtension != "mlmodelc" {
            try fm.createDirectory(at: target, withIntermediateDirectories: true)
            for child in try fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)
            where !child.lastPathComponent.hasPrefix(".") {
                try copyMerging(child, to: target.appendingPathComponent(child.lastPathComponent), onBytes: onBytes)
            }
        } else {
            if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
            try fm.copyItem(at: source, to: target)
            onBytes(directorySize(source))
        }
    }

    // MARK: - Model packs (.tdpack) made by the PC script

    /// A model pack is a plain container (a list of files followed by their bytes) so the models
    /// can be copied to the iPhone as a few single files — works with Apple Devices / iTunes
    /// file sharing, a USB drive or the Files app. Unpacking is purely local.
    enum PackError: LocalizedError {
        case invalid(String)
        case notEnoughSpace(needed: Int64)
        var errorDescription: String? {
            switch self {
            case .invalid(let name): return "The model pack \(name) is damaged or incomplete. Copy it again."
            case .notEnoughSpace(let needed):
                return "Not enough free space on the iPhone to install the models (need \(ByteCountFormatter.string(fromByteCount: needed, countStyle: .file)))."
            }
        }
    }

    /// Packs waiting to be installed (in Documents or the Inbox).
    static func pendingPacks() -> [URL] {
        let fm = FileManager.default
        var result: [URL] = []
        for dir in [documents, documents.appendingPathComponent("Inbox"), modelsRoot] {
            if let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                result += items.filter { $0.pathExtension.lowercased() == "tdpack" }
            }
        }
        return result
    }

    /// Unpacks one pack into Documents/ThongDichModels, then deletes the pack to free space.
    static func installPack(_ pack: URL, deleteAfter: Bool = true, progress: (Double) -> Void) throws {
        let fm = FileManager.default
        let accessing = pack.startAccessingSecurityScopedResource()
        defer { if accessing { pack.stopAccessingSecurityScopedResource() } }

        let handle = try FileHandle(forReadingFrom: pack)
        defer { try? handle.close() }

        // 1) Header: "TDPACK1\n" then "relative/path<TAB>size\n" lines, then an empty line.
        var header = Data()
        let separator = Data("\n\n".utf8)
        var headerEnd = 0
        while true {
            guard let chunk = try handle.read(upToCount: 65_536), !chunk.isEmpty else {
                throw PackError.invalid(pack.lastPathComponent)
            }
            header.append(chunk)
            if let r = header.range(of: separator) { headerEnd = r.upperBound; break }
            if header.count > 4_000_000 { throw PackError.invalid(pack.lastPathComponent) }
        }
        let text = String(decoding: header.prefix(headerEnd), as: UTF8.self)
        var lines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        guard lines.first == "TDPACK1" else { throw PackError.invalid(pack.lastPathComponent) }
        lines.removeFirst()

        var entries: [(path: String, size: Int64)] = []
        for line in lines {
            let parts = line.split(separator: "\t")
            guard parts.count == 2, let size = Int64(parts[1]) else { throw PackError.invalid(pack.lastPathComponent) }
            let path = String(parts[0])
            // Never write outside the models folder.
            guard !path.hasPrefix("/"), !path.split(separator: "/").contains("..") else {
                throw PackError.invalid(pack.lastPathComponent)
            }
            entries.append((path, size))
        }
        let total = max(1, entries.reduce(Int64(0)) { $0 + $1.size })

        let free = (try? documents.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
            .volumeAvailableCapacityForImportantUsage ?? Int64.max
        if free < total + 300_000_000 { throw PackError.notEnoughSpace(needed: total + 300_000_000) }

        // 2) Data: the files' bytes, in header order.
        try handle.seek(toOffset: UInt64(headerEnd))
        try fm.createDirectory(at: modelsRoot, withIntermediateDirectories: true)
        var done: Int64 = 0
        let block = 8 * 1_048_576
        for entry in entries {
            let destination = modelsRoot.appendingPathComponent(entry.path)
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
            guard fm.createFile(atPath: destination.path, contents: nil) else {
                throw PackError.invalid(pack.lastPathComponent)
            }
            let out = try FileHandle(forWritingTo: destination)
            var remaining = entry.size
            while remaining > 0 {
                let n = Int(min(Int64(block), remaining))
                guard let data = try handle.read(upToCount: n), data.count == n else {
                    try? out.close()
                    throw PackError.invalid(pack.lastPathComponent)
                }
                try out.write(contentsOf: data)
                remaining -= Int64(n)
                done += Int64(n)
                progress(Double(done) / Double(total))
            }
            try out.close()
        }
        excludeFromBackup(modelsRoot)
        if deleteAfter { try? fm.removeItem(at: pack) }
    }

    // MARK: - Helpers

    static func directorySize(_ url: URL) -> Int64 {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
        if !isDir.boolValue {
            return Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        var total: Int64 = 0
        if let e = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let f as URL in e {
                total += Int64((try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            }
        }
        return total
    }

    private static func allDirectories(under root: URL, maxDepth: Int) -> [URL] {
        var result: [URL] = []
        var frontier: [URL] = [root]
        let fm = FileManager.default
        for _ in 0..<maxDepth {
            var next: [URL] = []
            for dir in frontier {
                guard let children = try? fm.contentsOfDirectory(
                    at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
                else { continue }
                for child in children {
                    let isDir = (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                    guard isDir else { continue }
                    result.append(child)
                    // Don't descend into model bundles or the inbox
                    if child.pathExtension != "mlmodelc" && child.lastPathComponent != "Inbox" {
                        next.append(child)
                    }
                }
            }
            frontier = next
        }
        return result
    }

    private static func containsAll(_ names: [String], in dir: URL) -> Bool {
        names.allSatisfy { FileManager.default.fileExists(atPath: dir.appendingPathComponent($0).path) }
    }

    private static func hasWeights(_ dir: URL) -> Bool {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return files.contains { $0.hasSuffix(".safetensors") }
    }

    static func excludeFromBackup(_ url: URL) {
        var u = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? u.setResourceValues(values)
    }
}
