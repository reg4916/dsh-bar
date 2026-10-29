import AppKit
import UserNotifications

/// Local notifications for approvals, questions and turn results.
/// Approval banners deliberately never offer "Approve": the tool arguments are
/// not visible there, so approving stays a deliberate popover action.
final class BarNotifier: NSObject, UNUserNotificationCenterDelegate {
    var onDenyApproval: ((String) -> Void)?
    var onOpen: ((String?) -> Void)?

    private var notifiedApprovals = Set<String>()
    private var notifiedQuestions = Set<String>()
    private var lastState: BarState = .idle
    private var lastSession: String?
    private var ready = false

    func start() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.setNotificationCategories(categories())
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
            DispatchQueue.main.async { self?.ready = granted }
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
            post(title: Lf("notify.approval.title", approval.toolName), body: body,
                 category: "approval",
                 info: ["approvalId": approval.id, "sessionId": snapshot.activeSessionId ?? ""],
                 id: "approval-" + approval.id)
        }
        for group in snapshot.questionGroups where !notifiedQuestions.contains(group.id) {
            notifiedQuestions.insert(group.id)
            let text = group.questions.first?.question ?? snapshot.title
            post(title: Lf("notify.question.title", group.title ?? snapshot.title), body: text,
                 category: "question",
                 info: ["sessionId": group.sessionId ?? snapshot.activeSessionId ?? ""],
                 id: "question-" + group.id)
        }
        if snapshot.state == .done && lastState != .done {
            post(title: L("notify.done.title"), body: snapshot.title, category: "none",
                 info: ["sessionId": snapshot.activeSessionId ?? ""], id: "done-" + UUID().uuidString)
        }
        if snapshot.state == .error && lastState != .error {
            post(title: L("notify.error.title"), body: snapshot.detail.isEmpty ? snapshot.title : snapshot.detail,
                 category: "none",
                 info: ["sessionId": snapshot.activeSessionId ?? ""], id: "error-" + UUID().uuidString)
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
