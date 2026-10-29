import Foundation

/// Launch-at-login without SMAppService (works for an ad-hoc signed bundle).
enum LaunchAgent {
    static var path: String {
        NSHomeDirectory() + "/Library/LaunchAgents/com.reg4916.dsh-bar.plist"
    }

    static var enabled: Bool {
        FileManager.default.fileExists(atPath: path)
    }

    static func setEnabled(_ on: Bool) {
        if on {
            let directory = NSHomeDirectory() + "/Library/LaunchAgents"
            try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
            let executable = Bundle.main.executablePath ?? CommandLine.arguments[0]
            let plist: [String: Any] = [
                "Label": "com.reg4916.dsh-bar",
                "ProgramArguments": [executable],
                "RunAtLoad": true,
                "KeepAlive": false,
                "ProcessType": "Background",
            ]
            if let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) {
                try? data.write(to: URL(fileURLWithPath: path))
            }
        } else {
            try? FileManager.default.removeItem(atPath: path)
        }
    }
}
