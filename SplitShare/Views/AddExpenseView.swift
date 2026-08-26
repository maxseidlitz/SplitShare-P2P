import SwiftUI

struct AddExpenseView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var groupStore: GroupStore
    @EnvironmentObject private var peerService: MultipeerService

    let group: ExpenseGroup

    @State private var title = ""
    @State private var amountText = ""
    @State private var payerId: UUID?
    @State private var splitMode: SplitMode = .equal
    @State private var selectedMemberIds: Set<UUID> = []
    @State private var exactAmounts: [UUID: String] = [:]
    @State private var percentages: [UUID: String] = [:]
    @State private var date = Date()

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
            let total = selectedMemberIds.compactMap { exactAmounts[$0].flatMap { Decimal(string: $0.replacingOccurrences(of: ",", with: ".")) } }.reduce(0, +)
            return total == amount
        case .percentage:
            let total = selectedMemberIds.compactMap { percentages[$0].flatMap { Decimal(string: $0.replacingOccurrences(of: ",", with: ".")) } }.reduce(0, +)
            return total == 100
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

                Section("Aufteilen") {
                    Picker("Modus", selection: $splitMode) {
                        ForEach(SplitMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

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
                                    let share = amount / Decimal(selectedMemberIds.count)
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
                }
            }
            .navigationTitle("Neue Ausgabe")
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
                payerId = group.members.first(where: { $0.id == peerService.profile.id })?.id ?? group.members.first?.id
                selectedMemberIds = Set(group.members.map(\.id))
            }
        }
    }

    private var currencyCode: String {
        Locale.current.currency?.identifier ?? "EUR"
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

        let expense = Expense(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            amount: amount,
            payerId: payerId,
            splits: splits,
            date: date
        )

        groupStore.addExpense(to: group.id, expense: expense)
        dismiss()
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
