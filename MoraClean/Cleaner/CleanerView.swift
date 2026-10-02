import AppKit
import SwiftUI

struct CleanerView: View {
    @Environment(CleanerModel.self) private var model
    @AppStorage(AppSettingsKey.permanentDelete) private var permanentDelete = false
    @State private var confirmClean = false
    @State private var expanded: Set<CleanupCategory.ID> = []

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
        List {
            if let report = model.lastReport, !report.failures.isEmpty {
                DisclosureGroup("\(report.failures.count) items could not be deleted") {
                    ForEach(report.failures.prefix(50), id: \.path) { failure in
                        VStack(alignment: .leading) {
                            Text(failure.path).font(.caption.monospaced()).lineLimit(1).truncationMode(.middle)
                            Text(failure.reason).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                .foregroundStyle(.orange)
            }
            ForEach(model.categories) { category in
                CategoryRow(category: category, isExpanded: binding(for: category.id))
            }
        }
        .listStyle(.inset)
    }

    private func binding(for id: CleanupCategory.ID) -> Binding<Bool> {
        Binding(
            get: { expanded.contains(id) },
            set: { if $0 { expanded.insert(id) } else { expanded.remove(id) } }
        )
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

private struct CategoryRow: View {
    @Environment(CleanerModel.self) private var model
    let category: CleanupCategory
    @Binding var isExpanded: Bool

    var body: some View {
        let items = model.items(in: category.id)
        let scanned = model.results[category.id] != nil
        DisclosureGroup(isExpanded: $isExpanded) {
            if items.isEmpty {
                if let roots = model.results[category.id]?.inaccessibleRoots, !roots.isEmpty {
                    Text("Could not read: \(roots.map(\.path).joined(separator: ", ")). Grant Full Disk Access.").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(scanned ? "Nothing to clean up." : "Scanning…").foregroundStyle(.secondary)
                }
            } else {
                ForEach(items.prefix(300)) { item in
                    ItemRow(item: item)
                }
                if items.count > 300 {
                    Text("and \(items.count - 300) more items (selecting the category includes all of them)").font(.caption).foregroundStyle(.secondary)
                }
            }
        } label: {
            HStack(spacing: 12) {
                Toggle("", isOn: Binding(
                    get: { model.selectionState(of: category.id) != false },
                    set: { model.setCategory(category.id, selected: $0) }
                ))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .disabled(items.isEmpty || model.isBusy)
                Image(systemName: category.symbol)
                    .font(.title2)
                    .frame(width: 32)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(category.title).font(.headline)
                    Text(category.subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if let result = model.results[category.id], items.isEmpty, !result.inaccessibleRoots.isEmpty {
                    Label("Permission required", systemImage: "lock.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                        .help(result.inaccessibleRoots.map(\.path).joined(separator: "\n"))
                } else if scanned {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(Bytes.format(model.results[category.id]?.totalSize ?? 0)).font(.headline.monospacedDigit())
                        if model.selectionState(of: category.id) == nil {
                            Text("\(Bytes.format(model.selectedSize(in: category.id))) selected").font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text("\(items.count) items").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } else if model.phase == .scanning {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(.vertical, 6)
        }
    }
}

private struct ItemRow: View {
    @Environment(CleanerModel.self) private var model
    let item: CleanupItem

    var body: some View {
        HStack {
            Toggle("", isOn: Binding(
                get: { model.selectedItemIDs.contains(item.id) },
                set: { _ in model.toggle(item) }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()
            .disabled(model.isBusy)
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable()
                .frame(width: 18, height: 18)
            Text(item.name).lineLimit(1).truncationMode(.middle)
            Spacer()
            Text(Bytes.format(item.size)).monospacedDigit().foregroundStyle(.secondary)
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            } label: {
                Image(systemName: "magnifyingglass.circle")
            }
            .buttonStyle(.borderless)
            .help("Show in Finder")
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
