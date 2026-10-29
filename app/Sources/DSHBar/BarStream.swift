import Foundation

/// Long-lived SSE connection to /dsh-bar/events. The existing 0.8 s polling
/// stays as a safety net; this only makes state changes arrive immediately.
final class BarStream: NSObject, URLSessionDataDelegate {
    var onStatus: ((BarStatus) -> Void)?
    var onDisconnect: ((ClientError) -> Void)?

    private var session: URLSession!
    private var task: URLSessionDataTask?
    private var buffer = Data()
    private var stopped = true

    override init() {
        super.init()
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 3600
        config.timeoutIntervalForResource = 3600
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    func start() {
        stop()
        stopped = false
        guard let runtime = RuntimeStore.load() else {
            onDisconnect?(.noRuntime)
            return
        }
        guard RuntimeStore.hostAlive(pid: runtime.pid) else {
            onDisconnect?(.hostGone)
            return
        }
        guard let url = URL(string: runtime.origin + "/dsh-bar/events") else {
            onDisconnect?(.badRuntime)
            return
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer " + runtime.token, forHTTPHeaderField: "Authorization")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 3600
        buffer.removeAll()
        let task = session.dataTask(with: request)
        self.task = task
        task.resume()
    }

    func stop() {
        stopped = true
        task?.cancel()
        task = nil
        buffer.removeAll()
    }

    // MARK: - URLSessionDataDelegate

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard dataTask === task, !stopped else { return }
        buffer.append(data)
        let separator = Data("\n\n".utf8)
        while let range = buffer.range(of: separator) {
            let frame = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
            buffer.removeSubrange(buffer.startIndex..<range.upperBound)
            handle(frame)
        }
    }

    private func handle(_ frame: Data) {
        guard let text = String(data: frame, encoding: .utf8) else { return }
        var payload: [String] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("data:") {
                payload.append(String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces))
            }
        }
        guard !payload.isEmpty, let data = payload.joined(separator: "\n").data(using: .utf8) else { return }
        guard let status = try? JSONDecoder().decode(BarStatus.self, from: data) else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.stopped else { return }
            self.onStatus?(status)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard task === self.task else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.stopped else { return }
            self.onDisconnect?(.network(error?.localizedDescription ?? "stream ended"))
        }
    }
}
