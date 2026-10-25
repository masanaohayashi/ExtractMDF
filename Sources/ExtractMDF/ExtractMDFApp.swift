import SwiftUI
import AppKit
import UniformTypeIdentifiers
import LZMCore

struct ArchiveItem: Identifiable {
    let id = UUID()
    let url: URL
    var archive: MDFArchive?
    var selected: Set<Int> = []
    var status = L10n.text("読み込み中…")
    var error = false
    var outputs: [URL] = []
}

@MainActor
final class AppModel: ObservableObject {
    @Published var items: [ArchiveItem] = []
    @Published var destination: URL?
    @Published var saveBesideSource = false
    @Published var busy = false
    @Published var loading = 0
    @Published var progress = 0.0
    @Published var message = L10n.text("MDFを追加して、保存先を選んでください。")
    private var task: Task<Void, Never>?

    var selectedCount: Int { items.reduce(0) { $0 + $1.selected.count } }

    func chooseFiles() {
        let panel = NSOpenPanel()
        panel.title = L10n.text("LZMで圧縮されたMDFを追加")
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        if panel.runModal() == .OK { add(panel.urls) }
    }

    func chooseDestination() {
        let panel = NSOpenPanel()
        panel.title = L10n.text("解凍したファイルの保存先")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = L10n.text("保存先にする")
        if panel.runModal() == .OK { destination = panel.url }
    }

    func add(_ urls: [URL]) {
        guard !busy else { return }
        for url in urls where url.isFileURL {
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                loading += 1
                Task {
                    let files = await Task.detached(priority: .userInitiated) {
                        let enumerator = FileManager.default.enumerator(at: url,
                            includingPropertiesForKeys: [.isRegularFileKey],
                            options: [.skipsHiddenFiles, .skipsPackageDescendants])
                        return (enumerator?.allObjects as? [URL] ?? []).filter {
                            $0.pathExtension.lowercased() == "mdf" &&
                            (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
                        }.sorted { $0.path < $1.path }
                    }.value
                    loading -= 1
                    if files.isEmpty { message = L10n.text("このフォルダにはMDFファイルが見つかりませんでした。") }
                    add(files)
                }
                continue
            }
            guard !items.contains(where: { $0.url.standardizedFileURL == url.standardizedFileURL }) else { continue }
            let item = ArchiveItem(url: url)
            let id = item.id
            items.append(item)
            loading += 1
            Task {
                let result = await Task.detached(priority: .userInitiated) {
                    Result { try MDFArchive(url: url) }
                }.value
                loading -= 1
                guard let index = items.firstIndex(where: { $0.id == id }) else { return }
                switch result {
                case .success(let archive):
                    items[index].archive = archive
                    items[index].selected = Set(archive.entries.map(\.id))
                    items[index].status = L10n.count("files.ready", archive.entries.count)
                case .failure(let error):
                    items[index].status = error.localizedDescription
                    items[index].error = true
                }
            }
        }
    }

