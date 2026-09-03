import SwiftUI

struct ContentView: View {
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

struct AppLogo: View {
    var size: CGFloat = 84
    var cornerRadius: CGFloat = 20

    var body: some View {
        Image("Logo")
            .renderingMode(.original)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .accessibilityHidden(true)
    }
}

#Preview {
    ContentView()
        .environmentObject(MultipeerService())
        .environmentObject(GroupStore())
}
