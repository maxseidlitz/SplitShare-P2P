import SwiftUI

struct AddExpenseView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var groupStore: GroupStore
    @EnvironmentObject private var peerService: MultipeerService

    let group: ExpenseGroup
    let existingExpense: Expense?

    @State private var title: String
    @State private var amountText: String
    @State private var payerId: UUID?
    @State private var splitMode: SplitMode
    @State private var selectedMemberIds: Set<UUID>
    @State private var exactAmounts: [UUID: String]
    @State private var percentages: [UUID: String]
    @State private var date: Date

    private var isEditing: Bool { existingExpense != nil }

    init(group: ExpenseGroup, expense: Expense? = nil) {
        self.group = group
        self.existingExpense = expense

        if let expense {
            _title = State(initialValue: expense.title)
            _amountText = State(initialValue: Self.decimalString(expense.amount))
            _payerId = State(initialValue: expense.payerId)
            _date = State(initialValue: expense.date)
            _selectedMemberIds = State(initialValue: Set(expense.splits.map(\.memberId)))
            _percentages = State(initialValue: [:])

            let equalShares = Self.splitsAreEqual(expense.splits)
            _splitMode = State(initialValue: equalShares ? .equal : .exact)
            _exactAmounts = State(initialValue: Dictionary(
                uniqueKeysWithValues: expense.splits.map { ($0.memberId, Self.decimalString($0.amount)) }
            ))
        } else {
            _title = State(initialValue: "")
            _amountText = State(initialValue: "")
            _payerId = State(initialValue: nil)
            _splitMode = State(initialValue: .equal)
            _selectedMemberIds = State(initialValue: [])
            _exactAmounts = State(initialValue: [:])
            _percentages = State(initialValue: [:])
            _date = State(initialValue: Date())
        }
    }

    private var amount: Decimal? {
        Decimal(string: amountText.replacingOccurrences(of: ",", with: "."))
    }

    private var canSave: Bool {
        guard let amount, amount > 0,
              !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let payerId,
              !selectedMemberIds.isEmpty else { return false }

        switch splitMode {
        case .equal:
            return true
        case .exact:
            let values = selectedMemberIds.compactMap { memberId -> Decimal? in
                exactAmounts[memberId].flatMap { Decimal(string: $0.replacingOccurrences(of: ",", with: ".")) }
            }
            return values.count == selectedMemberIds.count && values.reduce(0, +) == amount
        case .percentage:
            let values = selectedMemberIds.compactMap { memberId -> Decimal? in
                percentages[memberId].flatMap { Decimal(string: $0.replacingOccurrences(of: ",", with: ".")) }
            }
            return values.count == selectedMemberIds.count && values.reduce(0, +) == 100
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Beschreibung", text: $title)
                    TextField("Betrag", text: $amountText)
                        .keyboardType(.decimalPad)
                    DatePicker("Datum", selection: $date, displayedComponents: .date)
                }

                Section("Bezahlt von") {
                    Picker("Bezahlt von", selection: Binding(
                        get: { payerId ?? group.members.first?.id ?? UUID() },
                        set: { payerId = $0 }
                    )) {
                        ForEach(group.members) { member in
                            Text(member.displayName).tag(member.id)
                        }
                    }
                }

                Section {
                    Picker("Modus", selection: $splitMode) {
                        ForEach(SplitMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    if !selectedMemberIds.isEmpty {
                        Text(splitSummary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Button("Alle") {
                            selectedMemberIds = Set(group.members.map(\.id))
                        }
                        .disabled(selectedMemberIds.count == group.members.count)

                        Spacer()

                        Button("Keine") {
                            selectedMemberIds.removeAll()
                        }
                        .disabled(selectedMemberIds.isEmpty)
                    }
                    .buttonStyle(.borderless)

                    ForEach(group.members) { member in
                        Toggle(isOn: Binding(
                            get: { selectedMemberIds.contains(member.id) },
                            set: { isOn in
                                if isOn {
                                    selectedMemberIds.insert(member.id)
                                } else {
                                    selectedMemberIds.remove(member.id)
                                }
                            }
                        )) {
                            Text(member.displayName)
                        }

                        if selectedMemberIds.contains(member.id) {
                            switch splitMode {
                            case .equal:
                                if let amount {
                                    let share = BalanceCalculator.roundMoney(amount / Decimal(selectedMemberIds.count))
                                    Text(share.formatted(.currency(code: currencyCode)))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            case .exact:
                                TextField("Betrag", text: Binding(
                                    get: { exactAmounts[member.id, default: ""] },
                                    set: { exactAmounts[member.id] = $0 }
                                ))
                                .keyboardType(.decimalPad)
                            case .percentage:
                                HStack {
                                    TextField("Prozent", text: Binding(
                                        get: { percentages[member.id, default: ""] },
                                        set: { percentages[member.id] = $0 }
                                    ))
                                    .keyboardType(.decimalPad)
                                    Text("%")
                                }
                            }
                        }
                    }
                } header: {
                    Text("Aufteilen")
                }
            }
            .navigationTitle(isEditing ? "Ausgabe bearbeiten" : "Neue Ausgabe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") { save() }
                        .disabled(!canSave)
                }
            }
            .onAppear {
                guard !isEditing else { return }
                payerId = group.members.first(where: { $0.id == peerService.profile.id })?.id ?? group.members.first?.id
                selectedMemberIds = Set(group.members.map(\.id))
            }
        }
    }

    private var currencyCode: String {
        Locale.current.currency?.identifier ?? "EUR"
    }

    private var splitSummary: String {
        let count = selectedMemberIds.count
        let people = count == 1 ? "1 Person" : "\(count) Personen"
        if splitMode == .equal, let amount, count > 0 {
            let share = BalanceCalculator.roundMoney(amount / Decimal(count))
            return "\(people) · je \(share.formatted(.currency(code: currencyCode)))"
        }
        return people
    }

    private func save() {
        guard let amount, let payerId else { return }
        let memberIds = Array(selectedMemberIds)

        let splits: [ExpenseSplit]
        switch splitMode {
        case .equal:
            splits = BalanceCalculator.equalSplits(amount: amount, memberIds: memberIds)
        case .exact:
            splits = memberIds.compactMap { memberId in
                guard let text = exactAmounts[memberId],
                      let value = Decimal(string: text.replacingOccurrences(of: ",", with: ".")) else { return nil }
                return ExpenseSplit(memberId: memberId, amount: value)
            }
        case .percentage:
            let percentMap: [UUID: Decimal] = Dictionary(uniqueKeysWithValues: memberIds.compactMap { memberId in
                guard let text = percentages[memberId],
                      let value = Decimal(string: text.replacingOccurrences(of: ",", with: ".")) else { return nil }
                return (memberId, value)
            })
            splits = BalanceCalculator.percentageSplits(amount: amount, percentages: percentMap)
        }

        let now = Date()
        let expense = Expense(
            id: existingExpense?.id ?? UUID(),
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            amount: amount,
            payerId: payerId,
            splits: splits,
            date: date,
            createdAt: existingExpense?.createdAt ?? now,
            updatedAt: now
        )

        if isEditing {
            groupStore.updateExpense(in: group.id, expense: expense)
        } else {
            groupStore.addExpense(to: group.id, expense: expense)
        }
        dismiss()
    }

    private static func decimalString(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale.current
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: value as NSDecimalNumber) ?? "\(value)"
    }

    private static func splitsAreEqual(_ splits: [ExpenseSplit]) -> Bool {
        guard let first = splits.first else { return true }
        return splits.allSatisfy { $0.amount == first.amount }
    }
}

#Preview {
    AddExpenseView(
        group: ExpenseGroup(
            name: "Test",
            members: [
                GroupMember(id: UUID(), displayName: "Anna"),
                GroupMember(id: UUID(), displayName: "Ben")
            ]
        )
    )
    .environmentObject(GroupStore())
    .environmentObject(MultipeerService())
}
