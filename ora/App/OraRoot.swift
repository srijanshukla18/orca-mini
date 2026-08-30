import Foundation
import SwiftData
import SwiftUI

final class PrivacyMode: ObservableObject {
    @Published var isPrivate: Bool

    init(isPrivate: Bool) {
        self.isPrivate = isPrivate
    }
}

struct OraRoot: View {
    @StateObject private var appState = AppState()
    @StateObject private var keyModifierListener = KeyModifierListener()
    @StateObject private var tabManager: TabManager
    @StateObject private var historyManager: HistoryManager
    @StateObject private var downloadManager: DownloadManager
    @StateObject private var privacyMode: PrivacyMode
    @StateObject private var sidebarManager = SidebarManager()
    @StateObject private var toolbarManager = ToolbarManager()
    @StateObject private var dialogManager = DialogManager()
    private let toastManager = ToastManager.shared

    let tabContext: ModelContext
    let historyContext: ModelContext
    let downloadContext: ModelContext
    @State private var window: NSWindow?
    @State private var notificationObservers: [NSObjectProtocol] = []
    @State private var keyDownHandlerIDs: [UUID] = []

    init(isPrivate: Bool = false) {
        _privacyMode = StateObject(wrappedValue: PrivacyMode(isPrivate: isPrivate))

        let container: ModelContainer
        let modelContext: ModelContext
        do {
            container = try ModelConfiguration.createOraContainer(isPrivate: isPrivate)
            modelContext = ModelContext(container)
        } catch {
            deleteSwiftDataStore("OraData.sqlite")
            fatalError("Failed to initialize ModelContainer: \(error)")
        }

        self.tabContext = modelContext
        self.downloadContext = modelContext
        self.historyContext = modelContext
        let historyManagerObj = StateObject(
            wrappedValue: HistoryManager(
                modelContainer: container,
                modelContext: modelContext
            )
        )
        _historyManager = historyManagerObj

        let tabManager = TabManager(
            modelContainer: container,
            modelContext: modelContext
        )
        _tabManager = StateObject(wrappedValue: tabManager)

        if !isPrivate, let profileID = tabManager.activeContainer?.id {
            let profile = BrowserEngine.shared.makeProfile(identifier: profileID, isPrivate: false)
            BrowserPrivacyService.shared.prewarm(spaceID: profileID, dataStore: profile.dataStore)
        }

        _downloadManager = StateObject(
            wrappedValue: DownloadManager(
                modelContainer: container,
                modelContext: modelContext
            )
        )
    }

