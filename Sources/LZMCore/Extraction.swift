import Foundation

public enum Extraction {
    /// Probe the actual destination so ACLs and read-only volumes are checked too.
    public static func checkWritableDirectory(_ directory: URL) throws {
        try Task.checkCancellation()
        let probe = directory.appendingPathComponent(".ExtractMDF-" + UUID().uuidString)
        try Data().write(to: probe, options: .withoutOverwriting)
        try FileManager.default.removeItem(at: probe)
    }

    public static func isWriteAccessError(_ error: Error) -> Bool {
        let error = error as NSError
        if error.domain == NSCocoaErrorDomain &&
            [NSFileWriteNoPermissionError, NSFileWriteVolumeReadOnlyError].contains(error.code) { return true }
        if error.domain == NSPOSIXErrorDomain && [1, 13, 30].contains(error.code) { return true }
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            return isWriteAccessError(underlying)
        }
        return false
    }

    public static func safeName(_ name: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:\0").union(.controlCharacters)
        let cleaned = name.components(separatedBy: forbidden).joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty || cleaned == "." || cleaned == ".." ? "untitled" : cleaned
    }

    /// Saves to the exact name; replacement is atomic and does not follow a destination symlink.
    public static func saveExact(_ data: Data, name: String, directory: URL, overwrite: Bool = false) throws -> URL {
        try Task.checkCancellation()
        let target = directory.appendingPathComponent(safeName(name), isDirectory: false)
        try data.write(to: target, options: overwrite ? .atomic : .withoutOverwriting)
        return target
    }

    /// Uses exclusive creation, including when a pre-existing path is a symlink.
    public static func save(_ data: Data, name: String, directory: URL) throws -> URL {
        let safe = safeName(name)
        let base = (safe as NSString).deletingPathExtension
        let ext = (safe as NSString).pathExtension
        for number in 0..<10000 {
            try Task.checkCancellation()
            let suffix = number == 0 ? "" : " (\(number + 1))"
            let filename = number == 0 ? safe : base + suffix + (ext.isEmpty ? "" : "." + ext)
            let target = directory.appendingPathComponent(filename, isDirectory: false)
            do {
                try data.write(to: target, options: .withoutOverwriting)
                return target
            } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileWriteFileExistsError {
                continue
            }
        }
        throw MDFError.invalid(L10n.text("同名ファイルが多すぎるため保存できません。"))
    }
}
