import SwiftUI

struct GroupsListView: View {
    @EnvironmentObject private var groupStore: GroupStore
    @State private var showingCreateGroup = false

    var body: some View {
        NavigationStack {
            Group {
                if groupStore.groups.isEmpty {
                    ContentUnavailableView {
                        Label("Keine Gruppen", systemImage: "tray")
                    } description: {
                        Text("Erstelle eine Gruppe und lade Freunde per Bluetooth ein.")
                    } actions: {
                        Button("Gruppe erstellen") {
                            showingCreateGroup = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    List(groupStore.groups) { group in
                        NavigationLink(value: group.id) {
                            GroupRowView(group: group)
                        }
                    }
                }
            }
            .navigationTitle("SplitShare")
            .navigationDestination(for: UUID.self) { groupId in
                if let group = groupStore.group(with: groupId) {
                    GroupDetailView(group: group)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingCreateGroup = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                }
            }
            .sheet(isPresented: $showingCreateGroup) {
                CreateGroupView()
            }
        }
    }
}

private struct GroupRowView: View {
    let group: ExpenseGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(group.name)
                .font(.headline)
            HStack(spacing: 12) {
                Label("\(group.members.count)", systemImage: "person.2")
                Label("\(group.expenses.count)", systemImage: "eurosign.circle")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    GroupsListView()
        .environmentObject(GroupStore())
}
