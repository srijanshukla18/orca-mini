import Foundation
@preconcurrency import WebKit

final class BrowserPrivacyService {
    private enum StaticRuleListIdentifier: String {
        case trackers = "com.orabrowser.privacy.trackers.v1"
        case thirdPartyCookies = "com.orabrowser.privacy.cookies.third-party.v1"
        case allCookies = "com.orabrowser.privacy.cookies.all.v1"
    }

    static let shared = BrowserPrivacyService()

    private final class CookiePolicyState {
        struct Request {
            let policy: CookiesPolicy
            let completion: () -> Void
        }

        weak var dataStore: WKWebsiteDataStore?
        var appliedPolicy: CookiesPolicy?
        var requests: [Request] = []
        var isApplying = false

        init(dataStore: WKWebsiteDataStore) {
            self.dataStore = dataStore
        }
    }

    private let ruleListStore = WKContentRuleListStore.default()!
    private let cacheLock = NSLock()
    private let artifactStore = ContentBlockerArtifactStore.shared
    private var cachedRuleLists: [String: WKContentRuleList] = [:]
    private var pendingRuleListCallbacks: [String: [(WKContentRuleList?) -> Void]] = [:]
    private var cookiePolicyStates: [ObjectIdentifier: CookiePolicyState] = [:]

    func activeRuleListIdentifiers(for spaceID: UUID) -> [String] {
        let privacySettings = SettingsStore.shared.privacySettings(for: spaceID)
        guard privacySettings.adBlock.enabled else { return [] }

        return SettingsStore.shared.adBlockFilterLists
            .filter { privacySettings.adBlock.enabledListIDs.contains($0.id) }
            .flatMap { record -> [String] in
                guard let revision = record.activeRevision else { return [] }
                return artifactStore.ruleListIdentifiers(for: record.id, revision: revision)
            }
    }

    func prepareConfiguration(
        _ configuration: WKWebViewConfiguration,
        spaceID: UUID,
        completion: @escaping () -> Void
    ) {
        let privacySettings = SettingsStore.shared.privacySettings(for: spaceID)
        let enabledRuleLists = enabledRuleLists(for: spaceID, privacySettings: privacySettings)
        let group = DispatchGroup()

        for identifier in enabledRuleLists {
            group.enter()
            contentRuleList(for: identifier) { ruleList in
                DispatchQueue.main.async {
                    if let ruleList {
                        configuration.userContentController.add(ruleList)
                    }
                    group.leave()
                }
            }
        }

        group.enter()
        applyCookiePolicy(privacySettings.cookiesPolicy, to: configuration.websiteDataStore) {
            group.leave()
        }

        group.notify(queue: .main, execute: completion)
    }

    /// Starts profile-scoped privacy preparation before the first page asks to navigate.
    /// Rule-list lookups and cookie policy application share the same caches/in-flight
    /// work used by `prepareConfiguration`.
    func prewarm(spaceID: UUID, dataStore: WKWebsiteDataStore) {
        let privacySettings = SettingsStore.shared.privacySettings(for: spaceID)
        for identifier in enabledRuleLists(for: spaceID, privacySettings: privacySettings) {
            contentRuleList(for: identifier) { _ in }
        }
        applyCookiePolicy(privacySettings.cookiesPolicy, to: dataStore) {}
    }

    private func enabledRuleLists(for spaceID: UUID, privacySettings: SpacePrivacySettings) -> [String] {
        var identifiers: [String] = []

        if privacySettings.blockThirdPartyTrackers {
            identifiers.append(StaticRuleListIdentifier.trackers.rawValue)
        }

        switch privacySettings.cookiesPolicy {
        case .allowAll:
            break
        case .blockThirdParty:
            identifiers.append(StaticRuleListIdentifier.thirdPartyCookies.rawValue)
        case .blockAll:
            identifiers.append(StaticRuleListIdentifier.allCookies.rawValue)
        }

        return identifiers + activeRuleListIdentifiers(for: spaceID)
    }

    private func applyCookiePolicy(
        _ policy: CookiesPolicy,
        to dataStore: WKWebsiteDataStore,
        completion: @escaping () -> Void
    ) {
        guard #available(macOS 14.0, *) else {
            completion()
            return
        }

        let key = ObjectIdentifier(dataStore)
        var shouldStartApplying = false

        cacheLock.lock()
        let state: CookiePolicyState
        if let existing = cookiePolicyStates[key], existing.dataStore === dataStore {
            state = existing
        } else {
            state = CookiePolicyState(dataStore: dataStore)
            cookiePolicyStates[key] = state
        }

        if state.appliedPolicy?.rawValue == policy.rawValue, !state.isApplying, state.requests.isEmpty {
            cacheLock.unlock()
            completion()
            return
        }

        state.requests.append(.init(policy: policy, completion: completion))
        if !state.isApplying {
            state.isApplying = true
            shouldStartApplying = true
        }
        cacheLock.unlock()

