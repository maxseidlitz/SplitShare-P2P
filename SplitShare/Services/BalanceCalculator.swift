import Foundation

enum BalanceCalculator {
    static func memberBalances(for group: ExpenseGroup) -> [MemberBalance] {
        var nets: [UUID: Decimal] = Dictionary(uniqueKeysWithValues: group.members.map { ($0.id, Decimal.zero) })

        for expense in group.expenses {
            nets[expense.payerId, default: 0] += expense.amount
            for split in expense.splits {
                nets[split.memberId, default: 0] -= split.amount
            }
        }

        return group.members.map { member in
            MemberBalance(member: member, netBalance: nets[member.id, default: 0])
        }
        .sorted { $0.member.displayName.localizedCaseInsensitiveCompare($1.member.displayName) == .orderedAscending }
    }

    static func simplifiedSettlements(for group: ExpenseGroup) -> [Settlement] {
        var balances = memberBalances(for: group)
            .filter { $0.netBalance != 0 }
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
            let amount = min(-debtor.1, creditor.1)

            if amount > 0 {
                settlements.append(Settlement(from: debtor.0, to: creditor.0, amount: amount))
            }

            balances[debtorIndex].1 += amount
            balances[creditorIndex].1 -= amount

            balances.removeAll { $0.1 == 0 }
        }

        return settlements
    }

    static func equalSplits(amount: Decimal, memberIds: [UUID]) -> [ExpenseSplit] {
        guard !memberIds.isEmpty else { return [] }
        let share = amount / Decimal(memberIds.count)
        return memberIds.map { ExpenseSplit(memberId: $0, amount: share) }
    }

    static func percentageSplits(amount: Decimal, percentages: [UUID: Decimal]) -> [ExpenseSplit] {
        percentages.map { memberId, percent in
            ExpenseSplit(memberId: memberId, amount: amount * percent / 100)
        }
    }
}
