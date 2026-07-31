import SwiftData
import SwiftUI

struct RootSplitView: View {
    @State private var selection: SidebarItem? = .dashboard

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $selection) { item in
                Label(item.title, systemImage: item.systemImage)
                    .tag(item)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 230)
        } detail: {
            switch selection ?? .dashboard {
            case .dashboard: DashboardView()
            case .cas: CAListView()
            case .certificates: CertificateListView()
            case .servers: ServerListView()
            }
        }
        .frame(minWidth: 860, minHeight: 540)
    }
}

// MARK: - Shared UI bits

struct RoleBadge: View {
    let role: CertRole

    var body: some View {
        Label(role.displayName, systemImage: role.systemImage)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .badgeBackground(tint: role == .server ? .blue : .purple)
    }
}

struct ExpiryBadge: View {
    let level: ExpiryLevel
    let days: Int

    var body: some View {
        Text(days < 0 ? "Expired" : "\(days) days")
            .font(.caption.monospacedDigit())
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .badgeBackground(tint: level.color)
    }
}

/// Saves text content via NSSavePanel (app is not sandboxed).
@MainActor
func saveToFile(defaultName: String, contents: String) {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = defaultName
    panel.canCreateDirectories = true
    guard panel.runModal() == .OK, let url = panel.url else { return }
    try? contents.write(to: url, atomically: true, encoding: .utf8)
}

@MainActor
func copyToPasteboard(_ string: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(string, forType: .string)
}
