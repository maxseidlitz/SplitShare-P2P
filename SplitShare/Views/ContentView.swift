import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var groupStore: GroupStore
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            GroupsListView()
                .tabItem {
                    Label("Gruppen", systemImage: "person.3.fill")
                }
                .tag(0)

            NearbyPeersView()
                .tabItem {
                    Label("In der Nähe", systemImage: "dot.radiowaves.left.and.right")
                }
                .tag(1)

            ProfileView()
                .tabItem {
                    Label("Profil", systemImage: "person.circle.fill")
                }
                .tag(2)
        }
        .tint(.teal)
        .onChange(of: groupStore.pendingOpenGroupId) { _, newValue in
            if newValue != nil {
                selectedTab = 0
            }
        }
        .alert(
            groupStore.presentedNotice?.title ?? "",
            isPresented: noticePresented
        ) {
            Button("OK") {
                groupStore.consumePresentedNotice()
            }
        } message: {
            Text(groupStore.presentedNotice?.message ?? "")
        }
    }

    private var noticePresented: Binding<Bool> {
        Binding(
            get: { groupStore.presentedNotice != nil },
            set: { isPresented in
                if !isPresented {
                    groupStore.consumePresentedNotice()
                }
            }
        )
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
