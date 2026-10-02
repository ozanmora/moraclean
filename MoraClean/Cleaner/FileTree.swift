import Foundation
import Observation

/// Ağaçta gezinmek için bir dosya ya da klasör. Yalnızca görüntülenir; silme seçimi üst düzey öğelerdedir.
struct FileNode: Identifiable, Sendable, Hashable {
    var id: String { url.path }
    let url: URL
    let size: Int64
    let isDirectory: Bool

    var name: String { url.lastPathComponent }
}

enum FileTree {
    /// Klasörün doğrudan içeriği, boyuta göre büyükten küçüğe. Sembolik bağlantılar izlenmez.
    static func children(of url: URL) async -> [FileNode] {
        await Task.detached(priority: .userInitiated) {
            let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
            guard let urls = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: []) else {
                return []
            }
            return urls.compactMap { child -> FileNode? in
                if child.lastPathComponent == ".DS_Store" { return nil }
                let values = try? child.resourceValues(forKeys: Set(keys))
                let isDirectory = values?.isDirectory == true && values?.isSymbolicLink != true
                return FileNode(url: child, size: CleanupEngine.allocatedSize(of: child), isDirectory: isDirectory)
            }
            .sorted { $0.size == $1.size ? $0.name < $1.name : $0.size > $1.size }
        }.value
    }
}

/// Açılan klasörlerin içeriğini isteğe bağlı yükler ve önbellekte tutar.
@MainActor
@Observable
final class FileTreeStore {
    private(set) var children: [String: [FileNode]] = [:]
    private(set) var loading: Set<String> = []

    func load(_ url: URL) {
        let key = url.path
        guard children[key] == nil, !loading.contains(key) else { return }
        loading.insert(key)
        Task {
            let nodes = await FileTree.children(of: url)
            children[key] = nodes
            loading.remove(key)
        }
    }

    func reset() {
        children = [:]
        loading = []
    }
}
