import AppKit
@testable import Ora
import Testing

@MainActor
struct BrowserPageHostViewTests {
    @Test func usesNativeWebKitUserAgentWithoutAppendedOverride() async throws {
        let settings = SpacePrivacySettings()
        let delegate = MetadataRecordingDelegate()
        let htmlURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("orca-native-user-agent-\(UUID().uuidString).html")
        try Data("<title>User Agent Test</title>".utf8).write(to: htmlURL)
        defer { try? FileManager.default.removeItem(at: htmlURL) }

        let page = BrowserPage(
            profile: BrowserEngineProfile(identifier: UUID(), isPrivate: true),
            configuration: .oraDefault(privacySettings: settings),
            delegate: delegate
        )
        defer { page.teardown() }

        page.load(URLRequest(url: htmlURL))
        try await waitUntil {
            delegate.updates.contains { $0.title == "User Agent Test" }
        }

        var userAgent: String?
        var scriptFinished = false
        page.evaluateJavaScript("navigator.userAgent") { value, _ in
            userAgent = value as? String
            scriptFinished = true
        }
        try await waitUntil { scriptFinished }

        let resolvedUserAgent = try #require(userAgent)
        #expect(resolvedUserAgent.contains("AppleWebKit/"))
        #expect(resolvedUserAgent.components(separatedBy: "Mozilla/5.0").count == 2)
    }

    @Test func nativeMetadataObservationTracksSameDocumentNavigation() async throws {
        let settings = SpacePrivacySettings()
        let delegate = MetadataRecordingDelegate()
        let htmlURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ora-native-metadata-\(UUID().uuidString).html")
        try Data("<title>Native Start</title>".utf8).write(to: htmlURL)
        defer { try? FileManager.default.removeItem(at: htmlURL) }

        let page = BrowserPage(
            profile: BrowserEngineProfile(identifier: UUID(), isPrivate: true),
            configuration: .oraDefault(privacySettings: settings),
            delegate: delegate
        )
        defer { page.teardown() }

        page.load(URLRequest(url: htmlURL))
        try await waitUntil {
            delegate.updates.contains { $0.title == "Native Start" }
        }

        var scriptFinished = false
        var scriptError: Error?
        page.evaluateJavaScript("history.pushState({}, '', '#spa'); document.title = 'Native SPA';") { _, error in
            scriptError = error
            scriptFinished = true
        }
        try await waitUntil { scriptFinished }
        #expect(scriptError == nil)
        try await waitUntil {
            delegate.updates.contains {
                $0.title == "Native SPA" && $0.url?.fragment == "spa"
            }
        }

        #expect(delegate.updates.contains {
            $0.title == "Native SPA" && $0.url?.fragment == "spa"
        })
    }

    @Test func attachingFirstContentViewAddsSubview() {
        let host = makeHost()
        let contentView = TrackingContentView()

        host.host(contentView: contentView)

        #expect(host.subviews.count == 1)
        #expect(host.subviews.first === contentView)
        #expect(host.hostedContentView === contentView)
        #expect(contentView.frame == host.bounds)
    }

    @Test func switchingContentViewsDetachesOldViewAndAttachesNewView() {
        let host = makeHost()
        let firstContentView = TrackingContentView()
        let secondContentView = TrackingContentView()

        host.host(contentView: firstContentView)
        host.host(contentView: secondContentView)

        #expect(host.subviews.count == 1)
        #expect(host.subviews.first === secondContentView)
        #expect(host.hostedContentView === secondContentView)
        #expect(firstContentView.superview == nil)
        #expect(secondContentView.superview === host)
    }

    @Test func updatingWithSameContentViewIsANoOp() {
        let host = makeHost()
        let contentView = TrackingContentView()

        host.host(contentView: contentView)
        let transitionCountAfterFirstAttach = contentView.superviewTransitions

        host.host(contentView: contentView)

        #expect(host.subviews.count == 1)
        #expect(host.subviews.first === contentView)
        #expect(contentView.superviewTransitions == transitionCountAfterFirstAttach)
    }

    @Test func clearingContentViewRemovesHostedSubview() {
        let host = makeHost()
        let contentView = TrackingContentView()

        host.host(contentView: contentView)
        host.host(contentView: nil)

        #expect(host.subviews.isEmpty)
        #expect(host.hostedContentView == nil)
        #expect(contentView.superview == nil)
    }

    @Test func attachingContentViewFromAnotherHostReparentsItCleanly() {
        let firstHost = makeHost()
        let secondHost = makeHost()
        let contentView = TrackingContentView()

        firstHost.host(contentView: contentView)
        secondHost.host(contentView: contentView)

        #expect(firstHost.subviews.isEmpty)
        #expect(firstHost.hostedContentView == nil)
        #expect(secondHost.subviews.count == 1)
        #expect(secondHost.subviews.first === contentView)
        #expect(secondHost.hostedContentView === contentView)
        #expect(contentView.superview === secondHost)
        #expect(contentView.removeFromSuperviewCalls == 1)
    }

    @Test func switchingToAStaleSubviewAlreadyAttachedToTheSameHostDoesNotReparentIt() {
        let host = makeHost()
        let firstContentView = TrackingContentView()
        let staleContentView = TrackingContentView()

        host.host(contentView: firstContentView)
        host.addSubview(staleContentView)

        let staleSuperviewTransitions = staleContentView.superviewTransitions

        host.host(contentView: staleContentView)

        #expect(host.subviews.count == 1)
        #expect(host.subviews.first === staleContentView)
        #expect(host.hostedContentView === staleContentView)
        #expect(firstContentView.superview == nil)
        #expect(staleContentView.superview === host)
        #expect(staleContentView.superviewTransitions == staleSuperviewTransitions)
        #expect(staleContentView.removeFromSuperviewCalls == 0)
    }

    private func makeHost() -> BrowserPageHostView {
        BrowserPageHostView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    }

    private func waitUntil(
        timeoutIterations: Int = 100,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        for _ in 0 ..< timeoutIterations {
            if condition() {
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        Issue.record("Timed out waiting for native WKWebView metadata observation")
    }
}

private final class MetadataRecordingDelegate: BrowserPageDelegate {
    private(set) var updates: [BrowserDocumentMetadata] = []

    func browserPage(_ page: BrowserPage, didUpdateDocumentMetadata metadata: BrowserDocumentMetadata) {
        updates.append(metadata)
    }
}

private final class TrackingContentView: NSView {
    var superviewTransitions = 0
    var removeFromSuperviewCalls = 0

    override func removeFromSuperview() {
        removeFromSuperviewCalls += 1
        super.removeFromSuperview()
    }

    override func viewWillMove(toSuperview newSuperview: NSView?) {
        superviewTransitions += 1
        super.viewWillMove(toSuperview: newSuperview)
    }
}
