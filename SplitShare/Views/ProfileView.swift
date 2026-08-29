import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var peerService: MultipeerService
    @EnvironmentObject private var groupStore: GroupStore
    @State private var displayName = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 10) {
                        AppLogo(size: 88, cornerRadius: 22)
                        Text("SplitShare")
                            .font(.title2.weight(.semibold))
                        Text("Gruppen teilen, ohne Internet")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                Section("Dein QR-Code") {
                    IdentityQRCodeView(payload: peerService.identityPayload)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                }

                Section("Dein Profil") {
                    TextField("Anzeigename", text: $displayName)
                        .textInputAutocapitalization(.words)
                    Button("Speichern") {
                        peerService.updateDisplayName(displayName)
                        groupStore.applyOwnDisplayName()
                    }
                    .disabled(displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Section("Info") {
                    LabeledContent("Geräte-ID") {
                        Text(deviceId)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    LabeledContent("Sync") {
                        Text("Nur eingeladene Mitglieder · QR + Bluetooth")
                    }
                }

                Section {
                    Text("SplitShare funktioniert ohne Internet. Gruppen siehst du erst, nachdem dich jemand per QR-Code eingeladen hat — nicht schon durch Bluetooth-Nähe.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Profil")
            .onAppear {
                displayName = peerService.profile.displayName
            }
        }
    }

    private var deviceId: String {
        UserDefaults.standard.string(forKey: "splitshare.deviceId") ?? "—"
    }
}

#Preview {
    ProfileView()
        .environmentObject(MultipeerService())
        .environmentObject(GroupStore())
}
