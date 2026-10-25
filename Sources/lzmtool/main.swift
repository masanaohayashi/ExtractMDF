import Foundation
import LZMCore

let args = Array(CommandLine.arguments.dropFirst())
do {
    guard args.count == 1 || args.count == 2 else {
        throw MDFError.invalid(L10n.text("使い方: lzmtool input.mdf [出力フォルダ]\n出力フォルダを省略すると中身を一覧表示します。"))
    }
    let archive = try MDFArchive(url: URL(fileURLWithPath: args[0]))
    print(archive.title)
    for entry in archive.entries { print("\(entry.name)\t\(entry.typeName)\t\(entry.compressedSize) → \(entry.expandedSize) bytes") }
    if args.count == 2 {
        let directory = URL(fileURLWithPath: args[1], isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for entry in archive.entries {
            let url = try Extraction.save(archive.extract(entry), name: entry.name, directory: directory)
            print(L10n.format("保存: %@", url.path))
        }
    }
} catch {
    FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
    exit(1)
}
