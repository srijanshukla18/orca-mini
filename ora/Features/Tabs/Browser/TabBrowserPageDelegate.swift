import AppKit

final class TabBrowserPageDelegate: BrowserPageDelegate {
    weak var tab: Tab?

    private var progressResetWorkItem: DispatchWorkItem?
    private var lastRecordedURL: URL?

    func browserPage(
        _ page: BrowserPage,
        decidePolicyFor navigationAction: BrowserNavigationAction
    ) -> BrowserNavigationActionDisposition {
        guard navigationAction.modifierFlags.contains(.command),
              let url = navigationAction.request.url,
              let tab,
              let tabManager = tab.tabManager,
              let historyManager = tab.historyManager,
              let downloadManager = tab.downloadManager
        else {
            return .allow
        }

        MainActor.assumeIsolated {
            _ = tabManager.openTab(
                url: url,
                historyManager: historyManager,
                downloadManager: downloadManager,
                isPrivate: tab.isPrivate
            )
        }
        return .openInNewTab
    }

    func browserPage(_ page: BrowserPage, didRequestOpenInNewTab url: URL) {
        guard let tab,
              let tabManager = tab.tabManager,
              let historyManager = tab.historyManager
        else {
            return
        }

        MainActor.assumeIsolated {
            _ = tabManager.openTab(
                url: url,
                historyManager: historyManager,
                downloadManager: tab.downloadManager,
                isPrivate: tab.isPrivate
            )
        }
    }

    func browserPage(_ page: BrowserPage, didUpdateNavigation event: BrowserNavigationEvent) {
        guard let tab else { return }

        switch event.phase {
        case .started:
            progressResetWorkItem?.cancel()
            tab.clearNavigationError()
            tab.isLoading = event.isLoading
            tab.loadingProgress = event.progress
            if let url = event.url {
                tab.url = url
            }

        case .committed:
            tab.isLoading = event.isLoading
            tab.loadingProgress = event.progress
            if let title = event.title, !title.isEmpty {
                tab.title = title
            }

        case .finished:
            tab.isLoading = event.isLoading
            tab.loadingProgress = event.progress
            if let title = event.title, !title.isEmpty {
                tab.title = title
            }
            if let url = event.url {
                updateTab(tab, url: url, title: event.title)
                recordHistory(for: tab, url: url, force: true)
            }

            let workItem = DispatchWorkItem { [weak tab] in
                tab?.loadingProgress = 0
            }
            progressResetWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: workItem)
        }
    }

    func browserPage(_ page: BrowserPage, didUpdateDocumentMetadata metadata: BrowserDocumentMetadata) {
        guard let tab else { return }

        updateTab(tab, url: metadata.url, title: metadata.title)
        if !page.isLoading, let url = metadata.url {
            recordHistory(for: tab, url: url, force: false)
        }
    }

    func browserPage(_ page: BrowserPage, didFailNavigationWith error: Error, failingURL: URL?) {
        tab?.setNavigationError(error, for: failingURL)
    }

    func browserPage(
        _ page: BrowserPage,
        requestPermission permission: BrowserPermissionKind,
        origin: URL?,
        decisionHandler: @escaping (BrowserPermissionDecision) -> Void
    ) {
        decisionHandler(.grant)
    }

    func browserPage(
        _ page: BrowserPage,
        runOpenPanelWith options: BrowserOpenPanelOptions,
        completion: @escaping ([URL]?) -> Void
    ) {
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = options.allowsDirectories
        openPanel.allowsMultipleSelection = options.allowsMultipleSelection
        openPanel.begin { result in
            completion(result == .OK ? openPanel.urls : nil)
        }
    }

    func browserPage(_ page: BrowserPage, runJavaScriptAlert message: String) {
        let alert = NSAlert()
        alert.messageText = "Alert"
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    func browserPage(_ page: BrowserPage, runJavaScriptConfirm message: String, completion: @escaping (Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = "Confirm"
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        completion(alert.runModal() == .alertFirstButtonReturn)
    }

    func browserPage(
        _ page: BrowserPage,
        runJavaScriptPrompt prompt: String,
        defaultText: String?,
        completion: @escaping (String?) -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = "Prompt"
        alert.informativeText = prompt
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        textField.stringValue = defaultText ?? ""
        alert.accessoryView = textField

        if alert.runModal() == .alertFirstButtonReturn {
            completion(textField.stringValue)
        } else {
            completion(nil)
        }
    }

    func browserPage(_ page: BrowserPage, didStartDownload download: BrowserDownloadTask) {
        MainActor.assumeIsolated {
            tab?.downloadManager?.handleDownload(download)

            guard page.isDownloadNavigation, let tab else { return }

            if page.lastCommittedURL != nil {
                tab.goBack()
            } else if let tabManager = tab.tabManager {
                tabManager.closeTab(tab: tab)
            }
        }
    }

    private func updateTab(_ tab: Tab, url: URL?, title: String?) {
        if let title, !title.isEmpty {
            tab.title = title
        }

        guard let url else { return }
        let previousHost = tab.url.host
        tab.url = url
        let localFaviconMissing = tab.faviconLocalFile.map {
            !FileManager.default.fileExists(atPath: $0.path)
        } ?? true
        if tab.favicon == nil || previousHost != url.host || localFaviconMissing {
            if previousHost != url.host {
                tab.favicon = nil
                tab.faviconLocalFile = nil
            }
            tab.setFavicon()
        }
    }

    private func recordHistory(for tab: Tab, url: URL, force: Bool) {
        guard force || lastRecordedURL != url else { return }
        lastRecordedURL = url
        tab.updateHistory()
    }
}
