import SwiftUI

struct GroupDetailView: View {
    @EnvironmentObject private var groupStore: GroupStore
    @EnvironmentObject private var peerService: MultipeerService

    let group: ExpenseGroup

    @State private var showingAddExpense = false
    @State private var showingInvite = false
    @State private var expenseToEdit: Expense?
    @State private var selectedTab = 0

    private var currentGroup: ExpenseGroup {
        groupStore.group(with: group.id) ?? group
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Ansicht", selection: $selectedTab) {
                Text("Ausgaben").tag(0)
                Text("Salden").tag(1)
                Text("Mitglieder").tag(2)
            }
            .pickerStyle(.segmented)
            .padding()

            switch selectedTab {
            case 0:
                expensesTab
            case 1:
                BalancesView(group: currentGroup)
            default:
                membersTab
            }
        }
        .navigationTitle(currentGroup.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showingAddExpense = true
                    } label: {
                        Label("Ausgabe hinzufügen", systemImage: "plus")
                    }

                    Button {
                        showingInvite = true
                    } label: {
                        Label("Mitglied einladen", systemImage: "person.badge.plus")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingAddExpense) {
            AddExpenseView(group: currentGroup)
        }
        .sheet(item: $expenseToEdit) { expense in
            AddExpenseView(group: currentGroup, expense: expense)
        }
        .sheet(isPresented: $showingInvite) {
            InviteMemberView(group: currentGroup)
        }
    }

    private var expensesTab: some View {
        Group {
            if currentGroup.expenses.isEmpty {
                ContentUnavailableView {
                    Label("Keine Ausgaben", systemImage: "cart")
                } description: {
                    Text("Füge die erste Ausgabe hinzu, z. B. Restaurant oder Einkauf.")
                }
            } else {
                List {
                    ForEach(currentGroup.expenses) { expense in
                        Button {
                            expenseToEdit = expense
                        } label: {
                            ExpenseRowView(expense: expense, members: currentGroup.members)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                groupStore.deleteExpense(groupId: currentGroup.id, expenseId: expense.id)
                            } label: {
                                Label("Löschen", systemImage: "trash")
                            }
                            Button {
                                expenseToEdit = expense
                            } label: {
                                Label("Bearbeiten", systemImage: "pencil")
                            }
                            .tint(.teal)
                        }
                        .contextMenu {
                            Button {
                                expenseToEdit = expense
                            } label: {
                                Label("Bearbeiten", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                groupStore.deleteExpense(groupId: currentGroup.id, expenseId: expense.id)
                            } label: {
                                Label("Löschen", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
    }

    private var membersTab: some View {
        List(currentGroup.members) { member in
            HStack {
                Image(systemName: "person.circle.fill")
                    .foregroundStyle(.teal)
                    .font(.title2)
                VStack(alignment: .leading) {
                    Text(member.displayName)
                    if member.id == peerService.profile.id {
                        Text("Du")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

private struct ExpenseRowView: View {
    let expense: Expense
    let members: [GroupMember]

    private var payerName: String {
        members.first { $0.id == expense.payerId }?.displayName ?? "Unbekannt"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(expense.title)
                    .font(.headline)
                Spacer()
                Text(expense.amount.formatted(.currency(code: Locale.current.currency?.identifier ?? "EUR")))
                    .font(.headline)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            Text("Bezahlt von \(payerName)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(expense.date.formatted(date: .abbreviated, time: .omitted))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        GroupDetailView(
            group: ExpenseGroup(
                name: "Urlaub",
                members: [GroupMember(displayName: "Anna")],
                expenses: [Expense(title: "Pizza", amount: 42, payerId: UUID(), splits: [])]
            )
        )
    }
    .environmentObject(GroupStore())
    .environmentObject(MultipeerService())
}
