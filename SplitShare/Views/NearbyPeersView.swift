import SwiftUI
import MultipeerConnectivity

struct NearbyPeersView: View {
    @EnvironmentObject private var peerService: MultipeerService
    @EnvironmentObject private var groupStore: GroupStore

    private var trustedDiscovered: [MCPeerID] {
        peerService.discoveredPeers.filter { peerService.isTrusted($0) }
    }

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
                        Text("Keine eingeladenen Geräte verbunden")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(peerService.connectedPeers, id: \.self) { peer in
                            Label(peer.displayName, systemImage: "link.circle.fill")
                        }
                    }
                } header: {
                    Text("Verbunden")
                } footer: {
                    Text("Es verbinden sich nur Personen, die du per QR-Code eingeladen hast. Unbekannte in der Nähe sehen deine Gruppen nicht.")
                }

                Section("Eingeladen in der Nähe") {
                    if trustedDiscovered.isEmpty {
                        ContentUnavailableView {
                            Label("Niemand bekannt in der Nähe", systemImage: "qrcode.viewfinder")
                        } description: {
                            Text("Lade Mitglieder in der Gruppe per QR-Code ein. Danach synchronisiert Bluetooth automatisch.")
                        }
                        .listRowBackground(Color.clear)
                    } else {
                        ForEach(trustedDiscovered, id: \.self) { peer in
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
        peerService.isConnected(peer)
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
