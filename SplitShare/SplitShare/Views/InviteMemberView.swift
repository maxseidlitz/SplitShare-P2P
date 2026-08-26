import SwiftUI
import MultipeerConnectivity

struct InviteMemberView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var groupStore: GroupStore
    @EnvironmentObject private var peerService: MultipeerService

    let group: ExpenseGroup

    @State private var manualName = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Sende eine Gruppeneinladung an verbundene Geräte. Der Empfänger erhält die Gruppe automatisch per Bluetooth.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section("Verbundene Geräte") {
                    if peerService.connectedPeers.isEmpty {
                        Text("Keine Geräte verbunden. Öffne den Tab „In der Nähe“ und halte zwei iPhones nah beieinander.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(peerService.connectedPeers, id: \.displayName) { peer in
                            Button {
                                invite(peer: peer)
                            } label: {
                                Label("Einladen: \(peer.displayName)", systemImage: "paperplane.fill")
                            }
                        }
                    }
                }

                Section("Manuell hinzufügen") {
                    TextField("Name", text: $manualName)
                    Button("Als Mitglied hinzufügen") {
                        let member = GroupMember(displayName: manualName.trimmingCharacters(in: .whitespacesAndNewlines))
                        groupStore.inviteMember(to: group.id, member: member)
                        manualName = ""
                        dismiss()
                    }
                    .disabled(manualName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } footer: {
                    Text("Manuelle Mitglieder synchronisieren Ausgaben nicht automatisch – nutze Bluetooth-Einladungen für Live-Sync.")
                }
            }
            .navigationTitle("Einladen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
    }

    private func invite(peer: MCPeerID) {
        groupStore.sendGroupInvite(group, to: peer)
        let member = GroupMember(displayName: peer.displayName, peerDeviceId: nil)
        groupStore.inviteMember(to: group.id, member: member)
        dismiss()
    }
}

#Preview {
    InviteMemberView(
        group: ExpenseGroup(name: "Test", members: [GroupMember(displayName: "Anna")])
    )
    .environmentObject(GroupStore())
    .environmentObject(MultipeerService())
}
