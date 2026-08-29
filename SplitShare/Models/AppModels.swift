import Foundation

struct PeerProfile: Codable, Equatable, Identifiable, Hashable {
    let id: UUID
    var displayName: String

    init(id: UUID = UUID(), displayName: String) {
        self.id = id
        self.displayName = displayName
    }
}

struct GroupMember: Codable, Equatable, Identifiable, Hashable {
    let id: UUID
    var displayName: String
    var peerDeviceId: String?

    init(id: UUID = UUID(), displayName: String, peerDeviceId: String? = nil) {
        self.id = id
        self.displayName = displayName
        self.peerDeviceId = peerDeviceId
    }
}

struct ExpenseSplit: Codable, Equatable, Identifiable, Hashable {
    var id: UUID { memberId }
    let memberId: UUID
    var amount: Decimal
}

struct Expense: Codable, Equatable, Identifiable, Hashable {
    let id: UUID
    var title: String
    var amount: Decimal
    var payerId: UUID
    var splits: [ExpenseSplit]
    var date: Date
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        amount: Decimal,
        payerId: UUID,
        splits: [ExpenseSplit],
        date: Date = Date(),
        createdAt: Date = Date(),
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.amount = amount
        self.payerId = payerId
        self.splits = splits
        self.date = date
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        amount = try container.decode(Decimal.self, forKey: .amount)
        payerId = try container.decode(UUID.self, forKey: .payerId)
        splits = try container.decode([ExpenseSplit].self, forKey: .splits)
        date = try container.decode(Date.self, forKey: .date)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
    }
}

struct ExpenseGroup: Codable, Equatable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var members: [GroupMember]
    var expenses: [Expense]
    var deletedExpenseIds: [UUID]
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        members: [GroupMember],
        expenses: [Expense] = [],
        deletedExpenseIds: [UUID] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.members = members
        self.expenses = expenses
        self.deletedExpenseIds = deletedExpenseIds
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        members = try container.decode([GroupMember].self, forKey: .members)
        expenses = try container.decode([Expense].self, forKey: .expenses)
        deletedExpenseIds = try container.decodeIfPresent([UUID].self, forKey: .deletedExpenseIds) ?? []
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    mutating func touch() {
        updatedAt = Date()
    }
}

enum SplitMode: String, CaseIterable, Identifiable {
    case equal
    case exact
    case percentage

    var id: String { rawValue }

    var title: String {
        switch self {
        case .equal: return "Gleichmäßig"
        case .exact: return "Exakte Beträge"
        case .percentage: return "Prozentual"
        }
    }
}

struct MemberBalance: Identifiable, Hashable {
    let member: GroupMember
    let netBalance: Decimal

    var id: UUID { member.id }
}

struct Settlement: Identifiable, Hashable {
    let from: GroupMember
    let to: GroupMember
    let amount: Decimal

    var id: String { "\(from.id)-\(to.id)-\(amount)" }
}

struct RawDebt: Identifiable, Hashable {
    let expenseId: UUID
    let expenseTitle: String
    let expenseDate: Date
    let from: GroupMember
    let to: GroupMember
    let amount: Decimal

    var id: String { "\(expenseId.uuidString)-\(from.id.uuidString)-\(to.id.uuidString)" }
}

enum SyncMessageType: String, Codable {
    case profile
    case groupSnapshot
    case groupUpdate
    case inviteToGroup
    case requestSync
}

struct SyncEnvelope: Codable {
    let id: UUID
    let senderDeviceId: String
    let timestamp: Date
    let type: SyncMessageType
    let payload: Data

    init(senderDeviceId: String, type: SyncMessageType, payload: Data) {
        self.id = UUID()
        self.senderDeviceId = senderDeviceId
        self.timestamp = Date()
        self.type = type
        self.payload = payload
    }
}

struct GroupInvitePayload: Codable {
    let group: ExpenseGroup
}

struct GroupUpdatePayload: Codable {
    let group: ExpenseGroup
}

struct GroupSnapshotPayload: Codable {
    let groups: [ExpenseGroup]
}

struct ProfilePayload: Codable {
    let profile: PeerProfile
}
