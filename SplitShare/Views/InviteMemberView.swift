import SwiftUI

struct InviteMemberView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var groupStore: GroupStore
    @EnvironmentObject private var peerService: MultipeerService

    let group: ExpenseGroup

    @State private var showingScanner = false
    @State private var showingMyCode = false
    @State private var errorMessage: String?
    @State private var successName: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Nur per QR-Code. Wer den Code nicht gescannt hat, sieht diese Gruppe nicht — auch nicht in Bluetooth-Reichweite.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button {
                        showingScanner = true
                    } label: {
                        Label("QR-Code der anderen Person scannen", systemImage: "qrcode.viewfinder")
                    }

                    Button {
                        showingMyCode = true
                    } label: {
                        Label("Eigenen Code zeigen", systemImage: "qrcode")
                    }
                }

                if let successName {
                    Section {
                        Label("\(successName) ist eingeladen. Ist Bluetooth verbunden, öffnet sich die Gruppe auf dem anderen iPhone.", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Text("Die andere Person zeigt ihren Code unter Profil. Nach dem Scannen öffnet sich die Gruppe bei ihr automatisch — sobald ihr per Bluetooth verbunden seid.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Einladen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
            .sheet(isPresented: $showingScanner) {
                QRScannerView { raw in
                    handleScan(raw)
                }
            }
            .sheet(isPresented: $showingMyCode) {
                NavigationStack {
                    IdentityQRCodeView(payload: peerService.identityPayload)
                        .navigationTitle("Dein Code")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Fertig") { showingMyCode = false }
                            }
                        }
                }
            }
        }
    }

    private func handleScan(_ raw: String) {
        guard let payload = QRIdentity.decode(raw) else {
            errorMessage = "Das ist kein SplitShare-Code."
            successName = nil
            return
        }
        if let error = groupStore.inviteByQR(payload, to: group.id) {
            errorMessage = error
            successName = nil
        } else {
            errorMessage = nil
            successName = payload.displayName
        }
    }
}

#Preview {
    InviteMemberView(
        group: ExpenseGroup(name: "Test", members: [GroupMember(displayName: "Anna")])
    )
    .environmentObject(GroupStore())
    .environmentObject(MultipeerService())
}
