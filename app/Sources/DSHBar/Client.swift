import Foundation
import Darwin

struct BarRuntime: Decodable {
    let origin: String
    let token: String
    let pid: Int32
}

struct BarActive: Decodable {
    let sessionId: String?
    let title: String?
    let state: String?
    let detail: String?
    let model: String?
    let tokens: Int?
}

struct BarStatus: Decodable {
    let schemaVersion: Int?
    let serverId: String?
    let revision: Int?
    let generatedAt: Double?
    let active: BarActive?
}

enum ClientError: Error, CustomStringConvertible {
    case noRuntime
    case hostGone
    case badRuntime
    case forbidden
    case network(String)
    case decode(String)

    var description: String {
        switch self {
        case .noRuntime: return "DSH runtime not found"
        case .hostGone: return "DSH is not running"
        case .badRuntime: return "DSH runtime file is invalid"
        case .forbidden: return "DSH rejected the token"
        case .network(let message): return "network: " + message
        case .decode(let message): return "decode: " + message
        }
    }
}

enum RuntimeStore {
    static func path() -> String {
        if let override = ProcessInfo.processInfo.environment["DSH_BAR_RUNTIME_FILE"], !override.isEmpty {
            return override
        }
        return NSString(string: "~/.dsh/dsh-bar/runtime.json").expandingTildeInPath
    }

    static func load() -> BarRuntime? {
        guard let data = FileManager.default.contents(atPath: path()) else { return nil }
        return try? JSONDecoder().decode(BarRuntime.self, from: data)
    }

    static func hostAlive(pid: Int32) -> Bool {
        kill(pid, 0) == 0
    }
}

final class BarClient {
    private let session: URLSession
    private var lastServerId: String?

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 8
        session = URLSession(configuration: config)
    }

    /// Re-reads runtime.json on every poll: Desktop starts the Host with
    /// --port 0, so the origin changes whenever DSH restarts.
    func poll(completion: @escaping (Result<BarSnapshot, ClientError>) -> Void) {
        guard let runtime = RuntimeStore.load() else {
            completion(.failure(.noRuntime))
            return
        }
        guard RuntimeStore.hostAlive(pid: runtime.pid) else {
            completion(.failure(.hostGone))
            return
        }
        guard let url = URL(string: runtime.origin + "/dsh-bar/status") else {
            completion(.failure(.badRuntime))
            return
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer " + runtime.token, forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 8
        session.dataTask(with: request) { [weak self] data, response, error in
            if let error {
                completion(.failure(.network(error.localizedDescription)))
                return
            }
            guard let http = response as? HTTPURLResponse else {
                completion(.failure(.network("no response")))
                return
            }
            if http.statusCode == 403 {
                completion(.failure(.forbidden))
                return
            }
            guard http.statusCode == 200, let data else {
                completion(.failure(.network("HTTP " + String(http.statusCode))))
                return
            }
            do {
                let status = try JSONDecoder().decode(BarStatus.self, from: data)
                if let known = self?.lastServerId, known != status.serverId {
                    self?.lastServerId = status.serverId
                }
                self?.lastServerId = status.serverId
                completion(.success(Self.snapshot(from: status)))
            } catch {
                completion(.failure(.decode(error.localizedDescription)))
            }
        }.resume()
    }

    static func snapshot(from status: BarStatus) -> BarSnapshot {
        let active = status.active
        let state = BarState(rawValue: active?.state ?? "idle") ?? .idle
        return BarSnapshot(
            state: state,
            title: active?.title ?? "No active session",
            detail: active?.detail ?? "",
            model: active?.model ?? "",
            tokens: active?.tokens ?? 0,
            cost: "—",
            approvals: state == .approval ? 1 : 0
        )
    }
}
