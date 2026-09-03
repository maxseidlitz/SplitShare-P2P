import Combine
import Foundation
import MultipeerConnectivity

@MainActor
final class GroupStore: ObservableObject {
    @Published private(set) var groups: [ExpenseGroup] = []
    @Published private(set) var archivedGroupIds: Set<UUID> = []
    @Published var pendingOpenGroupId: UUID?
    @Published var presentedNotice: GroupNotice?

    private weak var peerService: MultipeerService?
    private let storageURL: URL
    private var profileIdByDeviceId: [String: UUID] = [:]
    private var deletedGroupIds: Set<UUID> = []
    private var noticeQueue: [GroupNotice] = []

    init() {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        storageURL = directory.appendingPathComponent("groups.json")
        load()
    }

    var activeGroups: [ExpenseGroup] {
        groups.filter { !archivedGroupIds.contains($0.id) }
    }

    var archivedGroups: [ExpenseGroup] {
        groups.filter { archivedGroupIds.contains($0.id) }
    }

    func isArchived(_ groupId: UUID) -> Bool {
        archivedGroupIds.contains(groupId)
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

        let group = ExpenseGroup(name: trimmed, adminId: selfMember.id, members: [selfMember])
        groups.append(group)
        persist()
        refreshTrustedDeviceIds()
        pendingOpenGroupId = group.id
    }

    func addExpense(to groupId: UUID, expense: Expense) {
        guard let index = groups.firstIndex(where: { $0.id == groupId }) else { return }
        guard !archivedGroupIds.contains(groupId) else { return }
        groups[index].expenses.append(expense)
        groups[index].expenses.sort { $0.date > $1.date }
        groups[index].touch()
        persist()
        broadcastGroupUpdate(groups[index])
    }

    func updateExpense(in groupId: UUID, expense: Expense) {
        guard let groupIndex = groups.firstIndex(where: { $0.id == groupId }),
              let expenseIndex = groups[groupIndex].expenses.firstIndex(where: { $0.id == expense.id }) else { return }
        guard !archivedGroupIds.contains(groupId) else { return }
        groups[groupIndex].expenses[expenseIndex] = expense
        groups[groupIndex].expenses.sort { $0.date > $1.date }
        groups[groupIndex].touch()
        persist()
        broadcastGroupUpdate(groups[groupIndex])
    }

    func deleteExpense(groupId: UUID, expenseId: UUID) {
        guard let index = groups.firstIndex(where: { $0.id == groupId }) else { return }
        guard !archivedGroupIds.contains(groupId) else { return }
        groups[index].expenses.removeAll { $0.id == expenseId }
        if !groups[index].deletedExpenseIds.contains(expenseId) {
            groups[index].deletedExpenseIds.append(expenseId)
        }
        groups[index].touch()
        persist()
        broadcastGroupUpdate(groups[index])
    }

    @discardableResult
    func markMyDebtsSettled(in groupId: UUID) -> String? {
        guard let peerService, let group = group(with: groupId) else { return "Gruppe nicht gefunden." }
        guard !archivedGroupIds.contains(groupId) else { return "Archivierte Gruppen kannst du nicht ändern." }
        guard group.isActiveMember(peerService.profile.id) else { return "Du bist kein aktives Mitglied." }

        let myId = peerService.profile.id
        let settlements = BalanceCalculator.simplifiedSettlements(for: group).filter { $0.from.id == myId }
        guard !settlements.isEmpty else { return "Du hast keine offenen Schulden." }

        let amount = settlements.reduce(Decimal.zero) { $0 + $1.amount }
        let splits = settlements.map { ExpenseSplit(memberId: $0.to.id, amount: $0.amount) }
        let expense = Expense(
            title: "Ausgleich",
            amount: amount,
            payerId: myId,
            splits: splits
        )
        addExpense(to: groupId, expense: expense)
        return nil
    }

    func leaveBlockReason(for groupId: UUID) -> String? {
        guard let peerService, let group = group(with: groupId) else { return "Gruppe nicht gefunden." }
        let myId = peerService.profile.id
        guard group.isActiveMember(myId) else { return "Du bist kein aktives Mitglied." }
        if BalanceCalculator.owesMoney(myId, in: group) {
            let amount = -BalanceCalculator.netBalance(for: myId, in: group)
            let formatted = amount.formatted(.currency(code: Locale.current.currency?.identifier ?? "EUR"))
            return "Du kannst die Gruppe nicht verlassen, solange du noch \(formatted) schuldest. Markiere deine Schulden unter Salden als bezahlt."
        }
        return nil
    }

