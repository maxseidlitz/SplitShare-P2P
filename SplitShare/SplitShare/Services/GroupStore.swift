import Combine
import Foundation
import MultipeerConnectivity

@MainActor
final class GroupStore: ObservableObject {
    @Published private(set) var groups: [ExpenseGroup] = []

    private weak var peerService: MultipeerService?
    private let storageURL: URL

    init() {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        storageURL = directory.appendingPathComponent("groups.json")
        load()
    }

    func attach(peerService: MultipeerService) {
        self.peerService = peerService
        peerService.onEnvelopeReceived = { [weak self] envelope, peer in
            Task { @MainActor in
                self?.handle(envelope: envelope, from: peer)
            }
        }
        peerService.onPeerConnected = { [weak self] peer in
            Task { @MainActor in
                self?.respondWithSnapshot(to: peer)
                self?.requestSyncFromConnectedPeers()
            }
        }
        peerService.startNetworking()
    }

    func createGroup(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let peerService else { return }

        let selfMember = GroupMember(
            id: peerService.profile.id,
            displayName: peerService.profile.displayName,
            peerDeviceId: deviceId(from: peerService)
        )

        let group = ExpenseGroup(name: trimmed, members: [selfMember])
        groups.append(group)
        persist()
        broadcastGroupUpdate(group)
    }

    func addExpense(to groupId: UUID, expense: Expense) {
        guard let index = groups.firstIndex(where: { $0.id == groupId }) else { return }
        groups[index].expenses.append(expense)
        groups[index].touch()
        persist()
        broadcastGroupUpdate(groups[index])
    }

    func deleteExpense(groupId: UUID, expenseId: UUID) {
        guard let index = groups.firstIndex(where: { $0.id == groupId }) else { return }
        groups[index].expenses.removeAll { $0.id == expenseId }
        groups[index].touch()
        persist()
        broadcastGroupUpdate(groups[index])
    }

    func inviteMember(to groupId: UUID, member: GroupMember) {
        guard let index = groups.firstIndex(where: { $0.id == groupId }) else { return }
        guard !groups[index].members.contains(where: { $0.id == member.id || $0.displayName == member.displayName }) else { return }

        groups[index].members.append(member)
        groups[index].touch()
        persist()
        broadcastGroupUpdate(groups[index])
    }

    func sendGroupInvite(_ group: ExpenseGroup, to peer: MCPeerID) {
        guard let peerService,
              let payload = try? JSONEncoder().encode(GroupInvitePayload(group: group)) else { return }

        let envelope = SyncEnvelope(
            senderDeviceId: deviceId(from: peerService),
            type: .inviteToGroup,
            payload: payload
        )
        peerService.send(envelope, to: [peer])
    }

    func requestSyncFromConnectedPeers() {
        guard let peerService else { return }
        let payload = try? JSONEncoder().encode(ProfilePayload(profile: peerService.profile))
        guard let payload else { return }

        let envelope = SyncEnvelope(
            senderDeviceId: deviceId(from: peerService),
            type: .requestSync,
            payload: payload
        )
        peerService.send(envelope)
    }

    func group(with id: UUID) -> ExpenseGroup? {
        groups.first { $0.id == id }
    }

    private func handle(envelope: SyncEnvelope, from peer: MCPeerID) {
        switch envelope.type {
        case .profile:
            if let payload = try? JSONDecoder().decode(ProfilePayload.self, from: envelope.payload) {
                mergeProfileMember(payload.profile, peerDeviceId: envelope.senderDeviceId, peerName: peer.displayName)
            }
        case .groupSnapshot:
            if let payload = try? JSONDecoder().decode(GroupSnapshotPayload.self, from: envelope.payload) {
                mergeGroups(payload.groups)
            }
        case .groupUpdate:
            if let payload = try? JSONDecoder().decode(GroupUpdatePayload.self, from: envelope.payload) {
                mergeGroup(payload.group)
            }
        case .inviteToGroup:
            if let payload = try? JSONDecoder().decode(GroupInvitePayload.self, from: envelope.payload) {
                mergeGroup(payload.group)
            }
        case .requestSync:
            respondWithSnapshot(to: peer)
        }
    }

