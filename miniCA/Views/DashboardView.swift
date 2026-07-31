import SwiftData
import SwiftUI

struct DashboardView: View {
    @Query(sort: \CertificateAuthority.createdAt) private var cas: [CertificateAuthority]
    @Query(sort: \ManagedCertificate.notAfter) private var certificates: [ManagedCertificate]
    @Query private var servers: [LinuxServer]
    @Query(sort: \Deployment.createdAt, order: .reverse) private var deployments: [Deployment]
    @AppStorage(SettingsKeys.expiryWarningDays) private var warningDays = 30

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                statTiles

                if !expiringItems.isEmpty {
                    section("Expiring soon", systemImage: "exclamationmark.triangle") {
                        ForEach(expiringItems, id: \.name) { item in
                            HStack {
                                Image(systemName: item.isCA ? "checkmark.seal" : "doc.badge.ellipsis")
                                    .foregroundStyle(.secondary)
                                Text(item.name)
                                Text(item.commonName).foregroundStyle(.secondary)
                                Spacer()
                                ExpiryBadge(level: item.level, days: item.days)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                section("Recent Deployments", systemImage: "arrow.up.circle") {
                    if deployments.isEmpty {
                        Text("No deployments yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(deployments.prefix(8)) { deployment in
                            DeploymentRow(deployment: deployment)
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Dashboard")
        .overlay {
            if cas.isEmpty {
                ContentUnavailableView {
                    Label("Welcome to miniCA", systemImage: "checkmark.seal")
                } description: {
                    Text("Create a Root CA to get started.")
                }
            }
        }
    }

    private var statTiles: some View {
        HStack(spacing: 16) {
            StatTile(title: "CAs", value: cas.count, systemImage: "checkmark.seal", tint: .teal)
            StatTile(
                title: "Certificates", value: certificates.count,
                systemImage: "doc.badge.ellipsis", tint: .blue)
            StatTile(title: "Servers", value: servers.count, systemImage: "server.rack", tint: .indigo)
            StatTile(
                title: "Expiring", value: expiringItems.count,
                systemImage: "exclamationmark.triangle", tint: .orange)
        }
    }

    private struct ExpiringItem {
        let name: String
        let commonName: String
        let days: Int
        let level: ExpiryLevel
        let isCA: Bool
    }

    private var expiringItems: [ExpiringItem] {
        let caItems = cas
            .filter { $0.daysUntilExpiry <= warningDays }
            .map {
                ExpiringItem(
                    name: $0.name, commonName: $0.commonName,
                    days: $0.daysUntilExpiry,
                    level: .forDays($0.daysUntilExpiry, warningDays: warningDays), isCA: true)
            }
        let certItems = certificates
            .filter { $0.status == .active && $0.daysUntilExpiry <= warningDays }
            .map {
                ExpiringItem(
                    name: $0.name, commonName: $0.commonName,
                    days: $0.daysUntilExpiry,
                    level: .forDays($0.daysUntilExpiry, warningDays: warningDays), isCA: false)
            }
        return (caItems + certItems).sorted { $0.days < $1.days }
    }

    private func section(
        _ title: String, systemImage: String, @ViewBuilder content: () -> some View
    ) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        } label: {
            Label(title, systemImage: systemImage)
                .font(.headline)
        }
    }
}

private struct StatTile: View {
    let title: String
    let value: Int
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 12))
    }
}

struct DeploymentRow: View {
    let deployment: Deployment
    @Query private var certificates: [ManagedCertificate]
    @Query private var servers: [LinuxServer]

    private var certName: String {
        certificates.first { $0.id == deployment.certificateID }?.name ?? "Unknown certificate"
    }

    private var serverName: String {
        servers.first { $0.id == deployment.serverID }?.name ?? "Unknown server"
    }

    var body: some View {
        HStack {
            Image(systemName: statusIcon)
                .foregroundStyle(statusColor)
            VStack(alignment: .leading) {
                Text("\(certName) → \(serverName)")
                Text(deployment.remoteCertPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let deployedAt = deployment.deployedAt {
                Text(deployedAt, format: .dateTime.day().month().year())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let days = deployment.daysUntilRemoteExpiry {
                ExpiryBadge(level: .forDays(days), days: days)
            }
        }
        .padding(.vertical, 2)
    }

    private var statusIcon: String {
        switch deployment.lastScanStatus {
        case .ok: "checkmark.circle.fill"
        case .failed: "xmark.circle.fill"
        case .unknown: deployment.deployedAt != nil ? "arrow.up.circle.fill" : "circle.dashed"
        }
    }

    private var statusColor: Color {
        switch deployment.lastScanStatus {
        case .ok: .green
        case .failed: .red
        case .unknown: .secondary
        }
    }
}