    func extract() {
        guard !busy, loading == 0, selectedCount > 0, saveBesideSource || destination != nil else { return }
        let jobs = items.compactMap { item -> (UUID, MDFArchive, [MDFEntry], URL)? in
            guard let archive = item.archive else { return nil }
            let entries = archive.entries.filter { item.selected.contains($0.id) }
            guard !entries.isEmpty, let directory = saveBesideSource ? item.url.deletingLastPathComponent() : destination else { return nil }
            return (item.id, archive, entries, directory)
        }
        let inputURLs = Set(items.map { $0.url.resolvingSymlinksInPath().standardizedFileURL })
        busy = true
        progress = 0
        let total = selectedCount
        task = Task {
            defer { busy = false; task = nil }
            // Check every destination before creating any extracted files.
            for directory in Set(jobs.map { $0.3 }) {
                do {
                    let worker = Task.detached(priority: .userInitiated) {
                        try Extraction.checkWritableDirectory(directory)
                    }
                    try await withTaskCancellationHandler {
                        try await worker.value
                    } onCancel: { worker.cancel() }
                } catch {
                    if error is CancellationError { message = L10n.count("files.cancelled", 0) }
                    else { showWriteFailure(directory) }
                    return
                }
            }
            var completed = 0
            var failures = 0
            var skipped = 0
            var collisionPolicy: Bool?
            for (id, archive, entries, destination) in jobs {
                guard !Task.isCancelled else { break }
                if let index = items.firstIndex(where: { $0.id == id }) {
                    items[index].outputs = []
                    items[index].error = false
                    items[index].status = L10n.text("解凍中…")
                }
                for entry in entries {
                    guard !Task.isCancelled else { break }
                    message = L10n.format("解凍中: %@", entry.name)
                    let result: Result<URL?, Error>
                    do {
                        let target = destination.appendingPathComponent(Extraction.safeName(entry.name))
                        var overwrite = false
                        while true {
                            try Task.checkCancellation()
                            if FileManager.default.fileExists(atPath: target.path) ||
                                (try? FileManager.default.destinationOfSymbolicLink(atPath: target.path)) != nil {
                                let choice: Bool
                                if let collisionPolicy { choice = collisionPolicy }
                                else {
                                    let alert = NSAlert()
                                    alert.messageText = L10n.text("同名のファイルがあります")
                                    alert.informativeText = target.path
                                    alert.addButton(withTitle: L10n.text("上書き"))
                                    alert.addButton(withTitle: L10n.text("スキップ"))
                                    alert.addButton(withTitle: L10n.text("キャンセル"))
                                    alert.showsSuppressionButton = true
                                    alert.suppressionButton?.title = L10n.text("すべてに適用")
                                    let response = alert.runModal()
                                    guard response != .alertThirdButtonReturn else {
                                        task?.cancel()
                                        throw CancellationError()
                                    }
                                    choice = response == .alertFirstButtonReturn
                                    if alert.suppressionButton?.state == .on { collisionPolicy = choice }
                                }
                                if !choice { result = .success(nil); break }
                                overwrite = true
                            }
                            // Never replace an input archive, even when its name matches an entry.
                            guard !inputURLs.contains(target.resolvingSymlinksInPath().standardizedFileURL) else {
                                throw MDFError.invalid(L10n.text("入力MDFには上書きできません。"))
                            }
                            let replace = overwrite
                            let worker = Task.detached(priority: .userInitiated) {
                                try Task.checkCancellation()
                                let data = try archive.extract(entry)
                                try Task.checkCancellation()
                                return try Extraction.saveExact(data, name: entry.name, directory: destination, overwrite: replace)
                            }
                            let attempt = await withTaskCancellationHandler {
                                await worker.result
                            } onCancel: { worker.cancel() }
                            if case .failure(let error as NSError) = attempt,
                               error.domain == NSCocoaErrorDomain && error.code == NSFileWriteFileExistsError {
                                continue
                            }
                            result = attempt.map { Optional($0) }
                            break
                        }
                    } catch { result = .failure(error) }
                    guard let index = items.firstIndex(where: { $0.id == id }) else { continue }
                    switch result {
                    case .success(let url):
                        items[index].selected.remove(entry.id)
                        if let url {
                            items[index].outputs.append(url)
                            completed += 1
                        } else { skipped += 1 }
                    case .failure(let error):
                        if error is CancellationError { break }
                        if Extraction.isWriteAccessError(error) || !FileManager.default.isWritableFile(atPath: destination.path) {
                            items[index].error = true
                            items[index].status = error.localizedDescription
                            showWriteFailure(destination)
                            return
                        }
                        failures += 1
                        items[index].error = true
                        items[index].status = "\(entry.name): \(error.localizedDescription)"
                    }
                    progress = Double(completed + failures + skipped) / Double(total)
                }
                if let index = items.firstIndex(where: { $0.id == id }), !items[index].error {
                    items[index].status = L10n.count("files.saved", items[index].outputs.count)
                }
            }
            message = Task.isCancelled ? L10n.count("files.cancelled", completed) :
                L10n.count("files.completed", completed) + (failures == 0 ? "" : " " + L10n.count("files.failed", failures))
            if skipped > 0 { message += " " + L10n.format("%dファイルをスキップしました。", skipped) }
        }
    }

    private func showWriteFailure(_ directory: URL) {
        message = L10n.text("保存先に書き込めないため、処理を終了しました。")
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.text("保存先に書き込めません")
        alert.informativeText = directory.path
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    func cancel() { task?.cancel() }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let model = AppModel()
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func application(_ application: NSApplication, open urls: [URL]) { Self.model.add(urls) }
}

@main
struct ExtractMDFApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = AppDelegate.model
    var body: some Scene {
        Window("ExtractMDF", id: "main") {
            ContentView(model: model)
                .frame(minWidth: 700, minHeight: 540)
                .onOpenURL { model.add([$0]) }
        }
        .defaultSize(width: 860, height: 660)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(L10n.text("MDFを追加…"), action: model.chooseFiles).keyboardShortcut("o").disabled(model.busy)
            }
        }
    }
}

struct ContentView: View {
    @ObservedObject var model: AppModel
    @State private var targeted = false

