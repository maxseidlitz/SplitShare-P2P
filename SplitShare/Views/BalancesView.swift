import SwiftUI

struct BalancesView: View {
    let group: ExpenseGroup

    private var balances: [MemberBalance] {
        BalanceCalculator.memberBalances(for: group)
    }

    private var settlements: [Settlement] {
        BalanceCalculator.simplifiedSettlements(for: group)
    }

    var body: some View {
        List {
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

            if !settlements.isEmpty {
                Section("Ausgleichsvorschläge") {
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
