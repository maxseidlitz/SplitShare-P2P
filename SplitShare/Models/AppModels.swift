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

    init(
        id: UUID = UUID(),
        title: String,
        amount: Decimal,
        payerId: UUID,
        splits: [ExpenseSplit],
        date: Date = Date(),
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.amount = amount
        self.payerId = payerId
        self.splits = splits
        self.date = date
        self.createdAt = createdAt
    }
}

struct ExpenseGroup: Codable, Equatable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var members: [GroupMember]
    var expenses: [Expense]
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        members: [GroupMember],
        expenses: [Expense] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.members = members
        self.expenses = expenses
        self.createdAt = createdAt
        self.updatedAt = updatedAt
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
