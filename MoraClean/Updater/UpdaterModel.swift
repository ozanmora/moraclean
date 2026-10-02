import Foundation
import Observation

enum UpdateSourceKind: String, Sendable {
    case homebrew = "Homebrew"
    case appStore = "App Store"
    case sparkle = "Sparkle"
    case none = "Kaynak yok"
}

struct PendingUpdate: Sendable, Equatable {
    enum Action: Sendable, Equatable {
        case homebrew(token: String)
        case appStore(trackID: Int)
        case sparkle(AppcastItem)
    }

    let latestVersion: String
    let action: Action
}

struct UpdateEntry: Identifiable, Sendable {
    enum State: Sendable, Equatable {
        case checking
        case upToDate
        case available
        case updating(String)
        case updated
        case failed(String)
        /// Kullanıcıya devredilen işlem (App Store sayfası, Yükleyici).
        case handedOff(String)
        case noSource
        case checkFailed(String)
    }

    var id: String { app.id }
    var app: InstalledApp
    var source: UpdateSourceKind = .none
    var pending: PendingUpdate?
    var state: State = .checking
}

@MainActor
@Observable
final class UpdaterModel {
    private(set) var entries: [UpdateEntry] = []
    private(set) var isScanning = false
    private(set) var isUpdating = false
    private(set) var statusText = ""
    private(set) var lastScan: Date?
    var selectedIDs: Set<String> = []
    private(set) var ignoredBundleIDs: Set<String>

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        ignoredBundleIDs = Set(defaults.stringArray(forKey: AppSettingsKey.ignoredBundleIDs) ?? [])
    }

    var isBusy: Bool { isScanning || isUpdating }

    var available: [UpdateEntry] {
        entries.filter { $0.pending != nil && !isIgnored($0) && $0.state != .updated }
    }

    var upToDate: [UpdateEntry] {
        entries.filter { !isIgnored($0) && ($0.state == .upToDate || $0.state == .updated) }
    }

    var unsupported: [UpdateEntry] {
        entries.filter { entry in
            guard !isIgnored(entry) else { return false }
            switch entry.state {
            case .noSource, .checkFailed: return true
            default: return false
            }
        }
    }

    var ignored: [UpdateEntry] { entries.filter(isIgnored) }

    func isIgnored(_ entry: UpdateEntry) -> Bool { ignoredBundleIDs.contains(entry.app.bundleID) }

    func setIgnored(_ entry: UpdateEntry, _ ignore: Bool) {
        if ignore {
            ignoredBundleIDs.insert(entry.app.bundleID)
            selectedIDs.remove(entry.id)
        } else {
            ignoredBundleIDs.remove(entry.app.bundleID)
        }
        defaults.set(Array(ignoredBundleIDs).sorted(), forKey: AppSettingsKey.ignoredBundleIDs)
    }

    // MARK: - Tarama

    func scan(updateHomebrew: Bool) async {
        guard !isBusy else { return }
        isScanning = true
        defer {
            isScanning = false
            statusText = ""
        }

        statusText = "Uygulamalar listeleniyor…"
        let apps = await AppInventory.scan()
        entries = apps.map { UpdateEntry(app: $0) }
        selectedIDs = []

        var caskByPath: [String: HomebrewCask] = [:]
        if Homebrew.isAvailable {
            if updateHomebrew {
                statusText = "Homebrew tanımları güncelleniyor (brew update)…"
                try? await Homebrew.update()
            }
            statusText = "Homebrew cask'ları okunuyor…"
            for cask in (try? await Homebrew.installedCasks()) ?? [] {
                cask.appPaths.forEach { caskByPath[$0] = cask }
            }
        }

        statusText = "App Store kontrol ediliyor…"
        let storeIDs = apps.filter(\.isFromAppStore).map(\.bundleID)
        let listings = storeIDs.isEmpty ? [:] : ((try? await AppStore.lookup(bundleIDs: storeIDs)) ?? [:])

        for index in entries.indices {
            let app = entries[index].app
            if let cask = caskByPath[app.url.standardizedFileURL.path] {
                entries[index].source = .homebrew
                if Homebrew.hasUpdate(cask: cask, app: app) {
                    entries[index].pending = PendingUpdate(latestVersion: cask.latestVersion, action: .homebrew(token: cask.token))
                    entries[index].state = .available
                } else {
                    entries[index].state = .upToDate
                }
            } else if app.isFromAppStore {
                entries[index].source = .appStore
                if let listing = listings[app.bundleID] {
                    if VersionComparator.isNewer(listing.version, than: app.version), AppStore.isCompatible(listing) {
                        entries[index].pending = PendingUpdate(latestVersion: listing.version, action: .appStore(trackID: listing.trackID))
                        entries[index].state = .available
                    } else {
                        entries[index].state = .upToDate
                    }
                } else {
                    entries[index].state = .checkFailed("App Store'da bulunamadı")
                }
            } else if app.sparkleFeedURL != nil {
                entries[index].source = .sparkle
            } else {
                entries[index].state = .noSource
            }
        }

        statusText = "Sparkle güncelleme akışları kontrol ediliyor…"
        await checkSparkleFeeds()

        selectedIDs = Set(available.map(\.id))
        lastScan = Date()
    }

    private func checkSparkleFeeds() async {
        let apps = entries.filter { $0.source == .sparkle }.map(\.app)
        await withTaskGroup(of: (String, Result<AppcastItem?, Error>).self) { group in
            var queue = apps.makeIterator()
            // Aynı anda en fazla 6 istek.
            for _ in 0..<6 {
                guard let app = queue.next() else { break }
                group.addTask { await Self.sparkleResult(for: app) }
            }
            for await (id, result) in group {
                if let index = entries.firstIndex(where: { $0.id == id }) {
                    switch result {
                    case let .success(item?):
                        entries[index].pending = PendingUpdate(latestVersion: item.displayVersion, action: .sparkle(item))
                        entries[index].state = .available
                    case .success(nil):
                        entries[index].state = .upToDate
                    case let .failure(error):
                        entries[index].state = .checkFailed(error.localizedDescription)
                    }
                }
                if let app = queue.next() {
                    group.addTask { await Self.sparkleResult(for: app) }
                }
            }
        }
    }

    private nonisolated static func sparkleResult(for app: InstalledApp) async -> (String, Result<AppcastItem?, Error>) {
        do {
            return (app.id, .success(try await SparkleChecker.check(app)))
        } catch {
            return (app.id, .failure(error))
        }
    }

    // MARK: - Güncelleme

    func updateSelected() async {
        await update(ids: available.map(\.id).filter(selectedIDs.contains))
    }

    func updateAll() async {
        await update(ids: available.map(\.id))
    }

    func update(ids: [String]) async {
        guard !isBusy, !ids.isEmpty else { return }
        isUpdating = true
        defer { isUpdating = false }
        // Homebrew ve mas aynı anda tek işlem yürütebildiği için sırayla güncellenir.
        for id in ids {
            await updateOne(id)
        }
    }

    private func updateOne(_ id: String) async {
        guard let index = entries.firstIndex(where: { $0.id == id }), let pending = entries[index].pending else { return }
        let app = entries[index].app
        setState(id, .updating("Başlıyor…"))
        let progress: @Sendable (String) -> Void = { [weak self] line in
            Task { @MainActor in self?.setProgress(id, line) }
        }
        do {
            switch pending.action {
            case let .homebrew(token):
                try await Homebrew.upgrade(token: token, onLine: progress)
            case let .appStore(trackID):
                let done = await AppStore.update(trackID: trackID, onLine: progress)
                if !done {
                    setState(id, .handedOff("App Store'da açıldı; güncellemeyi oradan tamamlayın."))
                    return
                }
            case let .sparkle(item):
                try await SparkleInstaller.install(app: app, item: item, progress: progress)
            }
            if let index = entries.firstIndex(where: { $0.id == id }) {
                if let refreshed = AppInventory.read(app.url) { entries[index].app = refreshed }
                entries[index].pending = nil
                entries[index].state = .updated
            }
            selectedIDs.remove(id)
        } catch InstallError.handedOffToInstaller {
            setState(id, .handedOff(InstallError.handedOffToInstaller.localizedDescription))
        } catch {
            setState(id, .failed(error.localizedDescription))
        }
    }

    private func setState(_ id: String, _ state: UpdateEntry.State) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].state = state
    }

    private func setProgress(_ id: String, _ line: String) {
        guard let index = entries.firstIndex(where: { $0.id == id }), case .updating = entries[index].state else { return }
        entries[index].state = .updating(line)
    }
}
