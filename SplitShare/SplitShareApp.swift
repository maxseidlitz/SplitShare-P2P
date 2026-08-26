import SwiftUI

@main
struct SplitShareApp: App {
    @StateObject private var peerService = MultipeerService()
    @StateObject private var groupStore = GroupStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(peerService)
                .environmentObject(groupStore)
                .onAppear {
                    groupStore.attach(peerService: peerService)
                }
        }
    }
}