    func deleteBlockReason(for groupId: UUID) -> String? {
        guard let peerService, let group = group(with: groupId) else { return "Gruppe nicht gefunden." }
        guard group.isAdmin(peerService.profile.id) || group.activeMembers.count <= 1 else {
            return "Nur der Admin kann die Gruppe für alle löschen."
        }
        if BalanceCalculator.hasOpenBalances(group) {
            return "Die Gruppe kann erst gelöscht werden, wenn alle Salden ausgeglichen sind."
        }
        return nil
    }

    @discardableResult
    func leaveGroup(_ groupId: UUID, newAdminId: UUID? = nil) -> String? {
        guard let peerService, var group = group(with: groupId) else { return "Gruppe nicht gefunden." }
        let myId = peerService.profile.id
        guard group.isActiveMember(myId) else { return "Du bist kein aktives Mitglied." }
        if let reason = leaveBlockReason(for: groupId) { return reason }

        let remaining = group.activeMembers.filter { $0.id != myId }
        if remaining.isEmpty {
            if !group.leftMemberIds.contains(myId) {
                group.leftMemberIds.append(myId)
            }
            group.touch()
            upsert(group)
            archiveLocally(groupId)
            persist()
            refreshTrustedDeviceIds()
            return nil
        }

        if group.isAdmin(myId) {
            guard let newAdminId, remaining.contains(where: { $0.id == newAdminId }) else {
                return "Bitte wähle ein Mitglied, das Admin wird."
            }
            group.adminId = newAdminId
        }

        if !group.leftMemberIds.contains(myId) {
            group.leftMemberIds.append(myId)
        }
        group.touch()
        upsert(group)
        persist()
        broadcastGroupUpdate(group)
        archiveLocally(groupId)
        persist()
        refreshTrustedDeviceIds()
        return nil
    }

    @discardableResult
    func deleteGroupForEveryone(_ groupId: UUID) -> String? {
        guard let peerService, let group = group(with: groupId) else { return "Gruppe nicht gefunden." }
        if let reason = deleteBlockReason(for: groupId) { return reason }

        broadcastGroupDeleted(group, deletedByName: peerService.profile.displayName)
        removeLocally(groupId, rememberDeletion: true)
        persist()
        refreshTrustedDeviceIds()
        return nil
    }

    func removeFromArchive(_ groupId: UUID) {
        guard archivedGroupIds.contains(groupId) else { return }
        removeLocally(groupId, rememberDeletion: true)
        persist()
        refreshTrustedDeviceIds()
    }

    func consumePendingOpenGroup() {
        pendingOpenGroupId = nil
    }

    func consumePresentedNotice() {
        presentedNotice = nil
        presentNextNotice()
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
        for id in changedGroupIds where !archivedGroupIds.contains(id) {
            if let group = group(with: id) {
                broadcastGroupUpdate(group)
            }
        }
    }

