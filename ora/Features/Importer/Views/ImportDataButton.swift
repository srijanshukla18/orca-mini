import SwiftUI

struct ImportDataButton: View {
    @EnvironmentObject var tabManager: TabManager
    @EnvironmentObject var historyManager: HistoryManager
    @EnvironmentObject var downloadManager: DownloadManager
    @EnvironmentObject var privacyMode: PrivacyMode

    func importArc() {
        guard let root = getRoot(), let profile = tabManager.activeContainer else { return }

        let result = inspectItems(root)
        let pinnedParentIDs = Set(result.cleanSpaces.flatMap(\.containerIDs))
        var importedURLs: Set<String> = []

        for tab in result.cleanTabs where importedURLs.insert(tab.urlString).inserted {
            guard let url = URL(string: tab.urlString) else { continue }

            let newTab = tabManager.addTab(
                title: tab.title,
                url: url,
                container: profile,
                historyManager: historyManager,
                downloadManager: downloadManager,
                isPrivate: privacyMode.isPrivate
            )
            newTab.title = tab.title

            if result.favs.contains(tab.parentID) || pinnedParentIDs.contains(tab.parentID) {
                tabManager.togglePinTab(newTab)
            }
        }
    }

    var body: some View {
        Menu("Import Data") {
            Button("Arc") {
                importArc()
            }
            Button("Safari") {
                // importSafari()
            }
            Button("Chrome") {
                // importChrome()
            }
        }
    }
}
