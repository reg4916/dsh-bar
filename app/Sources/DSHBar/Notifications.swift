import AppKit
import UserNotifications

/// Local notifications for approvals, questions and turn results.
/// Approval banners deliberately never offer "Approve": the tool arguments are
/// not visible there, so approving stays a deliberate popover action.
final class BarNotifier: NSObject, UNUserNotificationCenterDelegate {
    var onDenyApproval: ((String) -> Void)?
    var onOpen: ((String?) -> Void)?

    private let alerts = AlertPresenter()
    private var notifiedApprovals = Set<String>()
    private var notifiedQuestions = Set<String>()
    private var lastState: BarState = .idle
    private var lastSession: String?
    private var ready = false

    func start() {
        alerts.onOpen = { [weak self] in self?.onOpen?(nil) }
        alerts.onDeny = { [weak self] id in self?.onDenyApproval?(id) }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.setNotificationCategories(categories())
        // A background-only (LSUIElement) app cannot present the system prompt
        // before it has an active run loop; without this the request is denied
        // immediately with "Notifications are not allowed for this application".
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            NSApp.activate(ignoringOtherApps: true)
            center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            center.getNotificationSettings { settings in
                DispatchQueue.main.async {
                    self?.ready = granted
                    UserDefaults.standard.set(granted, forKey: "notifGranted")
                    UserDefaults.standard.set(settings.authorizationStatus.rawValue, forKey: "notifStatus")
                    UserDefaults.standard.set(error?.localizedDescription ?? "", forKey: "notifError")
                }
            }
            }
        }
    }

    private func categories() -> Set<UNNotificationCategory> {
        let open = UNNotificationAction(identifier: "open", title: L("action.open"), options: [.foreground])
        let deny = UNNotificationAction(identifier: "deny", title: L("action.deny"), options: [.destructive])
        let approval = UNNotificationCategory(identifier: "approval", actions: [open, deny], intentIdentifiers: [], options: [])
        let question = UNNotificationCategory(identifier: "question", actions: [open], intentIdentifiers: [], options: [])
        return [approval, question]
    }

    /// Called after every status poll. Deduplicates by held id, so a poll storm
    /// cannot produce a notification storm.
    func sync(_ snapshot: BarSnapshot, enabled: Bool) {
        guard enabled else {
            lastState = snapshot.state
            lastSession = snapshot.activeSessionId
            return
        }
        guard ready else { return }

        for approval in snapshot.approvalItems where !notifiedApprovals.contains(approval.id) {
            notifiedApprovals.insert(approval.id)
            let body = approval.reason ?? snapshot.title
            if ready {
                post(title: Lf("notify.approval.title", approval.toolName), body: body,
                     category: "approval",
                     info: ["approvalId": approval.id, "sessionId": snapshot.activeSessionId ?? ""],
                     id: "approval-" + approval.id)
            } else {
                alerts.approval(id: approval.id, tool: approval.toolName, reason: approval.reason)
            }
        }
        for group in snapshot.questionGroups where !notifiedQuestions.contains(group.id) {
            notifiedQuestions.insert(group.id)
            let text = group.questions.first?.question ?? snapshot.title
            if ready {
                post(title: Lf("notify.question.title", group.title ?? snapshot.title), body: text,
                     category: "question",
                     info: ["sessionId": group.sessionId ?? snapshot.activeSessionId ?? ""],
                     id: "question-" + group.id)
            } else {
                alerts.question(title: group.title ?? snapshot.title, text: text)
            }
        }
        if snapshot.state == .done && lastState != .done {
            if ready {
                post(title: L("notify.done.title"), body: snapshot.title, category: "none",
                     info: ["sessionId": snapshot.activeSessionId ?? ""], id: "done-" + UUID().uuidString)
            } else {
                alerts.done(title: snapshot.title)
            }
        }
        if snapshot.state == .error && lastState != .error {
            let body = snapshot.detail.isEmpty ? snapshot.title : snapshot.detail
            if ready {
                post(title: L("notify.error.title"), body: body, category: "none",
                     info: ["sessionId": snapshot.activeSessionId ?? ""], id: "error-" + UUID().uuidString)
            } else {
                alerts.error(body)
            }
        }
        lastState = snapshot.state
        lastSession = snapshot.activeSessionId
    }

    private func post(title: String, body: String, category: String, info: [String: Any], id: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = category
        content.userInfo = info
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        if response.actionIdentifier == "deny", let id = info["approvalId"] as? String {
            onDenyApproval?(id)
        } else {
            onOpen?(info["sessionId"] as? String)
        }
        completionHandler()
    }
}
