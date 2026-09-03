import Combine
import Foundation
import MultipeerConnectivity
import UIKit

@MainActor
final class MultipeerService: NSObject, ObservableObject {
    static let serviceType = "splitshare-p2p"
    private static let peerIDKey = "splitshare.peerID"

    @Published private(set) var profile: PeerProfile
    @Published private(set) var connectedPeers: [MCPeerID] = []
    @Published private(set) var discoveredPeers: [MCPeerID] = []
    @Published private(set) var isAdvertising = false
    @Published private(set) var isBrowsing = false
    @Published var lastError: String?

    let deviceId: String

    var onEnvelopeReceived: ((SyncEnvelope, MCPeerID) -> Void)?
    var onPeerConnected: ((MCPeerID) -> Void)?

    private var myPeerID: MCPeerID
    private var session: MCSession
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var deviceIdByPeer: [MCPeerID: String] = [:]
    private var trustedDeviceIds: Set<String> = []
    private var pausedDeviceIds: Set<String> = []

    override init() {
        let storedDeviceId = UserDefaults.standard.string(forKey: "splitshare.deviceId") ?? UUID().uuidString
        UserDefaults.standard.set(storedDeviceId, forKey: "splitshare.deviceId")
        deviceId = storedDeviceId

        let loadedProfile: PeerProfile
        let createdNewProfile: Bool
        if let data = UserDefaults.standard.data(forKey: "splitshare.profile"),
           let savedProfile = try? JSONDecoder().decode(PeerProfile.self, from: data) {
            loadedProfile = savedProfile
            createdNewProfile = false
        } else {
            loadedProfile = PeerProfile(displayName: UIDevice.current.name)
            createdNewProfile = true
        }
        profile = loadedProfile

        myPeerID = Self.loadOrCreatePeerID(displayName: loadedProfile.displayName)
        session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
        super.init()
        session.delegate = self
        if createdNewProfile {
            persistProfile()
        }
    }

    var identityPayload: QRIdentity.Payload {
        QRIdentity.payload(profileId: profile.id, deviceId: deviceId, displayName: profile.displayName)
    }

    func updateDisplayName(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let previous = profile.displayName
        profile.displayName = trimmed
        persistProfile()
        if previous != trimmed {
            rebuildSession(displayName: trimmed)
        }
        broadcastProfile(to: session.connectedPeers.filter { isTrusted($0) })
    }

    func startNetworking() {
        startAdvertising()
        startBrowsing()
    }

    func stopNetworking() {
        stopAdvertising()
        stopBrowsing()
    }

    func setTrustedDeviceIds(_ ids: Set<String>) {
        trustedDeviceIds = ids.subtracting([deviceId])
        connectToTrustedDiscoveredPeers()
    }

    func deviceId(for peer: MCPeerID) -> String? {
        if let id = deviceIdByPeer[peer] { return id }
        return deviceIdByPeer.first(where: { $0.key == peer || $0.key.displayName == peer.displayName })?.value
    }

    func rememberDeviceId(_ id: String, for peer: MCPeerID) {
        deviceIdByPeer[peer] = id
    }

    func isTrusted(_ peer: MCPeerID) -> Bool {
        guard let id = deviceId(for: peer) else { return false }
        return trustedDeviceIds.contains(id)
    }

    func isConnected(_ peer: MCPeerID) -> Bool {
        if session.connectedPeers.contains(peer) { return true }
        if let id = deviceId(for: peer) {
            return session.connectedPeers.contains { deviceId(for: $0) == id }
        }
        return false
    }

    func startAdvertising() {
        guard !isAdvertising else { return }
        advertiser?.stopAdvertisingPeer()
        advertiser = MCNearbyServiceAdvertiser(
            peer: myPeerID,
            discoveryInfo: ["deviceId": deviceId],
            serviceType: Self.serviceType
        )
        advertiser?.delegate = self
        advertiser?.startAdvertisingPeer()
        isAdvertising = true
    }

    func stopAdvertising() {
        advertiser?.stopAdvertisingPeer()
        advertiser = nil
        isAdvertising = false
    }

