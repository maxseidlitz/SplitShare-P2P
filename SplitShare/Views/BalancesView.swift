import SwiftUI

private enum DebtDisplayMode: String, CaseIterable, Identifiable {
    case simplified
    case perExpense

    var id: String { rawValue }

    var title: String {
        switch self {
        case .simplified: return "Vereinfacht"
        case .perExpense: return "Pro Ausgabe"
        }
    }
}

struct BalancesView: View {
    let group: ExpenseGroup

    @State private var displayMode: DebtDisplayMode = .simplified

    private var balances: [MemberBalance] {
        BalanceCalculator.memberBalances(for: group)
    }

    private var settlements: [Settlement] {
        BalanceCalculator.simplifiedSettlements(for: group)
    }

    private var rawDebtsByExpense: [(id: UUID, title: String, date: Date, debts: [RawDebt])] {
        let grouped = Dictionary(grouping: BalanceCalculator.rawDebts(for: group), by: \.expenseId)
        return grouped.values.compactMap { debts in
            guard let first = debts.first else { return nil }
            return (id: first.expenseId, title: first.expenseTitle, date: first.expenseDate, debts: debts)
        }
        .sorted { $0.date > $1.date }
    }

    var body: some View {
        List {
            Section {
                Picker("Darstellung", selection: $displayMode) {
                    ForEach(DebtDisplayMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Salden") {
                ForEach(balances) { balance in
                    HStack {
                        Text(balance.member.displayName)
                        Spacer()
                        Text(formattedBalance(balance.netBalance))
                            .foregroundStyle(balance.netBalance >= 0 ? Color.green : Color.red)
                            .fontWeight(.semibold)
                    }
                }
            }

            switch displayMode {
            case .simplified:
                simplifiedSections
            case .perExpense:
                perExpenseSections
            }
        }
    }

    @ViewBuilder
    private var simplifiedSections: some View {
        if !settlements.isEmpty {
            Section {
                ForEach(settlements) { settlement in
                    HStack(alignment: .top) {
                        Image(systemName: "arrow.right.circle.fill")
                            .foregroundStyle(.teal)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(settlement.from.displayName) → \(settlement.to.displayName)")
                            Text(settlement.amount.formatted(.currency(code: currencyCode)))
                                .font(.headline)
                        }
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text("Ausgleichsvorschläge")
            } footer: {
                Text("Über alle Ausgaben hinweg auf möglichst wenige Zahlungen reduziert.")
            }
        } else if group.expenses.isEmpty {
            Section {
                Text("Noch keine Ausgaben erfasst.")
                    .foregroundStyle(.secondary)
            }
        } else {
            Section {
                Label("Alles ausgeglichen", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } footer: {
                Text("Über alle Ausgaben hinweg auf möglichst wenige Zahlungen reduziert.")
            }
        }
    }

    @ViewBuilder
    private var perExpenseSections: some View {
        if group.expenses.isEmpty {
            Section {
                Text("Noch keine Ausgaben erfasst.")
                    .foregroundStyle(.secondary)
            }
        } else if rawDebtsByExpense.isEmpty {
            Section {
                Text("Keine offenen Schulden pro Ausgabe.")
                    .foregroundStyle(.secondary)
            } footer: {
                Text("Einzelne Schulden je Ausgabe, ohne Saldierung über alle Rechnungen.")
            }
        } else {
            ForEach(rawDebtsByExpense, id: \.id) { groupDebts in
                Section {
                    ForEach(groupDebts.debts) { debt in
                        HStack(alignment: .top) {
                            Image(systemName: "arrow.right.circle")
                                .foregroundStyle(.teal)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(debt.from.displayName) → \(debt.to.displayName)")
                                Text(debt.amount.formatted(.currency(code: currencyCode)))
                                    .font(.headline)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    Text(groupDebts.title)
                } footer: {
                    if groupDebts.id == rawDebtsByExpense.last?.id {
                        Text("Einzelne Schulden je Ausgabe, ohne Saldierung über alle Rechnungen.")
                    }
                }
            }
        }
    }

    private var currencyCode: String {
        Locale.current.currency?.identifier ?? "EUR"
    }

    private func formattedBalance(_ value: Decimal) -> String {
        let prefix = value >= 0 ? "+" : ""
        return prefix + value.formatted(.currency(code: currencyCode))
    }
}

#Preview {
    BalancesView(
        group: ExpenseGroup(
            name: "Demo",
            members: [
                GroupMember(displayName: "Anna"),
                GroupMember(displayName: "Ben")
            ],
            expenses: []
        )
    )
}
