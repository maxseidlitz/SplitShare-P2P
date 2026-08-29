import Combine
import Foundation
import MultipeerConnectivity

@MainActor
final class GroupStore: ObservableObject {
    @Published private(set) var groups: [ExpenseGroup] = []

    private weak var peerService: MultipeerService?
    private let storageURL: URL
    private var profileIdByDeviceId: [String: UUID] = [:]
    private var deletedGroupIds: Set<UUID> = []

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
                self?.shareMembership(with: peer)
            }
        }
        refreshTrustedDeviceIds()
        peerService.startNetworking()
    }

    func createGroup(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let peerService else { return }

        let selfMember = GroupMember(
            id: peerService.profile.id,
            displayName: peerService.profile.displayName,
            peerDeviceId: peerService.deviceId
        )

        let group = ExpenseGroup(name: trimmed, members: [selfMember])
        groups.append(group)
        persist()
        refreshTrustedDeviceIds()
    }

    func addExpense(to groupId: UUID, expense: Expense) {
        guard let index = groups.firstIndex(where: { $0.id == groupId }) else { return }
        groups[index].expenses.append(expense)
        groups[index].expenses.sort { $0.date > $1.date }
        groups[index].touch()
        persist()
        broadcastGroupUpdate(groups[index])
    }

    func updateExpense(in groupId: UUID, expense: Expense) {
        guard let groupIndex = groups.firstIndex(where: { $0.id == groupId }),
              let expenseIndex = groups[groupIndex].expenses.firstIndex(where: { $0.id == expense.id }) else { return }
        groups[groupIndex].expenses[expenseIndex] = expense
        groups[groupIndex].expenses.sort { $0.date > $1.date }
        groups[groupIndex].touch()
        persist()
        broadcastGroupUpdate(groups[groupIndex])
    }

    func deleteExpense(groupId: UUID, expenseId: UUID) {
        guard let index = groups.firstIndex(where: { $0.id == groupId }) else { return }
        groups[index].expenses.removeAll { $0.id == expenseId }
        if !groups[index].deletedExpenseIds.contains(expenseId) {
            groups[index].deletedExpenseIds.append(expenseId)
        }
        groups[index].touch()
        persist()
        broadcastGroupUpdate(groups[index])
    }

    func deleteGroup(_ groupId: UUID) {
        groups.removeAll { $0.id == groupId }
        deletedGroupIds.insert(groupId)
        persist()
        refreshTrustedDeviceIds()
    }

    func applyOwnDisplayName() {
        guard let peerService else { return }
        var changedGroupIds: [UUID] = []
        for index in groups.indices {
            if let memberIndex = groups[index].members.firstIndex(where: { $0.id == peerService.profile.id }) {
                if groups[index].members[memberIndex].displayName != peerService.profile.displayName {
                    groups[index].members[memberIndex].displayName = peerService.profile.displayName
                    groups[index].touch()
                    changedGroupIds.append(groups[index].id)
                }
            }
        }
        guard !changedGroupIds.isEmpty else { return }
        persist()
        for id in changedGroupIds {
            if let group = group(with: id) {
                broadcastGroupUpdate(group)
            }
        }
    }

    func inviteMember(to groupId: UUID, member: GroupMember) {
        guard let index = groups.firstIndex(where: { $0.id == groupId }) else { return }
        guard !groups[index].members.contains(where: {
            $0.id == member.id || ($0.peerDeviceId != nil && $0.peerDeviceId == member.peerDeviceId)
        }) else { return }

        groups[index].members.append(member)
        groups[index].touch()
        persist()
        refreshTrustedDeviceIds()
        broadcastGroupUpdate(groups[index])
    }

    @discardableResult
    func inviteByQR(_ payload: QRIdentity.Payload, to groupId: UUID) -> String? {
        guard let peerService else { return "Sync ist nicht bereit." }
        if payload.deviceId == peerService.deviceId || payload.profileId == peerService.profile.id {
            return "Das ist dein eigener Code."
        }
        guard group(with: groupId) != nil else { return "Gruppe nicht gefunden." }

        profileIdByDeviceId[payload.deviceId] = payload.profileId
        let member = GroupMember(
            id: payload.profileId,
            displayName: payload.displayName,
            peerDeviceId: payload.deviceId
        )
        inviteMember(to: groupId, member: member)

        if let peer = peerService.discoveredPeers.first(where: { peerService.deviceId(for: $0) == payload.deviceId })
            ?? peerService.connectedPeers.first(where: { peerService.deviceId(for: $0) == payload.deviceId }) {
            let alreadyConnected = peerService.connectedPeers.contains {
                peerService.deviceId(for: $0) == payload.deviceId
            }
            if !alreadyConnected {
                peerService.invite(peer)
            }
            if let group = group(with: groupId) {
                sendGroupInvite(group, to: peer)
            }
        }

        return nil
    }

    func sendGroupInvite(_ group: ExpenseGroup, to peer: MCPeerID) {
        guard let peerService,
              let payload = try? JSONEncoder().encode(GroupInvitePayload(group: group)) else { return }

        let envelope = SyncEnvelope(
            senderDeviceId: peerService.deviceId,
            type: .inviteToGroup,
            payload: payload
        )
        peerService.send(envelope, to: [peer])
    }

    func requestSyncFromConnectedPeers() {
        guard let peerService else { return }
        let targets = peerService.connectedPeers.filter { peerService.isTrusted($0) }
        guard !targets.isEmpty else { return }
        guard let payload = try? JSONEncoder().encode(ProfilePayload(profile: peerService.profile)) else { return }

        let envelope = SyncEnvelope(
            senderDeviceId: peerService.deviceId,
            type: .requestSync,
            payload: payload
        )
        peerService.send(envelope, to: targets)
    }

    func group(with id: UUID) -> ExpenseGroup? {
        groups.first { $0.id == id }
    }

    private func handle(envelope: SyncEnvelope, from peer: MCPeerID) {
        peerService?.rememberDeviceId(envelope.senderDeviceId, for: peer)

        switch envelope.type {
        case .profile:
            if let payload = try? JSONDecoder().decode(ProfilePayload.self, from: envelope.payload) {
                profileIdByDeviceId[envelope.senderDeviceId] = payload.profile.id
                mergeProfileMember(payload.profile, peerDeviceId: envelope.senderDeviceId, peerName: peer.displayName)
            }
        case .groupSnapshot:
            if let payload = try? JSONDecoder().decode(GroupSnapshotPayload.self, from: envelope.payload) {
                mergeGroups(payload.groups.filter { shouldAccept($0) })
            }
        case .groupUpdate:
            if let payload = try? JSONDecoder().decode(GroupUpdatePayload.self, from: envelope.payload),
               shouldAccept(payload.group) {
                mergeGroup(payload.group)
            }
        case .inviteToGroup:
            if let payload = try? JSONDecoder().decode(GroupInvitePayload.self, from: envelope.payload),
               shouldAccept(payload.group) {
                mergeGroup(payload.group)
                shareMembership(with: peer, deviceId: envelope.senderDeviceId)
            }
        case .requestSync:
            shareMembership(with: peer, deviceId: envelope.senderDeviceId)
        }
    }

    private func shareMembership(with peer: MCPeerID, deviceId: String? = nil) {
        guard let peerService else { return }
        let resolvedId = deviceId ?? peerService.deviceId(for: peer)
        let shared = groups(sharedWith: resolvedId)
        guard !shared.isEmpty else { return }

        peerService.broadcastProfile(to: [peer])
        guard let payload = try? JSONEncoder().encode(GroupSnapshotPayload(groups: shared)) else { return }
        let envelope = SyncEnvelope(
            senderDeviceId: peerService.deviceId,
            type: .groupSnapshot,
            payload: payload
        )
        peerService.send(envelope, to: [peer])
    }

    private func groups(sharedWith deviceId: String?) -> [ExpenseGroup] {
        guard let deviceId else { return [] }
        let profileId = profileIdByDeviceId[deviceId]
        return groups.filter { group in
            group.members.contains { member in
                member.peerDeviceId == deviceId || (profileId != nil && member.id == profileId)
            }
        }
    }

    private func shouldAccept(_ incoming: ExpenseGroup) -> Bool {
        if deletedGroupIds.contains(incoming.id) {
            return false
        }
        if groups.contains(where: { $0.id == incoming.id }) {
            return true
        }
        guard let myId = peerService?.profile.id else { return false }
        return incoming.members.contains(where: { $0.id == myId })
    }

    private func broadcastGroupUpdate(_ group: ExpenseGroup) {
        guard let peerService,
              let payload = try? JSONEncoder().encode(GroupUpdatePayload(group: group)) else { return }

        let targets = peerService.connectedPeers.filter { peer in
            guard let deviceId = peerService.deviceId(for: peer) else { return false }
            return group.members.contains {
                $0.peerDeviceId == deviceId || $0.id == profileIdByDeviceId[deviceId]
            }
        }
        guard !targets.isEmpty else { return }

        let envelope = SyncEnvelope(
            senderDeviceId: peerService.deviceId,
            type: .groupUpdate,
            payload: payload
        )
        peerService.send(envelope, to: targets)
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
            refreshTrustedDeviceIds()
        }
    }

    private func mergeGroups(_ incoming: [ExpenseGroup]) {
        for group in incoming {
            mergeGroup(group)
        }
    }

    private func mergeGroup(_ incoming: ExpenseGroup) {
        guard !deletedGroupIds.contains(incoming.id) else { return }

        if let index = groups.firstIndex(where: { $0.id == incoming.id }) {
            let before = groups[index]
            let merged = mergeMembersAndExpenses(local: before, remote: incoming)
            groups[index] = merged
            if merged != before {
                broadcastGroupUpdate(merged)
            }
        } else {
            groups.append(incoming)
        }
        groups.sort { $0.updatedAt > $1.updatedAt }
        persist()
        refreshTrustedDeviceIds()
    }

    private func mergeMembersAndExpenses(local: ExpenseGroup, remote: ExpenseGroup) -> ExpenseGroup {
        var merged = local.updatedAt >= remote.updatedAt ? local : remote

        let membersById = Dictionary(
            (local.members + remote.members).map { ($0.id, $0) },
            uniquingKeysWith: Self.mergedMember
        )
        merged.members = membersById.values.sorted {
            let nameOrder = $0.displayName.localizedCaseInsensitiveCompare($1.displayName)
            if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
            return $0.id.uuidString < $1.id.uuidString
        }

        let deleted = Set(local.deletedExpenseIds + remote.deletedExpenseIds)
        var expensesById = Dictionary(
            local.expenses.map { ($0.id, $0) },
            uniquingKeysWith: { current, incoming in
                incoming.updatedAt >= current.updatedAt ? incoming : current
            }
        )
        for expense in remote.expenses {
            if deleted.contains(expense.id) { continue }
            if let existing = expensesById[expense.id] {
                if expense.updatedAt >= existing.updatedAt {
                    expensesById[expense.id] = expense
                }
            } else {
                expensesById[expense.id] = expense
            }
        }
        for id in deleted {
            expensesById.removeValue(forKey: id)
        }

        merged.deletedExpenseIds = deleted.sorted { $0.uuidString < $1.uuidString }
        merged.expenses = expensesById.values.sorted {
            if $0.date != $1.date { return $0.date > $1.date }
            return $0.id.uuidString < $1.id.uuidString
        }
        merged.updatedAt = max(local.updatedAt, remote.updatedAt)
        return merged
    }

    private static func mergedMember(_ current: GroupMember, _ incoming: GroupMember) -> GroupMember {
        var merged = current
        if merged.peerDeviceId == nil {
            merged.peerDeviceId = incoming.peerDeviceId
        }
        return merged
    }

    private func refreshTrustedDeviceIds() {
        let ids = Set(groups.flatMap { $0.members.compactMap(\.peerDeviceId) })
        peerService?.setTrustedDeviceIds(ids)
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: storageURL.path),
              let data = try? Data(contentsOf: storageURL) else {
            return
        }
        if let persisted = try? JSONDecoder().decode(PersistedStore.self, from: data) {
            groups = persisted.groups
            deletedGroupIds = Set(persisted.deletedGroupIds)
            return
        }
        if let decoded = try? JSONDecoder().decode([ExpenseGroup].self, from: data) {
            groups = decoded
        }
    }

    private func persist() {
        let persisted = PersistedStore(groups: groups, deletedGroupIds: Array(deletedGroupIds))
        guard let data = try? JSONEncoder().encode(persisted) else { return }
        try? data.write(to: storageURL, options: [.atomic])
    }
}

private struct PersistedStore: Codable {
    var groups: [ExpenseGroup]
    var deletedGroupIds: [UUID]
}