    func startBrowsing() {
        guard !isBrowsing else { return }
        browser?.stopBrowsingForPeers()
        browser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: Self.serviceType)
        browser?.delegate = self
        browser?.startBrowsingForPeers()
        isBrowsing = true
    }

    func stopBrowsing() {
        browser?.stopBrowsingForPeers()
        browser = nil
        isBrowsing = false
        discoveredPeers.removeAll()
    }

    func invite(_ peer: MCPeerID) {
        if let id = deviceId(for: peer) {
            pausedDeviceIds.remove(id)
        }
        sendInvite(peer)
    }

    private func sendInvite(_ peer: MCPeerID) {
        guard let browser else { return }
        browser.invitePeer(peer, to: session, withContext: nil, timeout: 20)
    }

    func disconnect(from peer: MCPeerID) {
        if let id = deviceId(for: peer) {
            pausedDeviceIds.insert(id)
        }

        if isConnected(peer) {
            session.disconnect()
            refreshConnectedPeers()
            connectToTrustedDiscoveredPeers()
        } else {
            session.cancelConnectPeer(peer)
        }
    }

    func send(_ envelope: SyncEnvelope, to peers: [MCPeerID]? = nil) {
        let targets = peers ?? session.connectedPeers
        guard !targets.isEmpty else { return }

        do {
            let data = try JSONEncoder().encode(envelope)
            try session.send(data, toPeers: targets, with: .reliable)
        } catch {
            lastError = "Senden fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    func broadcastProfile(to peers: [MCPeerID]? = nil) {
        let targets = peers ?? session.connectedPeers.filter { isTrusted($0) }
        guard !targets.isEmpty else { return }
        guard let payload = try? JSONEncoder().encode(ProfilePayload(profile: profile)) else { return }
        let envelope = SyncEnvelope(
            senderDeviceId: deviceId,
            type: .profile,
            payload: payload
        )
        send(envelope, to: targets)
    }

    private func persistProfile() {
        if let data = try? JSONEncoder().encode(profile) {
            UserDefaults.standard.set(data, forKey: "splitshare.profile")
        }
    }

    private func refreshConnectedPeers() {
        connectedPeers = session.connectedPeers
    }

    private func connectToTrustedDiscoveredPeers() {
        for peer in discoveredPeers where shouldAutoInvite(peer) && !isConnected(peer) {
            sendInvite(peer)
        }
    }

    private func shouldAutoInvite(_ peer: MCPeerID) -> Bool {
        guard isTrusted(peer), let peerDeviceId = deviceId(for: peer) else { return false }
        if pausedDeviceIds.contains(peerDeviceId) { return false }
        return !isConnected(peer)
    }

    private func handleReceivedData(_ data: Data, from peer: MCPeerID) {
        guard let envelope = try? JSONDecoder().decode(SyncEnvelope.self, from: data) else { return }
        rememberDeviceId(envelope.senderDeviceId, for: peer)
        onEnvelopeReceived?(envelope, peer)
    }

    private func rebuildSession(displayName: String) {
        stopNetworking()
        session.disconnect()
        myPeerID = MCPeerID(displayName: Self.peerDisplayName(displayName))
        Self.persistPeerID(myPeerID)
        session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        connectedPeers = []
        startNetworking()
    }

    private static func loadOrCreatePeerID(displayName: String) -> MCPeerID {
        let clipped = peerDisplayName(displayName)
        if let data = UserDefaults.standard.data(forKey: peerIDKey),
           let stored = try? NSKeyedUnarchiver.unarchivedObject(ofClass: MCPeerID.self, from: data),
           stored.displayName == clipped {
            return stored
        }
        let peerID = MCPeerID(displayName: clipped)
        persistPeerID(peerID)
        return peerID
    }

    private static func persistPeerID(_ peerID: MCPeerID) {
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: peerID, requiringSecureCoding: true) {
            UserDefaults.standard.set(data, forKey: peerIDKey)
        }
    }

    private static func peerDisplayName(_ name: String) -> String {
        var clipped = name.trimmingCharacters(in: .whitespacesAndNewlines)
        while clipped.utf8.count > 63, !clipped.isEmpty {
            clipped.removeLast()
        }
        return clipped.isEmpty ? "SplitShare" : clipped
    }
}

extension MultipeerService: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in
            refreshConnectedPeers()
            if state == .connected {
                onPeerConnected?(peerID)
                if isTrusted(peerID) {
                    broadcastProfile(to: [peerID])
                }
            }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        Task { @MainActor in
            handleReceivedData(data, from: peerID)
        }
    }

    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}

    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}

    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

extension MultipeerService: MCNearbyServiceAdvertiserDelegate {
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        Task { @MainActor in
            invitationHandler(true, session)
        }
    }

    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        Task { @MainActor in
            lastError = error.localizedDescription
            isAdvertising = false
        }
    }
}

extension MultipeerService: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        Task { @MainActor in
            if let discoveredId = info?["deviceId"] {
                deviceIdByPeer[peerID] = discoveredId
            }
            if !discoveredPeers.contains(peerID) {
                discoveredPeers.append(peerID)
            }
            if shouldAutoInvite(peerID) {
                browser.invitePeer(peerID, to: session, withContext: nil, timeout: 20)
            }
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task { @MainActor in
            discoveredPeers.removeAll { $0 == peerID }
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        Task { @MainActor in
            lastError = error.localizedDescription
            isBrowsing = false
        }
    }
}
