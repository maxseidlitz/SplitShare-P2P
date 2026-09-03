import SwiftUI

struct GroupsListView: View {
    @EnvironmentObject private var groupStore: GroupStore
    @State private var showingCreateGroup = false
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
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
                    List {
                        if !groupStore.activeGroups.isEmpty {
                            Section {
                                ForEach(groupStore.activeGroups) { group in
                                    NavigationLink(value: group.id) {
                                        GroupRowView(group: group)
                                    }
                                }
                            }
                        }

                        if !groupStore.archivedGroups.isEmpty {
                            Section("Archiv") {
                                ForEach(groupStore.archivedGroups) { group in
                                    NavigationLink(value: group.id) {
                                        GroupRowView(group: group, isArchived: true)
                                    }
                                }
                                .onDelete { offsets in
                                    let ids = offsets.map { groupStore.archivedGroups[$0].id }
                                    for id in ids {
                                        groupStore.removeFromArchive(id)
                                    }
                                }
                            }
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
            .onChange(of: groupStore.pendingOpenGroupId) { _, newValue in
                guard let newValue else { return }
                path.append(newValue)
                groupStore.consumePendingOpenGroup()
            }
        }
    }
}

private struct GroupRowView: View {
    let group: ExpenseGroup
    var isArchived = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(group.name)
                    .font(.headline)
                if isArchived {
                    Text("Verlassen")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.tertiary.opacity(0.4), in: Capsule())
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 12) {
                Label("\(group.activeMembers.count)", systemImage: "person.2")
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