        if shouldStartApplying {
            processNextCookiePolicyRequest(for: key)
        }
    }

    private func processNextCookiePolicyRequest(for key: ObjectIdentifier) {
        cacheLock.lock()
        guard let state = cookiePolicyStates[key], let dataStore = state.dataStore else {
            cookiePolicyStates.removeValue(forKey: key)
            cacheLock.unlock()
            return
        }

        guard !state.requests.isEmpty else {
            state.isApplying = false
            cacheLock.unlock()
            return
        }

        let request = state.requests.removeFirst()
        if state.appliedPolicy?.rawValue == request.policy.rawValue {
            cacheLock.unlock()
            request.completion()
            DispatchQueue.main.async { [weak self] in
                self?.processNextCookiePolicyRequest(for: key)
            }
            return
        }
        cacheLock.unlock()

        let webKitPolicy: WKHTTPCookieStore.CookiePolicy = switch request.policy {
        case .blockAll:
            .disallow
        case .allowAll, .blockThirdParty:
            .allow
        }

        dataStore.httpCookieStore.setCookiePolicy(webKitPolicy) { [weak self] in
            guard let self else {
                request.completion()
                return
            }

            self.cacheLock.lock()
            if let state = self.cookiePolicyStates[key], state.dataStore === dataStore {
                state.appliedPolicy = request.policy
            }
            self.cacheLock.unlock()

            request.completion()
            self.processNextCookiePolicyRequest(for: key)
        }
    }

    private func contentRuleList(
        for identifier: String,
        completion: @escaping (WKContentRuleList?) -> Void
    ) {
        cacheLock.lock()
        if let cachedRuleList = cachedRuleLists[identifier] {
            cacheLock.unlock()
            completion(cachedRuleList)
            return
        }

        if pendingRuleListCallbacks[identifier] != nil {
            pendingRuleListCallbacks[identifier, default: []].append(completion)
            cacheLock.unlock()
            return
        }

        pendingRuleListCallbacks[identifier] = [completion]
        cacheLock.unlock()

        ruleListStore.lookUpContentRuleList(forIdentifier: identifier) { [weak self] ruleList, _ in
            guard let self else { return }

            if let ruleList {
                self.finishLoadingRuleList(identifier, ruleList: ruleList)
                return
            }

            guard let encodedRuleList = Self.encodedRuleList(for: identifier, artifactStore: self.artifactStore) else {
                self.finishLoadingRuleList(identifier, ruleList: nil)
                return
            }

            self.ruleListStore.compileContentRuleList(
                forIdentifier: identifier,
                encodedContentRuleList: encodedRuleList
            ) { [weak self] compiledRuleList, error in
                if let error {
                    print("Failed to compile privacy rule list \(identifier): \(error.localizedDescription)")
                }
                self?.finishLoadingRuleList(identifier, ruleList: compiledRuleList)
            }
        }
    }

    private func finishLoadingRuleList(_ identifier: String, ruleList: WKContentRuleList?) {
        cacheLock.lock()
        if let ruleList {
            cachedRuleLists[identifier] = ruleList
        }
        let callbacks = pendingRuleListCallbacks.removeValue(forKey: identifier) ?? []
        cacheLock.unlock()

        callbacks.forEach { $0(ruleList) }
    }

    private static func encodedRuleList(
        for identifier: String,
        artifactStore: ContentBlockerArtifactStore
    ) -> String? {
        switch identifier {
        case StaticRuleListIdentifier.trackers.rawValue:
            return encodeRules(networkBlockingRules(for: trackerDomains))
        case StaticRuleListIdentifier.thirdPartyCookies.rawValue:
            return encodeRules([
                [
                    "trigger": [
                        "url-filter": ".*",
                        "load-type": ["third-party"]
                    ],
                    "action": ["type": "block-cookies"]
                ]
            ])
        case StaticRuleListIdentifier.allCookies.rawValue:
            return encodeRules([
                [
                    "trigger": ["url-filter": ".*"],
                    "action": ["type": "block-cookies"]
                ]
            ])
        default:
            return artifactStore.encodedRuleList(for: identifier)
        }
    }

    private static func networkBlockingRules(for domains: [String]) -> [[String: Any]] {
        domains.map { domain in
            [
                "trigger": [
                    "url-filter": regexForDomain(domain),
                    "load-type": ["third-party"]
                ],
                "action": ["type": "block"]
            ]
        }
    }

    static func regexForDomain(_ domain: String) -> String {
        let escapedDomain = NSRegularExpression.escapedPattern(for: domain)
        return "^https?://([^/]+\\.)?\(escapedDomain)(?:[/:]|$)"
    }

    private static func encodeRules(_ rules: [[String: Any]]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: rules, options: []),
              let encoded = String(data: data, encoding: .utf8)
        else {
            return "[]"
        }

        return encoded
    }

    private static let trackerDomains = [
        "google-analytics.com",
        "googletagmanager.com",
        "doubleclick.net",
        "googleadservices.com",
        "facebook.net",
        "connect.facebook.net",
        "analytics.twitter.com",
        "ads-twitter.com",
        "snap.licdn.com",
        "px.ads.linkedin.com",
        "bat.bing.com",
        "clarity.ms",
        "cdn.segment.com",
        "api.segment.io",
        "api.amplitude.com",
        "cdn.amplitude.com",
        "mixpanel.com",
        "api.mixpanel.com",
        "fullstory.com",
        "edge.fullstory.com",
        "static.hotjar.com",
        "script.hotjar.com",
        "intercom.io",
        "widget.intercom.io",
        "static.intercomassets.com"
    ]
}
