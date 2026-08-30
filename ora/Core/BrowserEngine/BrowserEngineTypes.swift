import AppKit
import Foundation

enum BrowserWebsiteDataType: Hashable {
    case cookies
    case cache
    case all
}

struct BrowserOpenPanelOptions {
    let allowsDirectories: Bool
    let allowsMultipleSelection: Bool
}

enum BrowserPermissionKind {
    case mediaCapture
}

enum BrowserPermissionDecision {
    case grant
    case deny
}

struct BrowserNavigationAction {
    let request: URLRequest
    let modifierFlags: NSEvent.ModifierFlags
}

enum BrowserNavigationActionDisposition {
    case allow
    case cancel
    case openInNewTab
}

enum BrowserNavigationPhase {
    case started
    case committed
    case finished
}

struct BrowserNavigationEvent {
    let phase: BrowserNavigationPhase
    let url: URL?
    let title: String?
    let progress: Double
    let isLoading: Bool
}

struct BrowserDocumentMetadata {
    let url: URL?
    let title: String?
}

struct BrowserSnapshotConfiguration {
    let rect: CGRect?
    let afterScreenUpdates: Bool
    let snapshotWidth: CGFloat?

    init(rect: CGRect?, afterScreenUpdates: Bool, snapshotWidth: CGFloat? = nil) {
        self.rect = rect
        self.afterScreenUpdates = afterScreenUpdates
        self.snapshotWidth = snapshotWidth
    }

    static let full = BrowserSnapshotConfiguration(rect: nil, afterScreenUpdates: false)
}
