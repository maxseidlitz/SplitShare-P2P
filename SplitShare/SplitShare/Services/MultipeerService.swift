import Combine
import Foundation
import MultipeerConnectivity
import UIKit

@MainActor
final class MultipeerService: NSObject, ObservableObject {
    static let serviceType = "splitshare-p2p"

    @Published private(set) var profile: PeerProfile
    @Published private(set) var connectedPeers: [MCPeerID] = []
    @Published private(set) var discoveredPeers: [MCPeerID] = []
    @Published private(set) var isAdvertising = false
    @Published private(set) var isBrowsing = false
    @Published var lastError: String?

    var onEnvelopeReceived: ((SyncEnvelope, MCPeerID) -> Void)?
    var onPeerConnected: ((MCPeerID) -> Void)?

    private let deviceId: String
    private let myPeerID: MCPeerID
    private let session: MCSession
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?

    override init() {
        let storedDeviceId = UserDefaults.standard.string(forKey: "splitshare.deviceId") ?? UUID().uuidString
        UserDefaults.standard.set(storedDeviceId, forKey: "splitshare.deviceId")
        deviceId = storedDeviceId

        if let data = UserDefaults.standard.data(forKey: "splitshare.profile"),
           let savedProfile = try? JSONDecoder().decode(PeerProfile.self, from: data) {
            profile = savedProfile
        } else {
            let defaultName = UIDevice.current.name
            profile = PeerProfile(displayName: defaultName)
        }

        myPeerID = MCPeerID(displayName: profile.displayName)
        session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
        super.init()
        session.delegate = self
    }

    func updateDisplayName(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        profile.displayName = trimmed
        persistProfile()
        broadcastProfile()
    }

    func startNetworking() {
        startAdvertising()
        startBrowsing()
    }

    func stopNetworking() {
        stopAdvertising()
        stopBrowsing()
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
        guard let browser else { return }
        browser.invitePeer(peer, to: session, withContext: nil, timeout: 20)
    }

    func disconnect(from peer: MCPeerID) {
        session.cancelConnectPeer(peer)
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

    func broadcastProfile() {
        guard let payload = try? JSONEncoder().encode(ProfilePayload(profile: profile)) else { return }
        let envelope = SyncEnvelope(
            senderDeviceId: deviceId,
            type: .profile,
            payload: payload
        )
        send(envelope)
    }

    private func persistProfile() {
        if let data = try? JSONEncoder().encode(profile) {
            UserDefaults.standard.set(data, forKey: "splitshare.profile")
        }
    }

    private func refreshConnectedPeers() {
        connectedPeers = session.connectedPeers
    }

    private func handleReceivedData(_ data: Data, from peer: MCPeerID) {
        guard let envelope = try? JSONDecoder().decode(SyncEnvelope.self, from: data) else { return }
        onEnvelopeReceived?(envelope, peer)
    }
}

extension MultipeerService: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in
            refreshConnectedPeers()
            if state == .connected {
                onPeerConnected?(peerID)
                broadcastProfile()
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
            if !discoveredPeers.contains(where: { $0.displayName == peerID.displayName }) {
                discoveredPeers.append(peerID)
            }
            browser.invitePeer(peerID, to: session, withContext: nil, timeout: 20)
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task { @MainActor in
            discoveredPeers.removeAll { $0.displayName == peerID.displayName }
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        Task { @MainActor in
            lastError = error.localizedDescription
            isBrowsing = false
        }
    }
}
