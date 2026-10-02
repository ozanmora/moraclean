import Foundation
import Observation

@MainActor
@Observable
final class CleanerModel {
    enum Phase: Equatable {
        case idle, scanning, ready, cleaning
    }

    let categories: [CleanupCategory]
    private(set) var phase: Phase = .idle
    private(set) var results: [CleanupCategory.ID: CategoryScanResult] = [:]
    private(set) var lastReport: CleanupReport?
    var selectedItemIDs: Set<String> = []
    let tree = FileTreeStore()

    init(categories: [CleanupCategory] = CleanupCategory.all()) {
        self.categories = categories
    }

    var isBusy: Bool { phase == .scanning || phase == .cleaning }

    var hasInaccessibleRoots: Bool {
        results.values.contains { !$0.inaccessibleRoots.isEmpty }
    }

    var totalFound: Int64 { results.values.reduce(0) { $0 + $1.totalSize } }

    var selectedItems: [CleanupItem] {
        results.values.flatMap(\.items).filter { selectedItemIDs.contains($0.id) }
    }

    var selectedSize: Int64 { selectedItems.reduce(0) { $0 + $1.size } }

    func items(in category: CleanupCategory.ID) -> [CleanupItem] {
        results[category]?.items ?? []
    }

    func selectedSize(in category: CleanupCategory.ID) -> Int64 {
        items(in: category).filter { selectedItemIDs.contains($0.id) }.reduce(0) { $0 + $1.size }
    }

    /// Kategori seçim durumu: nil = kısmi seçim.
    func selectionState(of category: CleanupCategory.ID) -> Bool? {
        let ids = items(in: category).map(\.id)
        guard !ids.isEmpty else { return false }
        let selected = ids.filter { selectedItemIDs.contains($0) }.count
        if selected == 0 { return false }
        return selected == ids.count ? true : nil
    }

    /// Bir öğe kümesinin seçim durumu: `nil` = kısmi seçim.
    func selectionState(of items: [CleanupItem]) -> Bool? {
        guard !items.isEmpty else { return false }
        let selected = items.filter { selectedItemIDs.contains($0.id) }.count
        if selected == 0 { return false }
        return selected == items.count ? true : nil
    }

    func set(_ items: [CleanupItem], selected: Bool) {
        let ids = items.map(\.id)
        if selected { selectedItemIDs.formUnion(ids) } else { selectedItemIDs.subtract(ids) }
    }

    func setCategory(_ category: CleanupCategory.ID, selected: Bool) {
        let ids = items(in: category).map(\.id)
        if selected { selectedItemIDs.formUnion(ids) } else { selectedItemIDs.subtract(ids) }
    }

    func toggle(_ item: CleanupItem) {
        if selectedItemIDs.contains(item.id) { selectedItemIDs.remove(item.id) } else { selectedItemIDs.insert(item.id) }
    }

    func scan() async {
        guard !isBusy else { return }
        phase = .scanning
        results = [:]
        selectedItemIDs = []
        tree.reset()
        lastReport = nil
        await withTaskGroup(of: CategoryScanResult.self) { group in
            for category in categories {
                group.addTask { await CleanupEngine.scan(category) }
            }
            for await result in group {
                results[result.categoryID] = result
                if categories.first(where: { $0.id == result.categoryID })?.selectedByDefault == true {
                    selectedItemIDs.formUnion(result.items.map(\.id))
                }
            }
        }
        phase = .ready
    }

    func clean(permanentDelete: Bool) async {
        guard !isBusy else { return }
        let items = selectedItems
        guard !items.isEmpty else { return }
        phase = .cleaning
        let permanentRoots = Set(categories.filter(\.alwaysPermanent).flatMap(\.targets).map(\.root.standardizedFileURL.path))
        let allowedRoots = Set(categories.flatMap(\.targets).map(\.root))
        let report = await CleanupEngine.clean(
            items,
            permanently: { item in permanentDelete || permanentRoots.contains(item.root.standardizedFileURL.path) },
            allowedRoots: allowedRoots
        )
        // Temizlik sonrası boyutları yenile; sonuç raporu korunur.
        phase = .idle
        await scan()
        lastReport = report
    }
}
