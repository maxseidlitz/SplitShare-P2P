import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var peerService: MultipeerService

    var body: some View {
        TabView {
            GroupsListView()
                .tabItem {
                    Label("Gruppen", systemImage: "person.3.fill")
                }

            NearbyPeersView()
                .tabItem {
                    Label("In der Nähe", systemImage: "dot.radiowaves.left.and.right")
                }

            ProfileView()
                .tabItem {
                    Label("Profil", systemImage: "person.circle.fill")
                }
        }
        .tint(.teal)
    }
}

#Preview {
    ContentView()
        .environmentObject(MultipeerService())
        .environmentObject(GroupStore())
}
