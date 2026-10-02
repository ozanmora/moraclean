import AppKit
import SwiftUI

struct UpdaterView: View {
    @Environment(UpdaterModel.self) private var model
    @AppStorage(AppSettingsKey.brewUpdateBeforeScan) private var brewUpdateBeforeScan = true
    @State private var showUpToDate = false
    @State private var showUnsupported = false
    @State private var showIgnored = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if model.entries.isEmpty {
                emptyState
            } else {
                list
            }
            Divider()
            footer
        }
        .navigationTitle("Updates")
    }

    private var header: some View {
        HStack(spacing: 16) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 64, height: 64)
                .background(LinearGradient(colors: [.teal, .blue], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 16))
            VStack(alignment: .leading, spacing: 4) {
                Text("App Updater").font(.title2.bold())
                Text(subtitle).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            if model.isScanning { ProgressView().controlSize(.small) }
            Button {
                Task { await model.scan(updateHomebrew: brewUpdateBeforeScan) }
            } label: {
                Label(model.entries.isEmpty ? "Scan" : "Scan Again", systemImage: "magnifyingglass")
            }
            .controlSize(.large)
            .disabled(model.isBusy)
        }
        .padding(20)
    }

    private var subtitle: String {
        if model.isScanning { return model.statusText }
        if model.isUpdating { return String(localized: "Updating…") }
        if model.entries.isEmpty { return String(localized: "Finds updates from Homebrew, the Mac App Store and Sparkle feeds.") }
        let count = model.available.count
        var text = count == 0 ? String(localized: "All apps are up to date.") : String(localized: "Updates are available for \(count) apps.")
        if let date = model.lastScan {
            text += " " + String(localized: "Last scan: \(date.formatted(date: .omitted, time: .shortened))")
        }
        return text
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Check for updates", systemImage: "arrow.down.app")
        } description: {
            Text("Scans /Applications and ~/Applications and finds each app's update source automatically.")
        } actions: {
            Button("Start Scan") { Task { await model.scan(updateHomebrew: brewUpdateBeforeScan) } }
                .buttonStyle(.borderedProminent)
                .disabled(model.isBusy)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        List {
            if !Homebrew.isAvailable {
                Label("Homebrew was not found; apps installed as casks are checked through Sparkle or the App Store.", systemImage: "info.circle")
                    .foregroundStyle(.secondary)
            }
            Section("Updates Available (\(model.available.count))") {
                if model.available.isEmpty {
                    Text(model.isScanning ? "Checking…" : "No pending updates.").foregroundStyle(.secondary)
                }
                ForEach(model.available) { entry in
                    UpdateRow(entry: entry, selectable: true)
                }
            }
            Section("Up to Date (\(model.upToDate.count))", isExpanded: $showUpToDate) {
                ForEach(model.upToDate) { UpdateRow(entry: $0, selectable: false) }
            }
            Section("Could Not Check (\(model.unsupported.count))", isExpanded: $showUnsupported) {
                ForEach(model.unsupported) { UpdateRow(entry: $0, selectable: false) }
            }
            if !model.ignored.isEmpty {
                Section("Ignored (\(model.ignored.count))", isExpanded: $showIgnored) {
                    ForEach(model.ignored) { UpdateRow(entry: $0, selectable: false) }
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
    }

    private var footer: some View {
        let selectedCount = model.available.filter { model.selectedIDs.contains($0.id) }.count
        return HStack {
            Text("\(selectedCount) of \(model.available.count) selected").foregroundStyle(.secondary)
            Spacer()
            Button("Update Selected") { Task { await model.updateSelected() } }
                .disabled(model.isBusy || selectedCount == 0)
            Button("Update All") { Task { await model.updateAll() } }
                .buttonStyle(.borderedProminent)
                .disabled(model.isBusy || model.available.isEmpty)
        }
        .controlSize(.large)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

private struct UpdateRow: View {
    @Environment(UpdaterModel.self) private var model
    let entry: UpdateEntry
    let selectable: Bool

    var body: some View {
        HStack(spacing: 12) {
            if selectable {
                Toggle("", isOn: Binding(
                    get: { model.selectedIDs.contains(entry.id) },
                    set: { isOn in
                        if isOn { model.selectedIDs.insert(entry.id) } else { model.selectedIDs.remove(entry.id) }
                    }
                ))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .disabled(model.isBusy)
            }
            Image(nsImage: NSWorkspace.shared.icon(forFile: entry.app.url.path))
                .resizable()
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.app.name).font(.headline)
                    SourceBadge(kind: entry.source)
                }
                versionLine
            }
            Spacer()
            stateView
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([entry.app.url]) }
            if model.isIgnored(entry) {
                Button("Stop Ignoring") { model.setIgnored(entry, false) }
            } else {
                Button("Ignore This App") { model.setIgnored(entry, true) }
            }
        }
    }

    @ViewBuilder
    private var versionLine: some View {
        if let pending = entry.pending, entry.state != .updated {
            Text("\(entry.app.displayVersion)  →  \(pending.latestVersion)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        } else {
            Text(entry.app.displayVersion.isEmpty ? entry.app.bundleID : entry.app.displayVersion)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var stateView: some View {
        switch entry.state {
        case .checking:
            ProgressView().controlSize(.small)
        case .available:
            Button("Update") { Task { await model.update(ids: [entry.id]) } }
                .disabled(model.isBusy)
        case let .updating(line):
            HStack(spacing: 8) {
                Text(line).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail).frame(maxWidth: 260, alignment: .trailing)
                ProgressView().controlSize(.small)
            }
        case .upToDate:
            Label("Up to date", systemImage: "checkmark.circle.fill").foregroundStyle(.green).labelStyle(.iconOnly).help("Up to date")
        case .updated:
            Label("Updated", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
        case let .failed(reason):
            HStack(spacing: 8) {
                Label("Failed", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).help(reason)
                Button("Retry") { Task { await model.update(ids: [entry.id]) } }.disabled(model.isBusy)
            }
            .frame(maxWidth: 260, alignment: .trailing)
        case let .handedOff(message):
            Label(message, systemImage: "arrow.up.forward.app").font(.caption).foregroundStyle(.blue).lineLimit(2).frame(maxWidth: 260, alignment: .trailing)
        case .noSource:
            Text("No update source").font(.caption).foregroundStyle(.secondary)
        case let .checkFailed(reason):
            Text(reason).font(.caption).foregroundStyle(.secondary).lineLimit(1).help(reason).frame(maxWidth: 260, alignment: .trailing)
        }
    }
}

private struct SourceBadge: View {
    let kind: UpdateSourceKind

    var body: some View {
        if kind != .none {
            Text(kind.rawValue)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(color.opacity(0.15), in: Capsule())
                .foregroundStyle(color)
        }
    }

    private var color: Color {
        switch kind {
        case .homebrew: .orange
        case .appStore: .blue
        case .sparkle: .purple
        case .none: .secondary
        }
    }
}
