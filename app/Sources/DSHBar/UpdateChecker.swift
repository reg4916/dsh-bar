import Foundation

/// Lightweight release check against GitHub. No Sparkle, no signing keys:
/// it only tells the user a newer release exists and opens its page.
enum UpdateChecker {
    static let repo = "reg4916/dsh-bar"
    static let releasesURL = URL(string: "https://github.com/reg4916/dsh-bar/releases/latest")!

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    /// Calls back with the newer tag (e.g. "0.2.0") or nil.
    static func check(_ completion: @escaping (String?) -> Void) {
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else {
            completion(nil)
            return
        }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10
        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            let newer = isNewer(latest, than: currentVersion)
            DispatchQueue.main.async { completion(newer ? latest : nil) }
        }.resume()
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0.filter(\.isNumber)) ?? 0 }
        let b = current.split(separator: ".").map { Int($0.filter(\.isNumber)) ?? 0 }
        for index in 0..<max(a.count, b.count) {
            let left = index < a.count ? a[index] : 0
            let right = index < b.count ? b[index] : 0
            if left != right { return left > right }
        }
        return false
    }
}
