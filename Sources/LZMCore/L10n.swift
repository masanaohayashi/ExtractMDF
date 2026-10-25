import Foundation

public enum L10n {
    static let bundle: Bundle = {
        if let url = Bundle.main.resourceURL?.appendingPathComponent("ExtractMDF_LZMCore.bundle"),
           let bundle = Bundle(url: url) { return bundle }
        return .module
    }()

    public static func text(_ key: String) -> String {
        bundle.localizedString(forKey: key, value: nil, table: nil)
    }

    public static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: Locale.current, arguments: arguments)
    }

    public static func count(_ key: String, _ count: Int) -> String {
        String.localizedStringWithFormat(text(key), count)
    }
}