    var body: some View {
        BrowserView()
            .background(WindowReader(window: $window))
            .background(
                WindowAccessor(
                    isFullscreen: Binding(
                        get: { appState.isFullscreen },
                        set: { newValue in appState.isFullscreen = newValue }
                    )
                )
            )
            .environment(\.window, window)
            .environmentObject(appState)
            .environmentObject(tabManager)
            .environmentObject(historyManager)
            .environmentObject(keyModifierListener)
            .environmentObject(CustomKeyboardShortcutManager.shared)
            .environmentObject(AppearanceManager.shared)
            .environmentObject(downloadManager)
            .environmentObject(privacyMode)
            .environmentObject(sidebarManager)
            .environmentObject(toolbarManager)
            .environmentObject(dialogManager)
            .environmentObject(toastManager)
            .dialogs(manager: dialogManager)
            .modelContext(tabContext)
            .modelContext(historyContext)
            .modelContext(downloadContext)
            .withTheme()
            .onAppear {
                downloadManager.toastManager = toastManager
                Task {
                    let profileIDs = await MainActor.run {
                        tabManager.activeContainer.map { [$0.id] } ?? []
                    }
                    await AdBlockService.shared.start(containerIDs: profileIDs)
                }

                guard notificationObservers.isEmpty, keyDownHandlerIDs.isEmpty else { return }

                // Dialog keyboard shortcuts (highest priority — checked first)
                keyDownHandlerIDs.append(keyModifierListener.registerKeyDownHandler { event in
                    // Escape: dismiss top dialog
                    if event.keyCode == 53, !dialogManager.dialogs.isEmpty {
                        DispatchQueue.main.async { dialogManager.dismissTop() }
                        return true
                    }
                    // Return: confirm top dialog (only if it carries a confirm action)
                    if event.keyCode == 36, let onConfirm = dialogManager.dialogs.last?.onConfirm {
                        DispatchQueue.main.async {
                            onConfirm()
                            dialogManager.dismissTop()
                        }
                        return true
                    }
                    return false
                })

                keyDownHandlerIDs.append(keyModifierListener.registerKeyDownHandler { event in
                    guard !appState.isFloatingTabSwitchVisible else { return false }

                    if event.keyCode == 48 {
                        if event.modifierFlags.contains(.control) {
                            DispatchQueue.main.async {
                                appState.isFloatingTabSwitchVisible = true
                            }
                            return true
                        }
                    }
                    return false
                })

                // Cmd+Q quit confirmation
                observe(.quitRequested) { note in
                    guard note.object as? NSWindow === window ?? NSApp.keyWindow else { return }
                    guard window != nil else {
                        NSApp.reply(toApplicationShouldTerminate: true)
                        return
                    }
                    dialogManager.confirm(
                        title: "Quit Orca Mini?",
                        message: "Are you sure you want to quit?",
                        iconImage: Image("OraColorLogo"),
                        confirmLabel: "Quit",
                        variant: .destructive,
                        onConfirm: { NSApp.reply(toApplicationShouldTerminate: true) },
                        onCancel: { NSApp.reply(toApplicationShouldTerminate: false) }
                    )
                }

                observe(.showLauncher) { note in
                    Task { @MainActor in
                        guard note.object as? NSWindow === window ?? NSApp.keyWindow else { return }
                        if tabManager.activeTab != nil {
                            appState.showLauncher.toggle()
                        }
                    }
                }
                observe(.closeActiveTab) { note in
                    Task { @MainActor in
                        guard note.object as? NSWindow === window ?? NSApp.keyWindow else { return }
                        tabManager.closeActiveTab()
                    }
                }
                observe(.restoreLastTab) { note in
                    Task { @MainActor in
                        guard note.object as? NSWindow === window ?? NSApp.keyWindow else { return }
                        tabManager.restoreLastTab()
                    }
                }
                observe(.findInPage) { note in
                    Task { @MainActor in
                        guard note.object as? NSWindow === window ?? NSApp.keyWindow else { return }
                        if let activeTab = tabManager.activeTab {
                            appState.showFinderIn = activeTab.id
                        }
                    }
                }
                observe(.toggleFullURL) { note in
                    guard note.object as? NSWindow === window ?? NSApp.keyWindow else { return }
                    toolbarManager.showFullURL.toggle()
                }
                observe(.toggleToolbar) { note in
                    guard note.object as? NSWindow === window ?? NSApp.keyWindow else { return }
                    withAnimation(.easeInOut(duration: 0.2)) {
                        toolbarManager.isToolbarHidden.toggle()
                    }
                }
                observe(.reloadPage) { note in
                    Task { @MainActor in
                        guard note.object as? NSWindow === window ?? NSApp.keyWindow else { return }
                        tabManager.activeTab?.reload()
                    }
                }
                observe(.goBack) { note in
                    Task { @MainActor in
                        guard note.object as? NSWindow === window ?? NSApp.keyWindow else { return }
                        tabManager.activeTab?.goBack()
                    }
                }
                observe(.goForward) { note in
                    Task { @MainActor in
                        guard note.object as? NSWindow === window ?? NSApp.keyWindow else { return }
                        tabManager.activeTab?.goForward()
                    }
                }
                observe(.togglePinTab) { note in
                    Task { @MainActor in
                        guard note.object as? NSWindow === window ?? NSApp.keyWindow else { return }
                        if let tab = tabManager.activeTab {
                            tabManager.togglePinTab(tab)
                        }
                    }
                }
                observe(.nextTab) { note in
                    guard note.object as? NSWindow === window ?? NSApp.keyWindow else { return }
                    appState.isFloatingTabSwitchVisible = true
                }
                observe(.previousTab) { note in
                    guard note.object as? NSWindow === window ?? NSApp.keyWindow else { return }
                    appState.isFloatingTabSwitchVisible = true
                }
                observe(.setAppearance) { note in
                    guard note.object as? NSWindow === window ?? NSApp.keyWindow else { return }
                    if let raw = note.userInfo?["appearance"] as? String,
                       let mode = AppAppearance(rawValue: raw)
                    {
                        AppearanceManager.shared.appearance = mode
                    }
                }
                observe(.selectTabAtIndex) { note in
                    Task { @MainActor in
                        guard note.object as? NSWindow === window ?? NSApp.keyWindow else { return }
                        if let index = note.userInfo?["index"] as? Int {
                            tabManager.selectTabAtIndex(index)
                        }
                    }
                }
                observe(.showWebInspector) { note in
                    Task { @MainActor in
                        guard note.object as? NSWindow === window ?? NSApp.keyWindow else { return }
                        if tabManager.activeTab?.showWebInspector() != true {
                            toastManager.show("Web Inspector unavailable", icon: .system("exclamationmark.triangle"))
                        }
                    }
                }
                observe(.openURL) { note in
                    Task { @MainActor in
                        let targetWindow = window ?? NSApp.keyWindow
                        if let sender = note.object as? NSWindow {
                            guard sender === targetWindow else { return }
                        } else {
                            guard NSApp.keyWindow === targetWindow else { return }
                        }
                        guard let url = note.userInfo?["url"] as? URL else { return }
                        tabManager.openTab(
                            url: url,
                            historyManager: historyManager,
                            downloadManager: downloadManager,
                            focusAfterOpening: true,
                            isPrivate: privacyMode.isPrivate
                        )
                    }
                }

                observe(.spacePrivacySettingsChanged) { note in
                    Task { @MainActor in
                        guard let containerId = note.userInfo?["containerId"] as? UUID else { return }
                        tabManager.refreshPrivacySettings(for: containerId)
                    }
                }

                // Clear cache and reload
                observe(.clearCacheAndReload) { note in
                    Task { @MainActor in
                        guard note.object as? NSWindow === window ?? NSApp.keyWindow else { return }
                        if let activeTab = tabManager.activeTab {
                            let host = activeTab.url.host ?? ""
                            let domain = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
                            PrivacyService
                                .clearCacheForHost(
                                    for: domain,
                                    container: activeTab.container
                                ) { [weak toastManager] in
                                    DispatchQueue.main.async {
                                        activeTab.reload()
                                        toastManager?.show("Cache cleared for \(domain)", icon: .system("trash"))
                                    }
                                }
                        }
                    }
                }

                // Clear cookies and reload
                observe(.clearCookiesAndReload) { note in
                    Task { @MainActor in
                        guard note.object as? NSWindow === window ?? NSApp.keyWindow else { return }

                        if let activeTab = tabManager.activeTab {
                            let host = activeTab.url.host ?? ""
                            let domain = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
                            PrivacyService
                                .clearCookiesForHost(
                                    for: host,
                                    container: activeTab.container
                                ) { [weak toastManager] in
                                    DispatchQueue.main.async {
                                        activeTab.reload()
                                        toastManager?.show("Cookies cleared for \(domain)", icon: .system("trash"))
                                    }
                                }
                        }
                    }
                }
            }
            .onDisappear(perform: removeEventHandlers)
    }

    private func observe(
        _ name: Notification.Name,
        using block: @escaping @Sendable (Notification) -> Void
    ) {
        notificationObservers.append(
            NotificationCenter.default.addObserver(
                forName: name,
                object: nil,
                queue: .main,
                using: block
            )
        )
    }

    private func removeEventHandlers() {
        notificationObservers.forEach(NotificationCenter.default.removeObserver)
        notificationObservers.removeAll()

        keyDownHandlerIDs.forEach(keyModifierListener.unregisterKeyDownHandler)
        keyDownHandlerIDs.removeAll()
    }
}
