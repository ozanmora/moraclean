import AppKit
import SwiftUI

struct CleanerView: View {
    @Environment(CleanerModel.self) private var model
    @AppStorage(AppSettingsKey.permanentDelete) private var permanentDelete = false
    @State private var confirmClean = false
    @State private var expansion = ExpansionState()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if model.phase == .idle, model.results.isEmpty {
                emptyState
            } else {
                content
            }
            Divider()
            footer
        }
        .navigationTitle("Cleanup")
        .confirmationDialog(
            "Clean up \(Bytes.format(model.selectedSize))?",
            isPresented: $confirmClean,
            titleVisibility: .visible
        ) {
            Button(permanentDelete ? "Delete Permanently" : "Move to Trash", role: .destructive) {
                Task { await model.clean(permanentDelete: permanentDelete) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(confirmMessage)
        }
    }

    private var confirmMessage: String {
        let count = model.selectedItems.count
        var lines = [permanentDelete
            ? String(localized: "\(count) selected items will be deleted permanently. This cannot be undone.")
            : String(localized: "\(count) selected items will be moved to the Trash. The space is freed when you empty the Trash.")]
        if model.selectedItems.contains(where: { $0.root.lastPathComponent == ".Trash" }) {
            lines.append(String(localized: "Items already in the Trash are always deleted permanently."))
        }
        lines.append(String(localized: "Quitting open apps before cleaning up is recommended."))
        return lines.joined(separator: "\n")
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 64, height: 64)
                .background(LinearGradient(colors: [.pink, .orange], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 16))
            VStack(alignment: .leading, spacing: 4) {
                Text("System Cleanup").font(.title2.bold())
                Text(statusText).foregroundStyle(.secondary)
            }
            Spacer()
            if model.isBusy { ProgressView().controlSize(.small) }
            Button {
                Task { await model.scan() }
            } label: {
                Label(model.results.isEmpty ? "Scan" : "Scan Again", systemImage: "magnifyingglass")
            }
            .controlSize(.large)
            .disabled(model.isBusy)
        }
        .padding(20)
    }

    private var statusText: String {
        switch model.phase {
        case .scanning: return String(localized: "Scanning…")
        case .cleaning: return String(localized: "Cleaning up…")
        case .idle, .ready:
            if let report = model.lastReport {
                var text = String(localized: "Cleaned up \(Bytes.format(report.freedBytes)). Items removed: \(report.removedCount).")
                if !report.failures.isEmpty { text += " " + String(localized: "\(report.failures.count) items could not be deleted.") }
                return text
            }
            return model.results.isEmpty
                ? String(localized: "Scan to find caches, logs and other unneeded files.")
                : String(localized: "Found \(Bytes.format(model.totalFound)) of unneeded files.")
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No scan yet", systemImage: "sparkles")
        } description: {
            Text("Scanning only reads. Nothing is deleted until you confirm.")
        } actions: {
            Button("Start Scan") { Task { await model.scan() } }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var content: some View {
        VStack(spacing: 0) {
            if model.hasInaccessibleRoots {
                FullDiskAccessBanner()
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(.orange.opacity(0.08))
                Divider()
            }
            categoryList
        }
    }

    private var categoryList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if let report = model.lastReport, !report.failures.isEmpty {
                    FailuresSection(failures: report.failures)
                }
                ForEach(model.categories) { category in
                    CategorySection(category: category)
                }
            }
        }
        .environment(expansion)
    }

    private var footer: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Selected: \(Bytes.format(model.selectedSize))").font(.headline)
                Text(permanentDelete ? "Mode: delete permanently" : "Mode: move to Trash")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let available = DiskSpace.available() {
                Text("Available: \(Bytes.format(available))").foregroundStyle(.secondary)
            }
            Button("Clean Up") { confirmClean = true }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(model.isBusy || model.selectedItemIDs.isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

/// Açık akordeon bölümleri ve ağaç düğümleri.
@MainActor
@Observable
final class ExpansionState {
    private(set) var open: Set<String> = []

    func isOpen(_ id: String) -> Bool { open.contains(id) }

    func toggle(_ id: String) {
        if open.contains(id) { open.remove(id) } else { open.insert(id) }
    }
}

private enum TreeMetrics {
    static let indent: CGFloat = 20
    static let chevron: CGFloat = 14
    static let checkbox: CGFloat = 18
    static let icon: CGFloat = 18
    static let rowHeight: CGFloat = 26
    static let maxRows = 300
}

// MARK: - Kategori (akordeon)

private struct CategorySection: View {
    @Environment(CleanerModel.self) private var model
    @Environment(ExpansionState.self) private var expansion
    let category: CleanupCategory

    private var key: String { "category:\(category.id.rawValue)" }

    var body: some View {
        let result = model.results[category.id]
        let items = result?.items ?? []
        let isOpen = expansion.isOpen(key)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                MixedCheckbox(state: model.selectionState(of: items), isEnabled: !items.isEmpty && !model.isBusy) { selected in
                    model.set(items, selected: selected)
                }
                .frame(width: TreeMetrics.checkbox)
                Image(systemName: category.symbol)
                    .font(.title2)
                    .frame(width: 32)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(category.title).font(.headline)
                    Text(category.subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                trailing(result: result, items: items)
                Image(systemName: "chevron.down")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isOpen ? 180 : 0))
                    .frame(width: 20)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) { expansion.toggle(key) }
            }
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                withAnimation(.easeInOut(duration: 0.2)) { expansion.toggle(key) }
            }

            if isOpen {
                VStack(alignment: .leading, spacing: 0) {
                    content(result: result, items: items)
                }
                // Ağaç, kategori ikonunun hizasından başlar.
                .padding(.leading, 20 + TreeMetrics.checkbox + 12 - TreeMetrics.chevron - 6)
                .padding(.trailing, 20 + 20 + 12)
                .padding(.bottom, 10)
            }
            Divider().padding(.leading, 20)
        }
    }

    @ViewBuilder
    private func trailing(result: CategoryScanResult?, items: [CleanupItem]) -> some View {
        if let result, items.isEmpty, !result.inaccessibleRoots.isEmpty {
            Label("Permission required", systemImage: "lock.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
                .help(result.inaccessibleRoots.map(\.path).joined(separator: "\n"))
        } else if let result {
            VStack(alignment: .trailing, spacing: 2) {
                Text(Bytes.format(result.totalSize)).font(.headline.monospacedDigit())
                if model.selectionState(of: items) == nil {
                    Text("\(Bytes.format(model.selectedSize(in: category.id))) selected").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("\(items.count) items").font(.caption).foregroundStyle(.secondary)
                }
            }
        } else if model.phase == .scanning {
            ProgressView().controlSize(.small)
        }
    }

    @ViewBuilder
    private func content(result: CategoryScanResult?, items: [CleanupItem]) -> some View {
        if items.isEmpty {
            Group {
                if let roots = result?.inaccessibleRoots, !roots.isEmpty {
                    Text("Could not read: \(roots.map(\.path).joined(separator: ", ")). Grant Full Disk Access.")
                } else {
                    Text(result != nil ? "Nothing to clean up." : "Scanning…")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.leading, TreeMetrics.chevron + 6)
            .padding(.vertical, 4)
        } else if let groups = result?.groups {
            ForEach(groups.prefix(TreeMetrics.maxRows)) { group in
                GroupTreeRow(group: group)
            }
            MoreRowsNote(hidden: groups.count - TreeMetrics.maxRows, level: 0)
        } else {
            ForEach(items.prefix(TreeMetrics.maxRows)) { item in
                ItemTreeRow(item: item, level: 0)
            }
            MoreRowsNote(hidden: items.count - TreeMetrics.maxRows, level: 0)
        }
    }
}

// MARK: - Ağaç satırları

/// Bir uygulamanın önbellekleri. Eşleşen uygulama yoksa öğe tek başına gösterilir.
private struct GroupTreeRow: View {
    @Environment(CleanerModel.self) private var model
    @Environment(ExpansionState.self) private var expansion
    let group: CleanupGroup

    var body: some View {
        if group.appURL == nil, let item = group.items.first, group.items.count == 1 {
            ItemTreeRow(item: item, level: 0)
        } else {
            let key = "group:\(group.id)"
            let isOpen = expansion.isOpen(key)
            TreeRow(
                level: 0,
                isExpandable: true,
                isOpen: isOpen,
                icon: NSWorkspace.shared.icon(forFile: group.appURL?.path ?? group.items[0].url.path),
                title: group.name,
                detail: String(localized: "\(group.items.count) items"),
                size: group.size,
                revealURL: nil,
                onToggle: { expansion.toggle(key) }
            ) {
                MixedCheckbox(state: model.selectionState(of: group.items), isEnabled: !model.isBusy) { selected in
                    model.set(group.items, selected: selected)
                }
            }
            if isOpen {
                ForEach(group.items) { item in
                    ItemTreeRow(item: item, level: 1)
                }
            }
        }
    }
}

/// Silinebilir bir öğe (kategori kökünün doğrudan alt öğesi). Klasörse içeriğine göz atılabilir.
private struct ItemTreeRow: View {
    @Environment(CleanerModel.self) private var model
    @Environment(ExpansionState.self) private var expansion
    let item: CleanupItem
    let level: Int

    var body: some View {
        let key = "node:\(item.id)"
        let isOpen = expansion.isOpen(key)
        TreeRow(
            level: level,
            isExpandable: item.isDirectory,
            isOpen: isOpen,
            icon: NSWorkspace.shared.icon(forFile: item.url.path),
            title: item.name,
            size: item.size,
            revealURL: item.url,
            onToggle: {
                expansion.toggle(key)
                model.tree.load(item.url)
            }
        ) {
            MixedCheckbox(state: model.selectedItemIDs.contains(item.id), isEnabled: !model.isBusy) { _ in
                model.toggle(item)
            }
        }
        if isOpen {
            NodeChildren(url: item.url, level: level + 1)
        }
    }
}

/// Bir klasörün içeriği (yalnızca görüntüleme).
private struct NodeChildren: View {
    @Environment(CleanerModel.self) private var model
    let url: URL
    let level: Int

    var body: some View {
        if let nodes = model.tree.children[url.path] {
            if nodes.isEmpty {
                TreeNote(text: String(localized: "Empty folder"), level: level)
            }
            ForEach(nodes.prefix(TreeMetrics.maxRows)) { node in
                NodeTreeRow(node: node, level: level)
            }
            MoreRowsNote(hidden: nodes.count - TreeMetrics.maxRows, level: level)
        } else {
            TreeNote(text: String(localized: "Loading…"), level: level)
        }
    }
}

private struct NodeTreeRow: View {
    @Environment(CleanerModel.self) private var model
    @Environment(ExpansionState.self) private var expansion
    let node: FileNode
    let level: Int

    var body: some View {
        let key = "node:\(node.id)"
        let isOpen = expansion.isOpen(key)
        TreeRow(
            level: level,
            isExpandable: node.isDirectory,
            isOpen: isOpen,
            icon: NSWorkspace.shared.icon(forFile: node.url.path),
            title: node.name,
            size: node.size,
            revealURL: node.url,
            onToggle: {
                expansion.toggle(key)
                model.tree.load(node.url)
            }
        ) {
            // İç düğümler tek tek silinmez; seçim üst düzey öğe üzerinden yapılır.
            Color.clear
        }
        if isOpen {
            NodeChildren(url: node.url, level: level + 1)
        }
    }
}

/// Ortak ağaç satırı: girinti, ok, onay kutusu, ikon, ad, boyut, Finder düğmesi tek hizada.
private struct TreeRow<Checkbox: View>: View {
    let level: Int
    let isExpandable: Bool
    let isOpen: Bool
    let icon: NSImage
    let title: String
    var detail: String? = nil
    let size: Int64
    let revealURL: URL?
    let onToggle: () -> Void
    @ViewBuilder let checkbox: Checkbox

    var body: some View {
        HStack(spacing: 6) {
            Color.clear.frame(width: CGFloat(level) * TreeMetrics.indent, height: 1)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(isOpen ? 90 : 0))
                .frame(width: TreeMetrics.chevron)
                .opacity(isExpandable ? 1 : 0)
            checkbox.frame(width: TreeMetrics.checkbox)
            Image(nsImage: icon)
                .resizable()
                .frame(width: TreeMetrics.icon, height: TreeMetrics.icon)
            Text(verbatim: title).lineLimit(1).truncationMode(.middle)
            if let detail {
                Text(verbatim: detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(Bytes.format(size)).monospacedDigit().foregroundStyle(.secondary)
            Group {
                if let revealURL {
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([revealURL])
                    } label: {
                        Image(systemName: "magnifyingglass.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Show in Finder")
                    .accessibilityLabel(Text("Show in Finder"))
                } else {
                    Color.clear
                }
            }
            .frame(width: 18)
        }
        .frame(height: TreeMetrics.rowHeight)
        .contentShape(Rectangle())
        .onTapGesture {
            guard isExpandable else { return }
            withAnimation(.easeInOut(duration: 0.15)) { onToggle() }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(isExpandable ? .isButton : [])
        .accessibilityLabel(Text(verbatim: title))
        .accessibilityAction {
            guard isExpandable else { return }
            withAnimation(.easeInOut(duration: 0.15)) { onToggle() }
        }
    }
}

private struct TreeNote: View {
    let text: String
    let level: Int

    var body: some View {
        Text(verbatim: text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.leading, CGFloat(level) * TreeMetrics.indent + TreeMetrics.chevron + 6 + TreeMetrics.checkbox + 6)
            .frame(height: TreeMetrics.rowHeight)
    }
}

private struct MoreRowsNote: View {
    let hidden: Int
    let level: Int

    var body: some View {
        if hidden > 0 {
            TreeNote(text: String(localized: "and \(hidden) more items (selecting the category includes all of them)"), level: level)
        }
    }
}

private struct FailuresSection: View {
    @Environment(ExpansionState.self) private var expansion
    let failures: [(path: String, reason: String)]

    var body: some View {
        let isOpen = expansion.isOpen("failures")
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label("\(failures.count) items could not be deleted", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isOpen ? 180 : 0))
                    .frame(width: 20)
            }
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { expansion.toggle("failures") } }
            if isOpen {
                ForEach(failures.prefix(50), id: \.path) { failure in
                    VStack(alignment: .leading) {
                        Text(verbatim: failure.path).font(.caption.monospaced()).lineLimit(1).truncationMode(.middle)
                        Text(verbatim: failure.reason).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        Divider().padding(.leading, 20)
    }
}

// MARK: - Kısmi seçimli onay kutusu

/// macOS'un kendi onay kutusu; `nil` durumunda kısmi seçim (–) gösterir.
/// Tıklanınca kısmi ya da boş durum "hepsini seç", dolu durum "hepsini bırak" olur.
private struct MixedCheckbox: NSViewRepresentable {
    let state: Bool?
    let isEnabled: Bool
    let onChange: (Bool) -> Void

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(checkboxWithTitle: "", target: context.coordinator, action: #selector(Coordinator.clicked(_:)))
        button.allowsMixedState = true
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentHuggingPriority(.required, for: .vertical)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.state = state
        context.coordinator.onChange = onChange
        button.state = Self.controlState(state)
        button.isEnabled = isEnabled
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(state: state, onChange: onChange)
    }

    static func controlState(_ state: Bool?) -> NSControl.StateValue {
        switch state {
        case true?: .on
        case false?: .off
        case nil: .mixed
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        var state: Bool?
        var onChange: (Bool) -> Void

        init(state: Bool?, onChange: @escaping (Bool) -> Void) {
            self.state = state
            self.onChange = onChange
        }

        @objc func clicked(_ sender: NSButton) {
            let newValue = state != true
            // NSButton kendi döngüsünde "mixed" durumuna geçmesin; durum modelden gelir.
            sender.state = newValue ? .on : .off
            onChange(newValue)
        }
    }
}

struct FullDiskAccessBanner: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.shield").font(.title2).foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Some folders could not be read").font(.headline)
                Text("For protected locations such as the Trash, allow MoraClean in System Settings > Privacy & Security > Full Disk Access, then restart the app.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
        .padding(.vertical, 6)
    }
}
