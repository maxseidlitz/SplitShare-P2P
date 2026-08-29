import SwiftUI

struct GroupsListView: View {
    @EnvironmentObject private var groupStore: GroupStore
    @State private var showingCreateGroup = false

    var body: some View {
        NavigationStack {
            Group {
                if groupStore.groups.isEmpty {
                    ContentUnavailableView {
                        VStack(spacing: 16) {
                            AppLogo(size: 88, cornerRadius: 22)
                            Text("Keine Gruppen")
                                .font(.title2.weight(.semibold))
                        }
                    } description: {
                        Text("Erstelle eine Gruppe und lade Freunde per QR-Code ein.")
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
                    .onDelete { offsets in
                        let ids = offsets.map { groupStore.groups[$0].id }
                        for id in ids {
                            groupStore.deleteGroup(id)
                        }
                    }
                }
            }
            .navigationTitle("SplitShare")
            .navigationDestination(for: UUID.self) { groupId in
                if let group = groupStore.group(with: groupId) {
                    GroupDetailView(group: group)
                } else {
                    ContentUnavailableView("Gruppe nicht gefunden", systemImage: "folder")
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    AppLogo(size: 28, cornerRadius: 7)
                }
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