    private func respondWithSnapshot(to peer: MCPeerID) {
        guard let peerService else { return }
        guard let payload = try? JSONEncoder().encode(GroupSnapshotPayload(groups: groups)) else { return }

        let envelope = SyncEnvelope(
            senderDeviceId: deviceId(from: peerService),
            type: .groupSnapshot,
            payload: payload
        )
        peerService.send(envelope, to: [peer])
    }

    private func broadcastGroupUpdate(_ group: ExpenseGroup) {
        guard let peerService,
              let payload = try? JSONEncoder().encode(GroupUpdatePayload(group: group)) else { return }

        let envelope = SyncEnvelope(
            senderDeviceId: deviceId(from: peerService),
            type: .groupUpdate,
            payload: payload
        )
        peerService.send(envelope)
    }

    private func mergeProfileMember(_ profile: PeerProfile, peerDeviceId: String, peerName: String) {
        var changed = false

        for groupIndex in groups.indices {
            if let memberIndex = groups[groupIndex].members.firstIndex(where: { $0.id == profile.id }) {
                if groups[groupIndex].members[memberIndex].displayName != profile.displayName {
                    groups[groupIndex].members[memberIndex].displayName = profile.displayName
                    changed = true
                }
                if groups[groupIndex].members[memberIndex].peerDeviceId == nil {
                    groups[groupIndex].members[memberIndex].peerDeviceId = peerDeviceId
                    changed = true
                }
            } else if let memberIndex = groups[groupIndex].members.firstIndex(where: { $0.peerDeviceId == peerDeviceId }) {
                groups[groupIndex].members[memberIndex].displayName = profile.displayName
                changed = true
            }
        }

        if changed {
            persist()
        }
    }

    private func mergeGroups(_ incoming: [ExpenseGroup]) {
        for group in incoming {
            mergeGroup(group)
        }
    }

    private func mergeGroup(_ incoming: ExpenseGroup) {
        if let index = groups.firstIndex(where: { $0.id == incoming.id }) {
            if incoming.updatedAt >= groups[index].updatedAt {
                groups[index] = incoming
            } else {
                groups[index] = mergeMembersAndExpenses(local: groups[index], remote: incoming)
            }
        } else {
            groups.append(incoming)
        }
        groups.sort { $0.updatedAt > $1.updatedAt }
        persist()
    }

    private func mergeMembersAndExpenses(local: ExpenseGroup, remote: ExpenseGroup) -> ExpenseGroup {
        var merged = local.updatedAt >= remote.updatedAt ? local : remote
        let allMembers = Dictionary(uniqueKeysWithValues: (local.members + remote.members).map { ($0.id, $0) })
        merged.members = Array(allMembers.values)

        var expensesById: [UUID: Expense] = Dictionary(uniqueKeysWithValues: local.expenses.map { ($0.id, $0) })
        for expense in remote.expenses {
            if let existing = expensesById[expense.id] {
                if expense.createdAt >= existing.createdAt {
                    expensesById[expense.id] = expense
                }
            } else {
                expensesById[expense.id] = expense
            }
        }
        merged.expenses = expensesById.values.sorted { $0.date > $1.date }
        merged.touch()
        return merged
    }

    private func deviceId(from peerService: MultipeerService) -> String {
        UserDefaults.standard.string(forKey: "splitshare.deviceId") ?? UUID().uuidString
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: storageURL.path),
              let data = try? Data(contentsOf: storageURL),
              let decoded = try? JSONDecoder().decode([ExpenseGroup].self, from: data) else {
            return
        }
        groups = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(groups) else { return }
        try? data.write(to: storageURL, options: [.atomic])
    }
}
