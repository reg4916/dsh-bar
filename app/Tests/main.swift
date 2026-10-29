import Foundation

var failures = 0

func check(_ condition: Bool, _ name: String) {
    if condition {
        print("ok - " + name)
    } else {
        failures += 1
        print("FAIL - " + name)
    }
}

func equal<T: Equatable>(_ got: T, _ want: T, _ name: String) {
    check(got == want, name + " (got " + String(describing: got) + ", want " + String(describing: want) + ")")
}

// MARK: - status decoding

let statusJSON = """
{
  "schemaVersion": 1,
  "serverId": "srv",
  "revision": 4,
  "active": {"sessionId": "s1", "title": "Session one", "state": "approval", "detail": "detail", "model": "deepseek-flash", "tokens": 42},
  "approvals": [
    {"id": "a1", "sessionId": "s1", "toolName": "bash", "reason": "write file"},
    {"id": "a2", "sessionId": "s2", "toolName": "write"}
  ],
  "questions": [
    {"id": "g1", "sessionId": "s1", "title": "Session one", "questions": [
      {"id": "q1", "question": "Pick one", "header": "Choice", "detail": "detail", "multiSelect": false,
       "options": [{"label": "A"}, {"label": "B", "description": "bee"}]}
    ]}
  ],
  "rows": [
    {"id": "s1", "title": "Session one", "state": "thinking", "busy": true, "approval": {"id": "a1", "toolName": "bash"}},
    {"id": "s2", "title": "Session two", "state": "idle", "busy": false, "ask": {"id": "g1", "questions": []}}
  ]
}
"""

do {
    let status = try JSONDecoder().decode(BarStatus.self, from: Data(statusJSON.utf8))
    let snapshot = BarClient.snapshot(from: status)
    equal(status.approvals?.count, 2, "decodes every approval")
    equal(snapshot.sessions.map(\.id), ["s1", "s2"], "keeps row order")
    equal(snapshot.sessions.filter(\.waiting).count, 2, "marks waiting sessions")
    equal(snapshot.questionGroups.count, 1, "decodes question groups")
    equal(snapshot.questionGroups.first?.questions.first?.options?.count, 2, "decodes options")
    equal(snapshot.questionGroups.first?.questions.first?.options?.last?.description, "bee", "decodes option description")
    equal(snapshot.activeSessionId, "s1", "active session id")
} catch {
    failures += 1
    print("FAIL - status decoding threw " + String(describing: error))
}

// MARK: - answer batch rules

let group = BarQuestionGroup(id: "g1", sessionId: "s1", title: "T", questions: [
    BarQuestion(id: "q1", question: "Single", detail: nil, header: nil,
                options: [BarOption(label: "A", description: nil), BarOption(label: "B", description: nil)],
                multiSelect: false),
    BarQuestion(id: "q2", question: "Multi", detail: nil, header: nil,
                options: [BarOption(label: "X", description: nil)], multiSelect: true),
])

let single = AnswerBatch.build(group, choices: [
    AnswerBatch.Choice(selected: ["A"], custom: ""),
    AnswerBatch.Choice(selected: ["X"], custom: ""),
])
equal(single[0]["selected"] as? [String], ["A"], "single select keeps labels")
check(single[0]["custom"] == nil, "no empty custom field")
equal(single[1]["selected"] as? [String], ["X"], "multi select keeps labels")

let customSingle = AnswerBatch.build(group, choices: [
    AnswerBatch.Choice(selected: ["A"], custom: "  mine  "),
    AnswerBatch.Choice(selected: ["X"], custom: "  extra "),
])
equal(customSingle[0]["selected"] as? [String], [], "custom replaces single-select labels")
equal(customSingle[0]["custom"] as? String, "mine", "custom is trimmed")
equal(customSingle[1]["selected"] as? [String], ["X"], "multi-select keeps labels with custom")
equal(customSingle[1]["custom"] as? String, "extra", "multi-select carries custom")

let short = AnswerBatch.build(group, choices: [AnswerBatch.Choice(selected: [], custom: "")])
equal(short.count, 2, "missing choices still produce every question")
equal(short[1]["selected"] as? [String], [], "missing choice is an empty selection")

// MARK: - version comparison

check(UpdateChecker.isNewer("0.2.0", than: "0.1.1"), "0.2.0 > 0.1.1")
check(UpdateChecker.isNewer("0.1.10", than: "0.1.9"), "numeric comparison, not lexical")
check(!UpdateChecker.isNewer("0.2.0", than: "0.2.0"), "equal is not newer")
check(!UpdateChecker.isNewer("0.1.9", than: "0.2.0"), "older is not newer")

if failures == 0 {
    print("native tests: all passed")
    exit(0)
} else {
    print("native tests: " + String(failures) + " failed")
    exit(1)
}
