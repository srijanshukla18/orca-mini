import SwiftData
import SwiftUI

// MARK: - Tab Manager

private struct ClosedTabSnapshot {
    let id: UUID
    let url: URL
    let savedURL: URL?
    let title: String
    let favicon: URL?
    let faviconLocalFile: URL?
    let createdAt: Date
    let lastAccessedAt: Date?
    let type: TabType
    let order: Int
    let isPrivate: Bool

    init(tab: Tab) {
        id = tab.id
        url = tab.url
        savedURL = tab.savedURL
        title = tab.title
        favicon = tab.favicon
        faviconLocalFile = tab.faviconLocalFile
        createdAt = tab.createdAt
        lastAccessedAt = tab.lastAccessedAt
        type = tab.type
        order = tab.order
        isPrivate = tab.isPrivate
    }
}

@MainActor
// swiftlint:disable:next type_body_length
class TabManager: ObservableObject {
    @Published var activeContainer: TabContainer?
    @Published var activeTab: Tab?
    let modelContainer: ModelContainer
    let modelContext: ModelContext

    var recentTabs: [Tab] {
        guard let container = activeContainer else { return [] }
        return Array(container.tabs
            .sorted { ($0.lastAccessedAt ?? Date.distantPast) > ($1.lastAccessedAt ?? Date.distantPast) }
            .prefix(SettingsStore.shared.maxRecentTabs)
        )
    }

    /// Note: Could be made injectable via init parameter if preferred
    let tabSearchingService: TabSearchingProviding

    private var cleanupTimer: Timer?
    private var recentlyClosedTabs: [ClosedTabSnapshot] = []
    private let maxRecentlyClosedTabs = 5

    init(
        modelContainer: ModelContainer,
        modelContext: ModelContext,
        tabSearchingService: TabSearchingProviding = TabSearchingService()
    ) {
        self.modelContainer = modelContainer
        self.modelContext = modelContext
        self.tabSearchingService = tabSearchingService

        self.modelContext.undoManager = UndoManager()
        initializeActiveContainerAndTab()

        // Start automatic cleanup timer (every minute)
        startCleanupTimer()
    }

    // MARK: - Public API's

    func search(_ text: String) -> [Tab] {
        tabSearchingService.search(
            text,
            activeContainer: activeContainer,
            modelContext: modelContext
        )
    }

    func openFromEngine(
        engineName: SearchEngineID,
        query: String,
        historyManager: HistoryManager,
        isPrivate: Bool
    ) {
        if let url = SearchEngineService().getSearchURLForEngine(
            engineName: engineName,
            query: query
        ) {
            openTab(url: url, historyManager: historyManager, isPrivate: isPrivate)
        }
    }

    func isActive(_ tab: Tab) -> Bool {
        if let activeTab = self.activeTab {
            return activeTab.id == tab.id
        }
        return false
    }

    func togglePinTab(_ tab: Tab) {
        if tab.type == .pinned {
            tab.type = .normal
            tab.savedURL = nil
        } else {
            tab.type = .pinned
            tab.savedURL = tab.url
        }

        try? modelContext.save()
    }

    private func initializeActiveContainerAndTab() {
        let profiles = fetchProfiles()
        migrateLegacyFavoriteTabs(in: profiles)

        if let profile = profiles.first {
            activeContainer = profile
            if let lastAccessedTab = profile.tabs
                .sorted(by: { ($0.lastAccessedAt ?? Date.distantPast) > ($1.lastAccessedAt ?? Date.distantPast) })
                .first
            {
                activeTab = lastAccessedTab
                activeTab?.maybeIsActive = true
            }
        } else {
            activeContainer = createProfile()
        }
    }

    private func migrateLegacyFavoriteTabs(in profiles: [TabContainer]) {
        var changed = false
        for tab in profiles.flatMap(\.tabs) where tab.type == .fav {
            tab.type = .pinned
            tab.savedURL = tab.savedURL ?? tab.url
            changed = true
        }

        if changed {
            try? modelContext.save()
        }
    }

    @discardableResult
    private func createProfile() -> TabContainer {
        let profile = TabContainer(name: "Profile", emoji: "")
        modelContext.insert(profile)
        try? modelContext.save()
        return profile
    }

    // MARK: - Tab Public API's

