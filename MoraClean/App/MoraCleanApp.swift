import SwiftUI

@main
struct MoraCleanApp: App {
    @State private var cleaner = CleanerModel()
    @State private var updater = UpdaterModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(cleaner)
                .environment(updater)
                .frame(minWidth: 860, minHeight: 560)
        }
        .windowResizability(.contentMinSize)
        .commands { SupportCommands() }

        Settings {
            SettingsView()
        }
    }
}

enum SidebarItem: String, CaseIterable, Identifiable {
    case cleaner, updater

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cleaner: String(localized: "Cleanup")
        case .updater: String(localized: "Updates")
        }
    }

    var symbol: String {
        switch self {
        case .cleaner: "sparkles"
        case .updater: "arrow.triangle.2.circlepath"
        }
    }
}

struct ContentView: View {
    @Environment(UpdaterModel.self) private var updater
    @State private var selection: SidebarItem? = .cleaner

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $selection) { item in
                Label(item.title, systemImage: item.symbol)
                    .badge(item == .updater ? updater.available.count : 0)
                    .tag(item)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
            .safeAreaInset(edge: .bottom) { DiskUsageView().padding(12) }
        } detail: {
            switch selection ?? .cleaner {
            case .cleaner: CleanerView()
            case .updater: UpdaterView()
            }
        }
    }
}

private struct DiskUsageView: View {
    var body: some View {
        if let total = DiskSpace.total(), let free = DiskSpace.available(), total > 0 {
            VStack(alignment: .leading, spacing: 6) {
                Text("Startup Disk").font(.caption.weight(.semibold))
                ProgressView(value: Double(total - free), total: Double(total))
                Text("\(Bytes.format(free)) free of \(Bytes.format(total))").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}
