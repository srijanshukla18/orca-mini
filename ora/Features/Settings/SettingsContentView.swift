import AppKit
import SwiftUI

enum SettingsTab: String, Hashable, CaseIterable {
    case general
    case privacy
    case shortcuts
    case searchEngines

    var title: String {
        switch self {
        case .general: return "General"
        case .privacy: return "Privacy"
        case .shortcuts: return "Shortcuts"
        case .searchEngines: return "Search"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .privacy: return "hand.raised"
        case .shortcuts: return "command"
        case .searchEngines: return "magnifyingglass"
        }
    }

    var subtitle: String {
        switch self {
        case .general:
            return "Browser defaults and app behavior."
        case .privacy:
            return "Privacy protections, content blocking, and browser data."
        case .shortcuts:
            return "Keyboard shortcuts and command mappings."
        case .searchEngines:
            return "Default search providers, AI engines, and custom shortcuts."
        }
    }
}

struct SettingsWindowRoot: View {
    var body: some View {
        SettingsContentView()
            .environmentObject(ToastManager.shared)
    }
}

struct SettingsContentView: View {
    static let selectedTabDefaultsKey = "settings.selectedTab"

    @AppStorage(Self.selectedTabDefaultsKey) private var selectionRawValue: String = SettingsTab.general.rawValue

    private var selection: Binding<SettingsTab> {
        Binding(
            get: { SettingsTab(rawValue: selectionRawValue) ?? .general },
            set: { selectionRawValue = $0.rawValue }
        )
    }

    private var selectedTab: SettingsTab {
        SettingsTab(rawValue: selectionRawValue) ?? .general
    }

    var body: some View {
        NavigationSplitView {
            List(SettingsTab.allCases, id: \.self, selection: selection) { tab in
                Label(tab.title, systemImage: tab.symbol)
                    .tag(tab)
            }
            .navigationSplitViewColumnWidth(200)
            .padding(.top, 8)
        } detail: {
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .navigationTitle(selectedTab.title)
                .navigationSubtitle(selectedTab.subtitle)
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selectedTab {
        case .general:
            GeneralSettingsView()
        case .privacy:
            PrivacySettingsView()
        case .shortcuts:
            ShortcutsSettingsView()
        case .searchEngines:
            SearchEngineSettingsView()
        }
    }
}