    func addTab(
        title: String = "Untitled",
        // Will Always Work
        url: URL = URL(string: "about:blank")!,
        container: TabContainer,
        favicon: URL? = nil,
        historyManager: HistoryManager? = nil,
        downloadManager: DownloadManager? = nil,
        isPrivate: Bool
    ) -> Tab {
        let cleanHost: String? = {
            guard let host = url.host else { return nil }
            return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        }()
        let newTab = Tab(
            url: url,
            title: cleanHost ?? "New Tab",
            favicon: favicon,
            container: container,
            type: .normal,
            order: container.tabs.count + 1,
            historyManager: historyManager,
            downloadManager: downloadManager,
            tabManager: self,
            isPrivate: isPrivate
        )
        modelContext.insert(newTab)
        container.tabs.append(newTab)
        activeTab?.maybeIsActive  = false
        activeTab = newTab
        activeTab?.maybeIsActive  = true
        newTab.lastAccessedAt = Date()
        container.lastAccessedAt = Date()

        // Initialize the WebView for the new active tab
        newTab.restoreTransientState(
            historyManager: historyManager ?? HistoryManager(
                modelContainer: modelContainer,
                modelContext: modelContext
            ),
            downloadManager: downloadManager ?? DownloadManager(
                modelContainer: modelContainer,
                modelContext: modelContext
            ),
            tabManager: self,
            isPrivate: isPrivate
        )

        try? modelContext.save()
        return newTab
    }

    @discardableResult
    func openTab(
        url: URL,
        historyManager: HistoryManager,
        downloadManager: DownloadManager? = nil,
        focusAfterOpening: Bool = true,
        isPrivate: Bool,
        loadSilently: Bool = false
    ) -> Tab? {
        if let container = activeContainer {
            if let host = url.host {
                let faviconURL = FaviconService.shared.faviconURL(for: host)

                let cleanHost = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host

                let newTab = Tab(
                    url: url,
                    title: cleanHost,
                    favicon: faviconURL,
                    container: container,
                    type: .normal,
                    order: container.tabs.count + 1,
                    historyManager: historyManager,
                    downloadManager: downloadManager,
                    tabManager: self,
                    isPrivate: isPrivate
                )
                modelContext.insert(newTab)
                container.tabs.append(newTab)

                if focusAfterOpening {
                    activateTab(newTab)
                }
                if focusAfterOpening || loadSilently {
                    // Initialize the WebView for the new active tab
                    newTab.restoreTransientState(
                        historyManager: historyManager,
                        downloadManager: downloadManager ?? DownloadManager(
                            modelContainer: modelContainer,
                            modelContext: modelContext
                        ),
                        tabManager: self,
                        isPrivate: isPrivate
                    )
                }

                container.lastAccessedAt = Date()
                try? modelContext.save()
                return newTab
            }
        }
        return nil
    }

    func reorderTabs(from: Tab, toTab: Tab) {
        from.container.reorderTabs(from: from, to: toTab)
        try? modelContext.save()
    }

    func switchSections(from: Tab, toTab: Tab) {
        from.switchSections(from: from, to: toTab)
        try? modelContext.save()
    }

