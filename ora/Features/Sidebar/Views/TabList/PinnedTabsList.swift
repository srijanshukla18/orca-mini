import SwiftUI

struct PinnedTabsList: View {
    let tabs: [Tab]
    @Binding var draggedItem: UUID?
    let onDrag: (UUID) -> NSItemProvider
    let onSelect: (Tab) -> Void
    let onPinToggle: (Tab) -> Void
    let onClose: (Tab) -> Void
    let onDuplicate: (Tab) -> Void
    @EnvironmentObject var tabManager: TabManager
    @Environment(\.theme) var theme

    var body: some View {
        VStack(spacing: 8) {
            Text("Pinned")
                .font(.callout)
                .foregroundColor(theme.mutedForeground)
                .padding(.top, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            if tabs.isEmpty {
                EmptyPinnedTabs()
            } else {
                ForEach(tabs) { tab in
                    TabItem(
                        tab: tab,
                        isSelected: tabManager.isActive(tab),
                        isDragging: draggedItem == tab.id,
                        onTap: { onSelect(tab) },
                        onPinToggle: { onPinToggle(tab) },
                        onClose: { onClose(tab) },
                        onDuplicate: { onDuplicate(tab) }
                    )
                    .onDrag { onDrag(tab.id) }
                    .onDrop(
                        of: [.text],
                        delegate: TabDropDelegate(
                            item: tab,
                            draggedItem: $draggedItem,
                            targetSection: .pinned
                        )
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onDrop(
            of: [.text],
            delegate: SectionDropDelegate(
                items: tabs,
                draggedItem: $draggedItem,
                targetSection: .pinned,
                tabManager: tabManager
            )
        )
    }
}
