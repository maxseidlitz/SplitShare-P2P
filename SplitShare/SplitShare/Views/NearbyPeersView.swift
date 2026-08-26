import SwiftUI
import MultipeerConnectivity

struct NearbyPeersView: View {
    @EnvironmentObject private var peerService: MultipeerService
    @EnvironmentObject private var groupStore: GroupStore

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Circle()
                            .fill(peerService.isAdvertising && peerService.isBrowsing ? Color.green : Color.orange)
                            .frame(width: 10, height: 10)
                        Text(peerService.isAdvertising && peerService.isBrowsing ? "Bluetooth aktiv" : "Bluetooth inaktiv")
                    }
                    if peerService.connectedPeers.isEmpty {
                        Text("Keine verbundenen Geräte")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(peerService.connectedPeers, id: \.displayName) { peer in
                            Label(peer.displayName, systemImage: "link.circle.fill")
                        }
                    }
                } header: {
                    Text("Verbunden")
                } footer: {
                    Text("Geräte in der Nähe verbinden sich automatisch per Bluetooth/WLAN-Direct. Kein Internet nötig.")
                }

                Section("In der Nähe gefunden") {
                    if peerService.discoveredPeers.isEmpty {
                        ContentUnavailableView {
                            Label("Suche läuft…", systemImage: "antenna.radiowaves.left.and.right")
                        } description: {
                            Text("Öffne SplitShare auf einem anderen iPhone in der Nähe.")
                        }
                        .listRowBackground(Color.clear)
                    } else {
                        ForEach(peerService.discoveredPeers, id: \.displayName) { peer in
                            PeerRowView(peer: peer)
                        }
                    }
                }

                if let error = peerService.lastError {
                    Section("Hinweis") {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Peer-to-Peer")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Sync") {
                        groupStore.requestSyncFromConnectedPeers()
                    }
                    .disabled(peerService.connectedPeers.isEmpty)
                }
            }
        }
    }
}

private struct PeerRowView: View {
    @EnvironmentObject private var peerService: MultipeerService

    let peer: MCPeerID

    private var isConnected: Bool {
        peerService.connectedPeers.contains { $0.displayName == peer.displayName }
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(peer.displayName)
                    .font(.headline)
                Text(isConnected ? "Verbunden" : "Verbindung wird aufgebaut…")
                    .font(.caption)
                    .foregroundStyle(isConnected ? .green : .secondary)
            }
            Spacer()
            if isConnected {
                Button("Trennen") {
                    peerService.disconnect(from: peer)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                Button("Verbinden") {
                    peerService.invite(peer)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
    }
}

#Preview {
    NearbyPeersView()
        .environmentObject(MultipeerService())
        .environmentObject(GroupStore())
}
