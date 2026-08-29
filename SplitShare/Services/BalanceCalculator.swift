import Foundation

enum BalanceCalculator {
    private static let moneyHandler = NSDecimalNumberHandler(
        roundingMode: .plain,
        scale: 2,
        raiseOnExactness: false,
        raiseOnOverflow: false,
        raiseOnUnderflow: false,
        raiseOnDivideByZero: false
    )

    static func roundMoney(_ value: Decimal) -> Decimal {
        NSDecimalNumber(decimal: value).rounding(accordingToBehavior: moneyHandler).decimalValue
    }

    static func memberBalances(for group: ExpenseGroup) -> [MemberBalance] {
        var nets: [UUID: Decimal] = Dictionary(
            group.members.map { ($0.id, Decimal.zero) },
            uniquingKeysWith: { first, _ in first }
        )

        for expense in group.expenses {
            nets[expense.payerId, default: 0] += expense.amount
            for split in expense.splits {
                nets[split.memberId, default: 0] -= split.amount
            }
        }

        return group.members.map { member in
            MemberBalance(member: member, netBalance: roundMoney(nets[member.id, default: 0]))
        }
        .sorted { $0.member.displayName.localizedCaseInsensitiveCompare($1.member.displayName) == .orderedAscending }
    }

    static func simplifiedSettlements(for group: ExpenseGroup) -> [Settlement] {
        var balances = memberBalances(for: group)
            .filter { abs($0.netBalance) >= Decimal(string: "0.01")! }
            .map { ($0.member, $0.netBalance) }

        var settlements: [Settlement] = []

        while balances.count > 1 {
            balances.sort { $0.1 < $1.1 }
            guard let debtorIndex = balances.firstIndex(where: { $0.1 < 0 }),
                  let creditorIndex = balances.lastIndex(where: { $0.1 > 0 }) else {
                break
            }

            let debtor = balances[debtorIndex]
            let creditor = balances[creditorIndex]
            let amount = roundMoney(min(-debtor.1, creditor.1))

            if amount > 0 {
                settlements.append(Settlement(from: debtor.0, to: creditor.0, amount: amount))
            }

            balances[debtorIndex].1 += amount
            balances[creditorIndex].1 -= amount

            balances.removeAll { abs($0.1) < Decimal(string: "0.01")! }
        }

        return settlements
    }

    static func rawDebts(for group: ExpenseGroup) -> [RawDebt] {
        let membersById = Dictionary(
            group.members.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var debts: [RawDebt] = []

        for expense in group.expenses.sorted(by: { $0.date > $1.date }) {
            guard let payer = membersById[expense.payerId] else { continue }
            for split in expense.splits where split.memberId != expense.payerId && split.amount > 0 {
                guard let debtor = membersById[split.memberId] else { continue }
                debts.append(
                    RawDebt(
                        expenseId: expense.id,
                        expenseTitle: expense.title,
                        expenseDate: expense.date,
                        from: debtor,
                        to: payer,
                        amount: split.amount
                    )
                )
            }
        }

        return debts
    }

    static func equalSplits(amount: Decimal, memberIds: [UUID]) -> [ExpenseSplit] {
        guard !memberIds.isEmpty else { return [] }
        let count = Decimal(memberIds.count)
        var allocated = Decimal(0)
        return memberIds.enumerated().map { index, memberId in
            if index == memberIds.count - 1 {
                return ExpenseSplit(memberId: memberId, amount: amount - allocated)
            }
            let share = roundMoney(amount / count)
            allocated += share
            return ExpenseSplit(memberId: memberId, amount: share)
        }
    }

    static func percentageSplits(amount: Decimal, percentages: [UUID: Decimal]) -> [ExpenseSplit] {
        let memberIds = Array(percentages.keys)
        guard !memberIds.isEmpty else { return [] }
        var allocated = Decimal(0)
        return memberIds.enumerated().map { index, memberId in
            if index == memberIds.count - 1 {
                return ExpenseSplit(memberId: memberId, amount: amount - allocated)
            }
            let share = roundMoney(amount * (percentages[memberId] ?? 0) / 100)
            allocated += share
            return ExpenseSplit(memberId: memberId, amount: share)
        }
    }
}