    func closeTab(tab: Tab, shouldTrackForRestore: Bool = true) {
        // If the closed tab was active, select another tab
        if self.activeTab?.id == tab.id {
            if let nextTab = tab.container.tabs
                .filter({ $0.id != tab.id && $0.isWebViewReady })
                .sorted(by: { $0.lastAccessedAt ?? Date.distantPast > $1.lastAccessedAt ?? Date.distantPast })
                .first
            {
                self.activateTab(nextTab)

            } else {
                self.activeTab = nil
            }
        } else {
            self.activeTab = activeTab
        }
        if activeTab?.isWebViewReady != nil, let historyManager = tab.historyManager,
           let downloadManager = tab.downloadManager, let tabManager = tab.tabManager
        {
            activeTab?
                .restoreTransientState(
                    historyManager: historyManager,
                    downloadManager: downloadManager,
                    tabManager: tabManager,
                    isPrivate: tab.isPrivate
                )
        }
        if shouldTrackForRestore, tab.type == .normal {
            trackRecentlyClosedTab(tab)
        }
        tab.stopMedia { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                if tab.type == .normal {
                    self.modelContext.delete(tab)
                } else {
                    tab.isWebViewReady = false
                    tab.destroyWebView()
                }
                try? self.modelContext.save()
            }
        }
        self.activeTab?.maybeIsActive = true
    }

    func closeActiveTab() {
        if let tab = activeTab {
            closeTab(tab: tab)
        } else {
            NSApp.keyWindow?.close()
        }
    }

    func restoreLastTab() {
        guard let snapshot = recentlyClosedTabs.popLast() else { return }
        guard let container = activeContainer else { return }

        shiftRestoredTabOrders(in: container, restoring: snapshot)

        let restoredTab = Tab(
            id: snapshot.id,
            url: snapshot.url,
            title: snapshot.title,
            favicon: snapshot.favicon,
            container: container,
            type: snapshot.type,
            order: snapshot.order,
            tabManager: self,
            isPrivate: snapshot.isPrivate
        )
        restoredTab.savedURL = snapshot.savedURL
        restoredTab.faviconLocalFile = snapshot.faviconLocalFile
        restoredTab.createdAt = snapshot.createdAt
        restoredTab.lastAccessedAt = snapshot.lastAccessedAt
        modelContext.insert(restoredTab)
        container.tabs.append(restoredTab)
        activateTab(restoredTab)
        try? modelContext.save()
    }

    func activateTab(_ tab: Tab) {
        guard tab.container.id == activeContainer?.id else { return }

        // Activate the tab
        activeTab?.maybeIsActive = false
        activeTab = tab
        activeTab?.maybeIsActive = true
        tab.lastAccessedAt = Date()
        tab.container.lastAccessedAt = Date()

        // Lazy load WebView if not ready
        if !tab.isWebViewReady {
            tab.restoreTransientState(
                historyManager: tab.historyManager ?? HistoryManager(
                    modelContainer: modelContainer,
                    modelContext: modelContext
                ),
                downloadManager: tab.downloadManager ?? DownloadManager(
                    modelContainer: modelContainer,
                    modelContext: modelContext
                ),
                tabManager: self,
                isPrivate: tab.isPrivate
            )
        }
        try? modelContext.save()
    }

    /// Clean up old tabs that haven't been accessed recently to preserve memory
    func cleanupOldTabs() {
        let timeout = SettingsStore.shared.tabAliveTimeout
        // Skip cleanup if set to "Never" (365 days)
        guard timeout < 365 * 24 * 60 * 60 else { return }

        guard let profile = activeContainer else { return }
        for tab in profile.tabs {
            if !tab.isAlive, tab.isWebViewReady, tab.id != activeTab?.id, tab.type == .normal {
                tab.destroyWebView()
            }
        }
    }

    /// Completely remove old normal tabs that haven't been accessed for a long time
    func removeOldTabs() {
        let cutoffDate = Date().addingTimeInterval(-SettingsStore.shared.tabRemovalTimeout)
        guard let profile = activeContainer else { return }

        for tab in profile.tabs {
            if let lastAccessed = tab.lastAccessedAt,
               lastAccessed < cutoffDate,
               tab.id != activeTab?.id,
               tab.type == .normal
            {
                closeTab(tab: tab, shouldTrackForRestore: false)
            }
        }
    }

    /// Start the automatic cleanup timer
    private func startCleanupTimer() {
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.cleanupOldTabs()
                self?.removeOldTabs()
            }
        }
    }

    deinit {
        cleanupTimer?.invalidate()
    }

    func activateTab(id: UUID) {
        if let tab = activeContainer?.tabs.first(where: { $0.id == id }) {
            activateTab(tab)
        }
    }

    func selectTabAtIndex(_ index: Int) {
        guard let container = activeContainer else { return }

        // Match the sidebar ordering: pinned, then normal tabs
        // All sorted by order in descending order
        let pinnedTabs = container.tabs
            .filter { $0.type == .pinned }
            .sorted(by: { $0.order > $1.order })

        let normalTabs = container.tabs
            .filter { $0.type == .normal }
            .sorted(by: { $0.order > $1.order })

        // Combine all tabs in the same order as the sidebar
        let allTabs = pinnedTabs + normalTabs

        // Handle special case: Command+9 selects the last tab
        let targetIndex = (index == 9) ? allTabs.count - 1 : index - 1

        // Validate index is within bounds
        guard targetIndex >= 0, targetIndex < allTabs.count else { return }

        let targetTab = allTabs[targetIndex]
        activateTab(targetTab)
    }

    private func fetchProfiles() -> [TabContainer] {
        do {
            let descriptor = FetchDescriptor<TabContainer>(sortBy: [SortDescriptor(\.lastAccessedAt, order: .reverse)])
            return try modelContext.fetch(descriptor)
        } catch {
            // Failed to fetch containers
        }
        return []
    }

    func duplicateTab(_ tab: Tab) {
        // Create a new tab using the existing openTab method
        guard let historyManager = tab.historyManager else { return }
        guard let newTab = openTab(
            url: tab.url,
            historyManager: historyManager,
            downloadManager: tab.downloadManager,
            focusAfterOpening: false,
            isPrivate: tab.isPrivate,
            loadSilently: true
        ) else { return }
        self.reorderTabs(from: tab, toTab: newTab)
    }

    func refreshPrivacySettings(for containerId: UUID) {
        guard let container = activeContainer, container.id == containerId else { return }

        let loadedTabs = container.tabs.filter(\.isWebViewReady)
        guard !loadedTabs.isEmpty else { return }

        for tab in loadedTabs {
            tab.refreshBrowserPageForPrivacySettings()
        }
    }

    private func trackRecentlyClosedTab(_ tab: Tab) {
        recentlyClosedTabs.append(ClosedTabSnapshot(tab: tab))
        if recentlyClosedTabs.count > maxRecentlyClosedTabs {
            recentlyClosedTabs.removeFirst(recentlyClosedTabs.count - maxRecentlyClosedTabs)
        }
    }

    private func shiftRestoredTabOrders(in container: TabContainer, restoring snapshot: ClosedTabSnapshot) {
        for tab in container.tabs where tab.type == snapshot.type && tab.order >= snapshot.order {
            tab.order += 1
        }
    }
}
