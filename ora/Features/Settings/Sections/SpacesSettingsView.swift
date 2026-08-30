import SwiftData
import SwiftUI

// swiftlint:disable type_body_length large_tuple
struct PrivacySettingsView: View {
    private enum ClearDataAction: Hashable {
        case cache(UUID)
        case cookies(UUID)
        case history(UUID)
    }

    @Query(sort: \TabContainer.lastAccessedAt, order: .reverse) private var profiles: [TabContainer]

    @StateObject private var settings = SettingsStore.shared
    @State private var completedClearActions: Set<ClearDataAction> = []
    @State private var newCustomFilterListURL = ""
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var toastManager: ToastManager

    private var profile: TabContainer? {
        profiles.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let container = profile {
                    privacySettingsCard(for: container)
                    adBlockingSettingsCard(for: container)

                    SettingsCard(header: "Clear Data") {
                        VStack(spacing: 8) {
                            Button(
                                clearDataButtonTitle(
                                    for: .cache(container.id),
                                    defaultTitle: "Clear Cache",
                                    completedTitle: "Cache Cleared"
                                )
                            ) {
                                PrivacyService.clearCache(container) {
                                    DispatchQueue.main.async {
                                        completedClearActions.insert(.cache(container.id))
                                        toastManager.show("Cache cleared", icon: .system("trash"))
                                    }
                                }
                            }
                            .disabled(completedClearActions.contains(.cache(container.id)))
                            .frame(maxWidth: .infinity, alignment: .leading)

                            Button(
                                clearDataButtonTitle(
                                    for: .cookies(container.id),
                                    defaultTitle: "Clear Cookies",
                                    completedTitle: "Cookies Cleared"
                                )
                            ) {
                                PrivacyService.clearCookies(container) {
                                    DispatchQueue.main.async {
                                        completedClearActions.insert(.cookies(container.id))
                                        toastManager.show("Cookies cleared", icon: .system("trash"))
                                    }
                                }
                            }
                            .disabled(completedClearActions.contains(.cookies(container.id)))
                            .frame(maxWidth: .infinity, alignment: .leading)

                            Button(
                                clearDataButtonTitle(
                                    for: .history(container.id),
                                    defaultTitle: "Clear History",
                                    completedTitle: "History Cleared"
                                )
                            ) {
                                if clearHistory(for: container) {
                                    completedClearActions.insert(.history(container.id))
                                    toastManager.show("History cleared", icon: .system("trash"))
                                }
                            }
                            .disabled(completedClearActions.contains(.history(container.id)))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.bordered)
                    }
                } else {
                    Text("Browser profile unavailable")
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .onAppear {
            if let profile {
                Task { await AdBlockService.shared.registerSpace(containerId: profile.id) }
            }
        }
    }

    private func clearHistory(for container: TabContainer) -> Bool {
        let containerId = container.id
        let descriptor = FetchDescriptor<History>(
            predicate: #Predicate { $0.container?.id == containerId }
        )

        do {
            let histories = try modelContext.fetch(descriptor)
            for history in histories {
                modelContext.delete(history)
            }
            try modelContext.save()
            return true
        } catch {
            print("Failed to clear history for container \(container.id): \(error.localizedDescription)")
            return false
        }
    }

    private func clearDataButtonTitle(
        for action: ClearDataAction,
        defaultTitle: String,
        completedTitle: String
    ) -> String {
        completedClearActions.contains(action) ? completedTitle : defaultTitle
    }

    private func privacySettingsCard(for container: TabContainer) -> some View {
        SettingsCard(header: "Privacy") {
            Text(
                "These protections apply to the browser profile. Open tabs are refreshed automatically."
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)

            Toggle(
                "Block third-party trackers",
                isOn: privacyBinding(for: container, keyPath: \.blockThirdPartyTrackers)
            )

            Divider()

            Picker(
                "Cookies",
                selection: privacyBinding(for: container, keyPath: \.cookiesPolicy)
            ) {
                ForEach(CookiesPolicy.allCases) { policy in
                    Text(policy.rawValue).tag(policy)
                }
            }
            .pickerStyle(.radioGroup)
        }
    }

    @ViewBuilder
    private func adBlockingSettingsCard(for container: TabContainer) -> some View {
        let privacySettings = settings.privacySettings(for: container.id)
        let enabledRecords = enabledAdBlockRecords(for: container)
        let builtinRecords = settings.adBlockFilterLists.filter(\.isBuiltin)
        let customRecords = settings.adBlockFilterLists.filter { $0.sourceKind == .custom }
        let summary = adBlockSummary(for: container)

        SettingsCard(
            header: "Ad Blocking",
            description: "Powered by embedded AdGuard filter lists compiled for WebKit."
        ) {
            Toggle("Enable Ad Blocking", isOn: adBlockEnabledBinding(for: container))

            Divider()

            Picker("Update Policy", selection: adBlockUpdateModeBinding(for: container)) {
                ForEach(AdBlockUpdateMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.menu)

            HStack(spacing: 12) {
                Button("Refresh Now") {
                    Task {
                        let changed = await AdBlockService.shared.refreshSpace(
                            containerId: container.id,
                            reason: .manual
                        )
                        _ = await MainActor.run {
                            toastManager.show(
                                changed ? "Filter lists updated" :
                                    "Filter lists are already current",
                                type: .info,
                                icon: .system("arrow.clockwise.circle")
                            )
                        }
                    }
                }
                .disabled(!privacySettings.adBlock.enabled || enabledRecords.isEmpty || summary.isUpdating)

                if summary.isUpdating {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("Status")
                    .font(.subheadline.weight(.semibold))
                Text(summary.statusText)
                    .foregroundStyle(summary.hasFailures ? .red : .secondary)
                if let lastUpdatedText = summary.lastUpdatedText {
                    Text("Last updated \(lastUpdatedText)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let coverageText = summary.coverageText {
                    Text(coverageText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("Built-In Lists")
                    .font(.subheadline.weight(.semibold))

                ForEach(builtinRecords) { record in
                    filterListRow(for: container, record: record, showRemoveButton: false)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("Custom Lists")
                    .font(.subheadline.weight(.semibold))

                HStack(alignment: .center, spacing: 10) {
                    TextField("https://example.com/filter.txt", text: $newCustomFilterListURL)
                        .textFieldStyle(.roundedBorder)
                    Button("Add") {
                        addCustomFilterList(for: container)
                    }
                    .disabled(newCustomFilterListURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if customRecords.isEmpty {
                    Text("Add a remote AdGuard-style filter list URL.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(customRecords) { record in
                        filterListRow(for: container, record: record, showRemoveButton: true)
                    }
                }
            }
        }
    }

    private func filterListRow(
        for container: TabContainer,
        record: FilterListRecord,
        showRemoveButton: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Toggle(isOn: adBlockFilterBinding(for: container, record: record)) {
                    VStack(alignment: .leading, spacing: 4) {
                        if record.sourceKind == .custom {
                            TextField(
                                "Custom list name",
                                text: customFilterNameBinding(for: record)
                            )
                            .textFieldStyle(.roundedBorder)
                        } else {
                            Text(record.name)
                                .font(.body.weight(.medium))
                        }
                        Text(record.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(filterListStatusText(for: record))
                            .font(.caption)
                            .foregroundStyle(record.status == .failed ? .red : .secondary)
                    }
                }
                .toggleStyle(.checkbox)

                if showRemoveButton {
                    Button("Remove", role: .destructive) {
                        Task {
                            await AdBlockService.shared.removeCustomList(id: record.id)
                            _ = await MainActor.run {
                                toastManager.show("Removed \(record.name)", type: .info, icon: .system("trash"))
                            }
                        }
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    private func privacyBinding<Value>(
        for container: TabContainer,
        keyPath: WritableKeyPath<SpacePrivacySettings, Value>
    ) -> Binding<Value> {
        Binding(
            get: {
                settings.privacySettings(for: container.id)[keyPath: keyPath]
            },
            set: { newValue in
                var updatedSettings = settings.privacySettings(for: container.id)
                updatedSettings[keyPath: keyPath] = newValue
                settings.setPrivacySettings(updatedSettings, for: container.id)
                settings.notifySpacePrivacySettingsChanged(for: container.id)
            }
        )
    }

    private func adBlockEnabledBinding(for container: TabContainer) -> Binding<Bool> {
        Binding(
            get: {
                settings.privacySettings(for: container.id).adBlock.enabled
            },
            set: { newValue in
                applyAdBlockSettingsChange(for: container) { updatedSettings in
                    updatedSettings.adBlock.enabled = newValue
                }
            }
        )
    }

    private func adBlockUpdateModeBinding(for container: TabContainer) -> Binding<AdBlockUpdateMode> {
        Binding(
            get: {
                settings.privacySettings(for: container.id).adBlock.updateMode
            },
            set: { newValue in
                var updatedSettings = settings.privacySettings(for: container.id)
                updatedSettings.adBlock.updateMode = newValue
                settings.setPrivacySettings(updatedSettings, for: container.id)
                Task {
                    await AdBlockService.shared.spaceSettingsDidChange(containerId: container.id)
                }
            }
        )
    }

    private func adBlockFilterBinding(for container: TabContainer, record: FilterListRecord) -> Binding<Bool> {
        Binding(
            get: {
                settings.privacySettings(for: container.id).adBlock.isEnabled(record)
            },
            set: { isEnabled in
                applyAdBlockSettingsChange(for: container) { updatedSettings in
                    updatedSettings.adBlock.setEnabled(isEnabled, for: record)
                }
            }
        )
    }

    private func customFilterNameBinding(for record: FilterListRecord) -> Binding<String> {
        Binding(
            get: {
                settings.adBlockFilterList(id: record.id)?.name ?? record.name
            },
            set: { newValue in
                guard var updatedRecord = settings.adBlockFilterList(id: record.id) else { return }
                updatedRecord.name = newValue
                settings.upsertAdBlockFilterList(updatedRecord)
            }
        )
    }

    private func addCustomFilterList(for container: TabContainer) {
        let submittedURL = newCustomFilterListURL
        Task {
            do {
                let record = try await AdBlockService.shared.addCustomList(sourceURL: submittedURL)
                await AdBlockService.shared.spaceSettingsDidChange(containerId: container.id)
                await MainActor.run { () in
                    newCustomFilterListURL = ""
                    _ = toastManager.show("Added \(record.name)", icon: .system("checkmark.circle"))
                }
            } catch {
                await MainActor.run { () in
                    _ = toastManager.show(error.localizedDescription, type: .error)
                }
            }
        }
    }

    private func applyAdBlockSettingsChange(
        for container: TabContainer,
        mutate: (inout SpacePrivacySettings) -> Void
    ) {
        var updatedSettings = settings.privacySettings(for: container.id)
        mutate(&updatedSettings)
        settings.setPrivacySettings(updatedSettings, for: container.id)
        Task {
            await AdBlockService.shared.refreshSpace(containerId: container.id, reason: .settingsChanged)
        }
    }

    private func enabledAdBlockRecords(for container: TabContainer) -> [FilterListRecord] {
        let enabledListIDs = Set(settings.privacySettings(for: container.id).adBlock.enabledListIDs)
        return settings.adBlockFilterLists.filter { enabledListIDs.contains($0.id) }
    }

    private func filterListStatusText(for record: FilterListRecord) -> String {
        switch record.status {
        case .idle:
            return "Not downloaded yet"
        case .updating:
            return "Updating list and compiling WebKit rules"
        case .ready:
            return if let coverage = record.coverage {
                "\(coverage.convertedRuleCount) converted, \(coverage.skippedRuleCount) skipped"
            } else {
                "Compiled and ready"
            }
        case .failed:
            return record.lastErrorMessage ?? "The list could not be refreshed"
        }
    }

    private func adBlockSummary(for container: TabContainer) -> (
        statusText: String,
        lastUpdatedText: String?,
        coverageText: String?,
        isUpdating: Bool,
        hasFailures: Bool
    ) {
        let privacySettings = settings.privacySettings(for: container.id)
        guard privacySettings.adBlock.enabled else {
            return ("Ad blocking is off.", nil, nil, false, false)
        }

        let enabledRecords = enabledAdBlockRecords(for: container)
        guard !enabledRecords.isEmpty else {
            return ("Select at least one filter list to block ads.", nil, nil, false, false)
        }

        let isUpdating = enabledRecords.contains { $0.status == .updating }
        let failedRecords = enabledRecords.filter { $0.status == .failed }
        let lastUpdated = enabledRecords.compactMap(\.lastSuccessfulRefreshAt).max()
        let totalConverted = enabledRecords.compactMap(\.coverage).reduce(0) { $0 + $1.convertedRuleCount }
        let totalSkipped = enabledRecords.compactMap(\.coverage).reduce(0) { $0 + $1.skippedRuleCount }

        let statusText = if isUpdating {
            "Updating filter lists and recompiling WebKit rule sets."
        } else if let failedRecord = failedRecords.first {
            "\(failedRecord.name) needs attention."
        } else {
            "Ready in \(enabledRecords.count) enabled list\(enabledRecords.count == 1 ? "" : "s")."
        }

        let lastUpdatedText = lastUpdated?.formatted(date: .abbreviated, time: .shortened)
        let coverageText = totalConverted == 0 && totalSkipped == 0
            ? nil
            : "\(totalConverted) converted rules, \(totalSkipped) skipped"

        return (statusText, lastUpdatedText, coverageText, isUpdating, !failedRecords.isEmpty)
    }
}

// swiftlint:enable type_body_length large_tuple
