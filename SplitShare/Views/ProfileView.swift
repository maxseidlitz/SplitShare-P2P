import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var peerService: MultipeerService
    @State private var displayName = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Dein Profil") {
                    TextField("Anzeigename", text: $displayName)
                        .textInputAutocapitalization(.words)
                    Button("Speichern") {
                        peerService.updateDisplayName(displayName)
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
                        Text("Offline · Bluetooth P2P")
                    }
                }

                Section {
                    Text("SplitShare funktioniert komplett ohne Internet. Gruppen und Ausgaben werden direkt zwischen iPhones synchronisiert.")
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
}
