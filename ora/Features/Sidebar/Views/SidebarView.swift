import AppKit
import SwiftUI

struct SidebarView: View {
    @Environment(\.theme) private var theme
    @Environment(\.window) var window: NSWindow?
    @EnvironmentObject var tabManager: TabManager
    @EnvironmentObject var historyManager: HistoryManager
    @EnvironmentObject var downloadManager: DownloadManager
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var privacyMode: PrivacyMode
    @EnvironmentObject var sidebarManager: SidebarManager
    @EnvironmentObject var toolbarManager: ToolbarManager

    @State private var isHoveringSidebarToggle = false

    private var isShowingDownloads: Bool {
        downloadManager.isShowingDownloadsHistory
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let progress: CGFloat = isShowingDownloads ? 1 : 0

            ZStack(alignment: .leading) {
                // Tab content pushes back and blurs out when downloads is shown.
                tabsContent
                    .frame(width: width)
                    .offset(x: width * 0.12 * progress)
                    .scaleEffect(CGFloat(1.0) - 0.06 * progress, anchor: .center)
                    .opacity(CGFloat(1.0) - 0.5 * progress)
                    .allowsHitTesting(progress < 0.5)

                // Downloads history - slides in from leading edge
                DownloadsHistoryView()
                    .frame(width: width)
                    .offset(x: -width + width * progress)
                    .shadow(color: .black.opacity(0.08 * Double(progress)), radius: 8, x: 4, y: 0)
                    .allowsHitTesting(progress >= 0.5)
            }
            .clipped()
        }
    }

    // MARK: - Tabs Content

    private var tabsContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            if sidebarManager.sidebarPosition == .secondary, !toolbarManager.isToolbarHidden {
                Spacer().frame(height: 8)
            } else if appState.isFullscreen, !toolbarManager.isToolbarHidden {
                Spacer().frame(height: 8)
            } else {
                SidebarHeader()
            }
            if let container = tabManager.activeContainer {
                ContainerView(
                    container: container
                )
                .padding(.horizontal, 10)
                .environmentObject(tabManager)
                .environmentObject(historyManager)
                .environmentObject(downloadManager)
                .environmentObject(appState)
                .environmentObject(privacyMode)
                .environmentObject(toolbarManager)
            }

            if !privacyMode.isPrivate {
                HStack {
                    DownloadsWidget()
                }
                .padding(.horizontal, 10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(
            EdgeInsets(
                top: 4,
                leading: 0,
                bottom: 10,
                trailing: 0
            )
        )
        .onTapGesture(count: 2) {
            toggleMaximizeWindow()
        }
    }

    private func toggleMaximizeWindow() {
        window?.toggleMaximized()
    }
}
