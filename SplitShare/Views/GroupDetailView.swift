import SwiftUI

struct GroupDetailView: View {
    @EnvironmentObject private var groupStore: GroupStore
    @EnvironmentObject private var peerService: MultipeerService
    @Environment(\.dismiss) private var dismiss

    let group: ExpenseGroup

    @State private var showingAddExpense = false
    @State private var showingInvite = false
    @State private var expenseToEdit: Expense?
    @State private var selectedTab = 0
    @State private var alertMessage: String?
    @State private var showingLeaveConfirm = false
    @State private var showingCreditWarning = false
    @State private var showingAdminPicker = false
    @State private var showingDeleteConfirm = false
    @State private var showingLastMemberChoice = false
    @State private var showingArchiveDelete = false
    @State private var selectedNewAdminId: UUID?

    private var currentGroup: ExpenseGroup {
        groupStore.group(with: group.id) ?? group
    }

    private var isArchived: Bool {
        groupStore.isArchived(currentGroup.id)
    }

    private var myId: UUID {
        peerService.profile.id
    }

    private var isAdmin: Bool {
        currentGroup.isAdmin(myId)
    }

    private var otherActiveMembers: [GroupMember] {
        currentGroup.activeMembers.filter { $0.id != myId }
    }

    var body: some View {
        VStack(spacing: 0) {
            if isArchived {
                archiveBanner
            }

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
                BalancesView(group: currentGroup, isReadOnly: isArchived)
            default:
                membersTab
            }
        }
        .navigationTitle(currentGroup.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if !isArchived {
                    Button {
                        showingAddExpense = true
                    } label: {
                        Image(systemName: "plus.circle")
                    }
                    .accessibilityLabel("Ausgabe hinzufügen")
                }

                Menu {
                    if !isArchived {
                        Button {
                            showingInvite = true
                        } label: {
                            Label("Mitglied einladen", systemImage: "person.badge.plus")
                        }

                        Divider()

                        Button(role: .destructive) {
                            startLeaveFlow()
                        } label: {
                            Label("Gruppe verlassen", systemImage: "rectangle.portrait.and.arrow.right")
                        }

                        if isAdmin {
                            Button(role: .destructive) {
                                startDeleteFlow()
                            } label: {
                                Label("Gruppe löschen", systemImage: "trash")
                            }
                        }
                    } else {
                        Button(role: .destructive) {
                            showingArchiveDelete = true
                        } label: {
                            Label("Aus Archiv entfernen", systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Gruppenaktionen")
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
        .alert("Hinweis", isPresented: alertPresented) {
            Button("OK", role: .cancel) { alertMessage = nil }
        } message: {
            Text(alertMessage ?? "")
        }
        .confirmationDialog("Gruppe verlassen?", isPresented: $showingLeaveConfirm, titleVisibility: .visible) {
            Button("Verlassen", role: .destructive) {
                performLeave()
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Die Gruppe bleibt im Archiv. Die anderen Mitglieder sehen, dass du gegangen bist.")
        }
        .confirmationDialog("Dir stehen noch Geld zu", isPresented: $showingCreditWarning, titleVisibility: .visible) {
            Button("Trotzdem verlassen", role: .destructive) {
                continueLeaveAfterCreditWarning()
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            let amount = BalanceCalculator.netBalance(for: myId, in: currentGroup)
            Text("Dir stehen noch \(formatted(amount)) zu. Die anderen sehen das als offene Schuld gegenüber dir.")
        }
        .confirmationDialog("Wer wird Admin?", isPresented: $showingAdminPicker, titleVisibility: .visible) {
            ForEach(otherActiveMembers) { member in
                Button(member.displayName) {
                    selectedNewAdminId = member.id
                    afterAdminPicked()
                }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Du bist Admin. Wähle, wer die Gruppe weiterführt.")
        }
        .confirmationDialog("Gruppe für alle löschen?", isPresented: $showingDeleteConfirm, titleVisibility: .visible) {
            Button("Löschen", role: .destructive) {
                performDelete()
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Die Gruppe verschwindet bei allen, sobald sie synchronisieren.")
        }
        .confirmationDialog("Du bist das letzte Mitglied", isPresented: $showingLastMemberChoice, titleVisibility: .visible) {
            Button("In Archiv verschieben") {
                performLeave()
            }
            Button("Gruppe endgültig löschen", role: .destructive) {
                startDeleteFlow()
            }
            Button("Abbrechen", role: .cancel) {}
        }
        .confirmationDialog("Aus Archiv entfernen?", isPresented: $showingArchiveDelete, titleVisibility: .visible) {
            Button("Entfernen", role: .destructive) {
                groupStore.removeFromArchive(currentGroup.id)
                dismiss()
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Die Gruppe wird nur auf diesem iPhone gelöscht.")
        }
    }

    private var archiveBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "archivebox")
            Text("Du hast diese Gruppe verlassen. Sie ist nur noch im Archiv.")
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.top, 8)
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
                            if !isArchived {
                                expenseToEdit = expense
                            }
                        } label: {
                            ExpenseRowView(expense: expense, members: currentGroup.members, myId: myId)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            if !isArchived {
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
                        }
                        .contextMenu {
                            if !isArchived {
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
    }

    private var membersTab: some View {
        List {
            Section("Aktiv") {
                ForEach(currentGroup.activeMembers) { member in
                    memberRow(member, isFormer: false)
                }
            }
            if !currentGroup.formerMembers.isEmpty {
                Section("Ausgetreten") {
                    ForEach(currentGroup.formerMembers) { member in
                        memberRow(member, isFormer: true)
                    }
                }
            }
        }
    }

    private func memberRow(_ member: GroupMember, isFormer: Bool) -> some View {
        HStack {
            Image(systemName: isFormer ? "person.crop.circle.badge.minus" : "person.circle.fill")
                .foregroundStyle(isFormer ? Color.secondary : Color.teal)
                .font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text(member.displayName)
                HStack(spacing: 8) {
                    if member.id == myId {
                        Text("Du")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if currentGroup.isAdmin(member.id) && !isFormer {
                        Text("Admin")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.teal)
                    }
                }
            }
        }
    }

    private func startLeaveFlow() {
        if let reason = groupStore.leaveBlockReason(for: currentGroup.id) {
            alertMessage = reason
            return
        }
        if otherActiveMembers.isEmpty {
            showingLastMemberChoice = true
            return
        }
        if isAdmin {
            showingAdminPicker = true
            return
        }
        if BalanceCalculator.isOwedMoney(myId, in: currentGroup) {
            showingCreditWarning = true
            return
        }
        showingLeaveConfirm = true
    }

    private func afterAdminPicked() {
        if BalanceCalculator.isOwedMoney(myId, in: currentGroup) {
            showingCreditWarning = true
        } else {
            showingLeaveConfirm = true
        }
    }

    private func continueLeaveAfterCreditWarning() {
        performLeave()
    }

    private func performLeave() {
        if let reason = groupStore.leaveGroup(currentGroup.id, newAdminId: selectedNewAdminId) {
            alertMessage = reason
            return
        }
        dismiss()
    }

    private func startDeleteFlow() {
        if let reason = groupStore.deleteBlockReason(for: currentGroup.id) {
            alertMessage = reason
            return
        }
        showingDeleteConfirm = true
    }

    private func performDelete() {
        if let reason = groupStore.deleteGroupForEveryone(currentGroup.id) {
            alertMessage = reason
            return
        }
        dismiss()
    }

    private var alertPresented: Binding<Bool> {
        Binding(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )
    }

    private func formatted(_ value: Decimal) -> String {
        value.formatted(.currency(code: Locale.current.currency?.identifier ?? "EUR"))
    }
}

private struct ExpenseRowView: View {
    let expense: Expense
    let members: [GroupMember]
    let myId: UUID

    private var payerName: String {
        members.first { $0.id == expense.payerId }?.displayName ?? "Unbekannt"
    }

    private var myShare: Decimal? {
        expense.splits.first { $0.memberId == myId }?.amount
    }

    private var shareLabel: (text: String, color: Color)? {
        guard let share = myShare, share > 0 else { return nil }
        let amount = share.formatted(.currency(code: Locale.current.currency?.identifier ?? "EUR"))
        if expense.payerId == myId {
            return ("Dein Anteil \(amount)", .secondary)
        }
        return ("Du schuldest \(amount)", .red)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(expense.title)
                    .font(.headline)
                Text("Bezahlt von \(payerName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(expense.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 8)
            HStack(alignment: .top, spacing: 6) {
                VStack(alignment: .trailing, spacing: 4) {
                    Text(expense.amount.formatted(.currency(code: Locale.current.currency?.identifier ?? "EUR")))
                        .font(.headline)
                    if let shareLabel {
                        Text(shareLabel.text)
                            .font(.caption)
                            .foregroundStyle(shareLabel.color)
                            .multilineTextAlignment(.trailing)
                    }
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 4)
            }
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