    func inviteMember(to groupId: UUID, member: GroupMember) {
        guard let index = groups.firstIndex(where: { $0.id == groupId }) else { return }
        guard !archivedGroupIds.contains(groupId) else { return }

        if groups[index].leftMemberIds.contains(member.id) {
            groups[index].leftMemberIds.removeAll { $0 == member.id }
        }

        if let existing = groups[index].members.firstIndex(where: {
            $0.id == member.id || ($0.peerDeviceId != nil && $0.peerDeviceId == member.peerDeviceId)
        }) {
            groups[index].members[existing].displayName = member.displayName
            if groups[index].members[existing].peerDeviceId == nil {
                groups[index].members[existing].peerDeviceId = member.peerDeviceId
            }
        } else {
            groups[index].members.append(member)
        }

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
                let wasNew = group(with: payload.group.id) == nil
                let wasArchived = archivedGroupIds.contains(payload.group.id)
                mergeGroup(payload.group)
                archivedGroupIds.remove(payload.group.id)
                persist()
                shareMembership(with: peer, deviceId: envelope.senderDeviceId)
                if wasNew || wasArchived {
                    pendingOpenGroupId = payload.group.id
                }
            }
        case .requestSync:
            shareMembership(with: peer, deviceId: envelope.senderDeviceId)
        case .groupDeleted:
            if let payload = try? JSONDecoder().decode(GroupDeletedPayload.self, from: envelope.payload) {
                handleRemoteDeletion(payload)
            }
        }
    }

    private func handleRemoteDeletion(_ payload: GroupDeletedPayload) {
        guard groups.contains(where: { $0.id == payload.groupId }) || archivedGroupIds.contains(payload.groupId) else {
            deletedGroupIds.insert(payload.groupId)
            persist()
            return
        }
        let myName = peerService?.profile.displayName
        if myName != payload.deletedByName {
            enqueueNotice(
                GroupNotice(
                    title: "Gruppe gelöscht",
                    message: "\(payload.deletedByName) hat die Gruppe „\(payload.groupName)“ gelöscht."
                )
            )
        }
        removeLocally(payload.groupId, rememberDeletion: true)
        persist()
        refreshTrustedDeviceIds()
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
        if let myId = peerService?.profile.id, incoming.isActiveMember(myId) {
            return true
        }
        if archivedGroupIds.contains(incoming.id) {
            return false
        }
        return groups.contains(where: { $0.id == incoming.id })
    }

    private func broadcastGroupUpdate(_ group: ExpenseGroup) {
        guard let peerService,
              let payload = try? JSONEncoder().encode(GroupUpdatePayload(group: group)) else { return }

        let targets = connectedTargets(for: group)
        guard !targets.isEmpty else { return }

        let envelope = SyncEnvelope(
            senderDeviceId: peerService.deviceId,
            type: .groupUpdate,
            payload: payload
        )
        peerService.send(envelope, to: targets)
    }

    private func broadcastGroupDeleted(_ group: ExpenseGroup, deletedByName: String) {
        guard let peerService,
              let payload = try? JSONEncoder().encode(
                GroupDeletedPayload(groupId: group.id, groupName: group.name, deletedByName: deletedByName)
              ) else { return }

        let targets = connectedTargets(for: group)
        guard !targets.isEmpty else { return }

        let envelope = SyncEnvelope(
            senderDeviceId: peerService.deviceId,
            type: .groupDeleted,
            payload: payload
        )
        peerService.send(envelope, to: targets)
    }

    private func connectedTargets(for group: ExpenseGroup) -> [MCPeerID] {
        guard let peerService else { return [] }
        return peerService.connectedPeers.filter { peer in
            guard let deviceId = peerService.deviceId(for: peer) else { return false }
            return group.members.contains {
                $0.peerDeviceId == deviceId || $0.id == profileIdByDeviceId[deviceId]
            }
        }
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

        let wasArchived = archivedGroupIds.contains(incoming.id)
        if wasArchived {
            guard let myId = peerService?.profile.id, incoming.isActiveMember(myId) else { return }
            archivedGroupIds.remove(incoming.id)
        }

        if let index = groups.firstIndex(where: { $0.id == incoming.id }) {
            let before = groups[index]
            let merged = mergeMembersAndExpenses(local: before, remote: incoming)
            groups[index] = merged
            if merged != before {
                enqueueMembershipNotices(before: before, after: merged)
                if !archivedGroupIds.contains(merged.id) {
                    broadcastGroupUpdate(merged)
                }
            }
            if wasArchived, let myId = peerService?.profile.id, merged.isActiveMember(myId) {
                pendingOpenGroupId = merged.id
            }
        } else {
            groups.append(incoming)
            if let myId = peerService?.profile.id, incoming.isActiveMember(myId) {
                pendingOpenGroupId = incoming.id
            }
        }
        groups.sort { $0.updatedAt > $1.updatedAt }
        persist()
        refreshTrustedDeviceIds()
    }

    private func mergeMembersAndExpenses(local: ExpenseGroup, remote: ExpenseGroup) -> ExpenseGroup {
        var merged = local.updatedAt >= remote.updatedAt ? local : remote
        let newer = local.updatedAt >= remote.updatedAt ? local : remote

        let olderMembers = local.updatedAt >= remote.updatedAt ? remote.members : local.members
        let newerMembers = local.updatedAt >= remote.updatedAt ? local.members : remote.members
        let membersById = Dictionary(
            (olderMembers + newerMembers).map { ($0.id, $0) },
            uniquingKeysWith: { olderMember, newerMember in
                var mergedMember = newerMember
                if mergedMember.peerDeviceId == nil {
                    mergedMember.peerDeviceId = olderMember.peerDeviceId
                }
                return mergedMember
            }
        )
        merged.members = membersById.values.sorted { lhs, rhs in
            let nameOrder = lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName)
            if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
            return lhs.id.uuidString < rhs.id.uuidString
        }

        let tombstones = Set(local.leftMemberIds + remote.leftMemberIds)
        let revived = Set(newer.activeMembers.map(\.id))
        merged.leftMemberIds = tombstones.subtracting(revived).sorted { lhs, rhs in
            lhs.uuidString < rhs.uuidString
        }
        merged.adminId = newer.adminId

        let deleted = Set(local.deletedExpenseIds + remote.deletedExpenseIds)
        var expensesById = Dictionary(
            local.expenses.map { ($0.id, $0) },
            uniquingKeysWith: { current, incomingExpense in
                incomingExpense.updatedAt >= current.updatedAt ? incomingExpense : current
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

        merged.deletedExpenseIds = deleted.sorted { lhs, rhs in
            lhs.uuidString < rhs.uuidString
        }
        merged.expenses = Array(expensesById.values).sorted { lhs, rhs in
            if lhs.date != rhs.date { return lhs.date > rhs.date }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        merged.updatedAt = max(local.updatedAt, remote.updatedAt)
        return merged
    }

    private func enqueueMembershipNotices(before: ExpenseGroup, after: ExpenseGroup) {
        guard let myId = peerService?.profile.id else { return }
        let departed = Set(before.activeMembers.map(\.id))
            .subtracting(after.activeMembers.map(\.id))
            .subtracting([myId])

        for memberId in departed {
            let name = after.member(with: memberId)?.displayName
                ?? before.member(with: memberId)?.displayName
                ?? "Jemand"
            var message = "\(name) hat die Gruppe „\(after.name)“ verlassen."
            if before.adminId == memberId, after.adminId != memberId, let newAdmin = after.admin {
                message += " \(newAdmin.displayName) ist jetzt Admin."
            }
            enqueueNotice(GroupNotice(title: "Mitglied verlassen", message: message))
        }

        if before.adminId != after.adminId,
           departed.isEmpty,
           after.adminId != myId,
           let newAdmin = after.admin {
            enqueueNotice(
                GroupNotice(
                    title: "Neuer Admin",
                    message: "\(newAdmin.displayName) ist jetzt Admin von „\(after.name)“."
                )
            )
        }
    }

    private func enqueueNotice(_ notice: GroupNotice) {
        if presentedNotice == nil {
            presentedNotice = notice
        } else {
            noticeQueue.append(notice)
        }
    }

    private func presentNextNotice() {
        guard presentedNotice == nil, !noticeQueue.isEmpty else { return }
        presentedNotice = noticeQueue.removeFirst()
    }

    private func upsert(_ group: ExpenseGroup) {
        if let index = groups.firstIndex(where: { $0.id == group.id }) {
            groups[index] = group
        } else {
            groups.append(group)
        }
        groups.sort { $0.updatedAt > $1.updatedAt }
    }

    private func archiveLocally(_ groupId: UUID) {
        archivedGroupIds.insert(groupId)
    }

    private func removeLocally(_ groupId: UUID, rememberDeletion: Bool) {
        groups.removeAll { $0.id == groupId }
        archivedGroupIds.remove(groupId)
        if rememberDeletion {
            deletedGroupIds.insert(groupId)
        }
    }

    private func refreshTrustedDeviceIds() {
        let ids = Set(
            groups
                .filter { !archivedGroupIds.contains($0.id) }
                .flatMap { $0.activeMembers.compactMap(\.peerDeviceId) }
        )
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
            archivedGroupIds = Set(persisted.archivedGroupIds ?? [])
            return
        }
        if let decoded = try? JSONDecoder().decode([ExpenseGroup].self, from: data) {
            groups = decoded
        }
    }

    private func persist() {
        let persisted = PersistedStore(
            groups: groups,
            deletedGroupIds: Array(deletedGroupIds),
            archivedGroupIds: Array(archivedGroupIds)
        )
        guard let data = try? JSONEncoder().encode(persisted) else { return }
        try? data.write(to: storageURL, options: [.atomic])
    }
}

private struct PersistedStore: Codable {
    var groups: [ExpenseGroup]
    var deletedGroupIds: [UUID]
    var archivedGroupIds: [UUID]?
}
