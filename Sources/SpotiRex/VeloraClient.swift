import Foundation
import Security

protocol VeloraTokenStorage {
    func load() -> String?
    func save(_ token: String)
    func delete()
}

struct KeychainVeloraTokenStore: VeloraTokenStorage {
    private static let service = "com.crickdevs.spotirex.velora"
    private static let account = "read-token"

    func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func save(_ token: String) {
        delete()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: Data(token.utf8)
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

@MainActor
final class VeloraClient: ObservableObject {
    @Published private(set) var status = "Checking Velora…"
    @Published private(set) var isConnected = false
    @Published private(set) var isAuthorizing = false

    private let base: URL
    private let session: URLSession
    private let eventsEnabled: Bool
    private let tokenStore: any VeloraTokenStorage
    private var token: String?
    private var socket: URLSessionWebSocketTask?
    private var socketLoop: Task<Void, Never>?
    var onUpdate: (() -> Void)?

    init(base: URL = URL(string: "http://127.0.0.1:39031")!, session: URLSession = .shared,
         tokenStore: any VeloraTokenStorage = KeychainVeloraTokenStore(), eventsEnabled: Bool = true) {
        self.base = base
        self.session = session
        self.tokenStore = tokenStore
        self.token = tokenStore.load()
        self.eventsEnabled = eventsEnabled
    }

    func disconnect() {
        socketLoop?.cancel()
        socket?.cancel(with: .normalClosure, reason: nil)
        socket = nil
        socketLoop = nil
        token = nil
        tokenStore.delete()
        isConnected = false
        status = "Not connected"
        onUpdate?()
    }

    func read() async -> LocalReadResult {
        guard let token else {
            do {
                let (_, response) = try await session.data(from: base.appendingPathComponent("health"))
                status = (response as? HTTPURLResponse)?.statusCode == 200 ? "Approval needed" : "Local API unavailable"
            } catch { status = "Local API unavailable" }
            isConnected = false
            return LocalReadResult(track: nil, status: status)
        }
        var request = URLRequest(url: base.appendingPathComponent("current-track"))
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 4
        do {
            let (data, response) = try await session.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if code == 401 || code == 403 {
                disconnect()
                status = "Access revoked — reconnect in Settings"
                return LocalReadResult(track: nil, status: status)
            }
            guard code == 200 else { throw URLError(.badServerResponse) }
            let payload = try JSONDecoder().decode(CurrentTrackResponse.self, from: data)
            isConnected = true
            status = payload.track?.is_playing == true ? "Playing" : "Not playing"
            connectEventsIfNeeded(token: token)
            guard let item = payload.track, item.is_playing == true,
                  let title = item.title, !title.isEmpty else {
                return LocalReadResult(track: nil, status: status)
            }
            let urlString = item.cover_url ?? item.thumbnail_url ?? ""
            let url = URL(string: urlString)
            return LocalReadResult(track: TrackSnapshot(
                source: .velora,
                id: item.id ?? title + (item.artist ?? ""),
                title: title,
                artists: item.artist ?? "",
                album: item.album ?? "",
                artworkURL: url,
                isPlaying: true
            ), status: status)
        } catch {
            isConnected = false
            status = "Local API unavailable"
            socket?.cancel(with: .goingAway, reason: nil)
            socket = nil
            return LocalReadResult(track: nil, status: status)
        }
    }

    func requestReadAccess() async {
        guard !isAuthorizing else { return }
        isAuthorizing = true
        defer { isAuthorizing = false }
        do {
            var request = URLRequest(url: base.appendingPathComponent("register"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "app": ["name": "SpotiRex", "description": "Read-only now-playing display", "developer": "CrickDevs"],
                "permissions": ["read"]
            ])
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 202 else { throw URLError(.badServerResponse) }
            let pending = try JSONDecoder().decode(RegistrationResponse.self, from: data)
            status = "Approve SpotiRex in Velora"
            for _ in 0..<90 {
                try await Task.sleep(for: .seconds(2))
                var components = URLComponents(url: base.appendingPathComponent("request-status"), resolvingAgainstBaseURL: false)!
                components.queryItems = [URLQueryItem(name: "request_id", value: pending.request_id)]
                let (statusData, _) = try await session.data(from: components.url!)
                let approval = try JSONDecoder().decode(ApprovalResponse.self, from: statusData)
                if approval.status == "denied" {
                    status = "Access denied in Velora"
                    return
                }
                if approval.status == "approved", let approvedToken = approval.access_token {
                    token = approvedToken
                    tokenStore.save(approvedToken)
                    status = "Connected"
                    onUpdate?()
                    return
                }
            }
            status = "Approval timed out — try again"
        } catch {
            status = "Unable to connect to Velora"
        }
    }

    private func connectEventsIfNeeded(token: String) {
        guard eventsEnabled else { return }
        guard socket == nil else { return }
        var components = URLComponents(string: "ws://127.0.0.1:39031/ws")!
        components.queryItems = [URLQueryItem(name: "access_token", value: token)]
        let task = session.webSocketTask(with: components.url!)
        socket = task
        task.resume()
        socketLoop = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    let message = try await task.receive()
                    guard let self else { break }
                    switch message {
                    case .string(let value):
                        if value.contains("track_changed") || value.contains("playback_state_changed") { self.onUpdate?() }
                    case .data: self.onUpdate?()
                    @unknown default: break
                    }
                } catch { break }
            }
            if self?.socket === task { self?.socket = nil }
        }
    }
}

private struct CurrentTrackResponse: Decodable { let track: VeloraTrack? }
private struct VeloraTrack: Decodable {
    let id: String?
    let title: String?
    let artist: String?
    let album: String?
    let cover_url: String?
    let thumbnail_url: String?
    let is_playing: Bool?
}
private struct RegistrationResponse: Decodable { let request_id: String }
private struct ApprovalResponse: Decodable { let status: String; let access_token: String? }