    var body: some View {
        VStack(spacing: 0) {
            if model.items.isEmpty {
                VStack(spacing: 18) {
                    Image(systemName: "square.and.arrow.down").font(.system(size: 44, weight: .light)).foregroundStyle(.secondary)
                    Text(L10n.text("MDFファイルをここにドロップ")).font(.title3.weight(.semibold))
                    Text(L10n.text("LZMでまとめた曲・音色・歌詞を取り出します。\n複数のMDFやフォルダをまとめて追加できます。"))
                        .multilineTextAlignment(.center).foregroundStyle(.secondary).lineSpacing(5)
                    Button(L10n.text("ファイルを選択…"), action: model.chooseFiles).controlSize(.large)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack {
                    Text(L10n.text("追加したMDF")).font(.headline)
                    Text(L10n.count("archives.count", model.items.count)).foregroundStyle(.secondary)
                    Spacer()
                    Button(L10n.text("追加…"), action: model.chooseFiles)
                    Button(L10n.text("一覧をクリア")) { model.items.removeAll() }
                }.padding(.horizontal, 24).padding(.vertical, 14).disabled(model.busy || model.loading > 0)
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach($model.items) { $item in
                            archiveCard($item)
                        }
                    }.padding(.horizontal, 24).padding(.bottom, 20)
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 14) {
                Toggle(L10n.text("元のMDFと同じフォルダに保存"), isOn: $model.saveBesideSource)
                    .toggleStyle(.checkbox)
                    .disabled(model.busy)
                if !model.saveBesideSource {
                    HStack {
                        Image(systemName: "folder").foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(L10n.text("保存先")).font(.caption).foregroundStyle(.secondary)
                            Text(model.destination?.path ?? L10n.text("フォルダを選択してください"))
                                .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                        }
                        Spacer()
                        Button(L10n.text("選択…"), action: model.chooseDestination).disabled(model.busy)
                        if let destination = model.destination {
                            Button { NSWorkspace.shared.open(destination) } label: { Image(systemName: "arrow.up.forward.square") }
                                .help(L10n.text("保存先をFinderで開く"))
                        }
                    }
                }
                Text(L10n.text("元のMDFはそのまま残ります。同名ファイルがある場合は確認します。"))
                    .font(.caption).foregroundStyle(.secondary)
                if model.busy { ProgressView(value: model.progress) }
                HStack {
                    Text(model.loading > 0 ? L10n.text("MDFを読み込み中…") : model.message)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    Spacer()
                    if model.busy { Button(L10n.text("中止"), action: model.cancel) }
                    Button(L10n.count("files.extract", model.selectedCount), action: model.extract)
                        .buttonStyle(.borderedProminent).controlSize(.large)
                        .disabled(model.busy || model.loading > 0 || model.selectedCount == 0 || (!model.saveBesideSource && model.destination == nil))
                }
            }.padding(24)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay { if targeted { RoundedRectangle(cornerRadius: 12).stroke(Color.accentColor, lineWidth: 3).padding(6).allowsHitTesting(false) } }
        .onDrop(of: [UTType.fileURL], isTargeted: $targeted) { providers in
            guard !model.busy else { return false }
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in model.add([url]) }
                }
            }
            return true
        }
    }

    private func archiveCard(_ item: Binding<ArchiveItem>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Image(systemName: item.wrappedValue.error ? "exclamationmark.triangle" : "doc.zipper")
                    .font(.title2).foregroundStyle(item.wrappedValue.error ? Color.orange : Color.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.wrappedValue.url.lastPathComponent).font(.headline)
                    if let title = item.wrappedValue.archive?.title, !title.isEmpty {
                        Text(title).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Text(item.wrappedValue.status).font(.caption)
                        .foregroundStyle(item.wrappedValue.error ? Color.orange : Color.secondary).textSelection(.enabled)
                }
                Spacer()
                if !item.wrappedValue.outputs.isEmpty {
                    Button { NSWorkspace.shared.activateFileViewerSelecting(item.wrappedValue.outputs) } label: {
                        Image(systemName: "folder")
                    }.help(L10n.text("保存したファイルをFinderに表示"))
                }
            }
            if let archive = item.wrappedValue.archive {
                Divider()
                ForEach(archive.entries) { entry in
                    Toggle(isOn: Binding(get: { item.wrappedValue.selected.contains(entry.id) }, set: { selected in
                        if selected { item.wrappedValue.selected.insert(entry.id) }
                        else { item.wrappedValue.selected.remove(entry.id) }
                    })) {
                        HStack {
                            Text(entry.name).font(.system(.body, design: .monospaced)).lineLimit(1)
                            Text(entry.typeName).font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Text("\(size(entry.compressedSize)) → \(size(entry.expandedSize))")
                                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        }
                    }.toggleStyle(.checkbox).disabled(model.busy)
                }
            }
        }.padding(16).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
    }

    private func size(_ count: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
    }
}
