/**
 * Incremental state fold + approval/question holding for the menu bar.
 *
 * Deliberately NOT session.snapshotEvents(): that API is deprecated in 0.2.1.
 * We listen to ctx.on('session/event') and keep only the fields the icon needs.
 */
import { randomUUID } from "node:crypto";

const FAILED_KINDS = new Set(["error", "blocked", "max-tokens"]);
const DONE_TTL_MS = 6_000;

const STATE_PRIORITY = { approval: 0, error: 1, tool: 2, thinking: 3, done: 4, idle: 5 };

export class Board {
  constructor(ctx, serverId) {
    this.ctx = ctx;
    this.serverId = serverId;
    this.fold = new Map();
    this.pending = new Map();
    this.focus = undefined;
    this.revision = 0;
    this.listeners = new Set();
  }

  touch() {
    this.revision += 1;
    for (const listener of this.listeners) {
      try {
        listener();
      } catch {
        /* a broken subscriber must not break the fold */
      }
    }
  }

  subscribe(listener) {
    this.listeners.add(listener);
    return () => {
      this.listeners.delete(listener);
    };
  }

  row(sessionId) {
    let row = this.fold.get(sessionId);
    if (row === undefined) {
      row = {
        lastTurn: undefined,
        pendingTools: new Set(),
        lastTool: undefined,
        lastError: undefined,
        startedAt: undefined,
        model: undefined,
      };
      this.fold.set(sessionId, row);
    }
    return row;
  }

  forget(sessionId) {
    this.fold.delete(sessionId);
    for (const [id, held] of this.pending) {
      if (held.sessionId === sessionId) this.pending.delete(id);
    }
    this.touch();
  }

  onSessionEvent(session, event) {
    const row = this.row(session.id);
    const data = event?.data ?? {};
    const at = typeof event?.time === "number" ? event.time : Date.now();
    switch (event?.type) {
      case "turn/start":
        row.startedAt = at;
        row.lastError = undefined;
        row.pendingTools.clear();
        break;
      case "tool/call":
        if (data.callId) row.pendingTools.add(String(data.callId));
        row.lastTool = { name: String(data.name ?? "tool"), callId: data.callId, at };
        break;
      case "tool/result":
        if (data.callId) row.pendingTools.delete(String(data.callId));
        else row.pendingTools.clear();
        break;
      case "turn/end": {
        row.startedAt = undefined;
        row.pendingTools.clear();
        const kind = String(data.reason?.kind ?? "completed");
        row.lastTurn = { at, kind, failed: FAILED_KINDS.has(kind) };
        break;
      }
      case "model/selection":
        row.model = data.lastUsed?.model ?? data.model ?? row.model;
        break;
      case "user/message":
        if (data.source === "user") row.lastError = undefined;
        break;
      default:
        break;
    }
    this.touch();
  }

  onAgentError(sessionId, error) {
    if (!sessionId) return;
    const row = this.row(sessionId);
    const message = String(error?.message ?? error ?? "agent error");
    row.lastError = { at: Date.now(), message: message.slice(0, 200) };
    this.touch();
  }

  isChild(sessionId) {
    try {
      const session = this.ctx.sessions?.get?.(sessionId);
      return session?.header?.origin === "subagent";
    } catch {
      return false;
    }
  }

  /** Hold a tool approval so the menu bar can answer it. Child sessions are
   *  skipped: background subagents raise sandbox escalations that are not the
   *  user's decision and would turn the icon red for no reason. */
  holdApproval(request, next) {
    const sessionId = String(request?.agent?.id ?? "");
    if (!sessionId || this.isChild(sessionId)) return next();
    const id = randomUUID();
    const held = new Promise((resolve) => {
      this.pending.set(id, {
        kind: "approval",
        id,
        sessionId,
        title: this.titleOfId(sessionId),
        toolName: String(request.toolName ?? "tool"),
        reason: request.reason,
        resolve,
        at: Date.now(),
      });
      this.touch();
      request.signal?.addEventListener("abort", () => {
        if (this.pending.delete(id)) this.touch();
      }, { once: true });
    });
    return Promise.race([held, next()]).finally(() => {
      if (this.pending.delete(id)) this.touch();
    });
  }

  /** Hold an AskUserQuestion request. The delegated wait owns its own abort
   *  controller: the losing Web answerer must be cancelled, or its interaction
   *  stays mounted forever. */
  holdAsk(request, next) {
    const sessionId = String(request?.agent?.id ?? "");
    if (!sessionId) return next();
    const originalSignal = request.signal;
    const downstream = new AbortController();
    request.signal = originalSignal
      ? AbortSignal.any([originalSignal, downstream.signal])
      : downstream.signal;
    const id = randomUUID();
    const questions = (request.questions ?? []).map((item) => ({
      id: item.id,
      question: item.question,
      detail: item.detail,
      header: item.header,
      options: item.options,
      multiSelect: item.multiSelect,
    }));
    const held = new Promise((resolve) => {
      this.pending.set(id, {
        kind: "ask",
        id,
        sessionId,
        title: this.titleOfId(sessionId),
        questions,
        resolve,
        at: Date.now(),
      });
      this.touch();
      request.signal?.addEventListener("abort", () => {
        if (this.pending.delete(id)) this.touch();
      }, { once: true });
    });
    return Promise.race([held, Promise.resolve().then(next)]).finally(() => {
      downstream.abort(new Error("Question settled through another answerer"));
      if (originalSignal === undefined) delete request.signal;
      else request.signal = originalSignal;
      if (this.pending.delete(id)) this.touch();
    });
  }

  decideApproval(id, outcome) {
    const held = this.pending.get(id);
    if (!held || held.kind !== "approval") return false;
    this.pending.delete(id);
    this.touch();
    held.resolve(outcome);
    return true;
  }

  answerAsk(id, answers) {
    const held = this.pending.get(id);
    if (!held || held.kind !== "ask") return false;
    this.pending.delete(id);
    this.touch();
    held.resolve({ answers });
    return true;
  }

  stop(sessionId) {
    try {
      const agent = this.ctx.agents?.get?.(sessionId);
      if (!agent || typeof agent.cancel !== "function") return false;
      agent.cancel({ kind: "user" }, { keepInbox: true });
      return true;
    } catch {
      return false;
    }
  }

  heldApproval(sessionId) {
    for (const held of this.pending.values()) {
      if (held.kind === "approval" && held.sessionId === sessionId) return held;
    }
    return undefined;
  }

  heldAsk(sessionId) {
    for (const held of this.pending.values()) {
      if (held.kind === "ask" && held.sessionId === sessionId) return held;
    }
    return undefined;
  }

  stateFor(session, row) {
    const agent = this.ctx.agents?.get?.(session.id);
    const busy = agent?.status === "running";
    if (this.heldApproval(session.id) || this.heldAsk(session.id)) return "approval";
    if (row.lastError && (row.lastTurn === undefined || row.lastTurn.at < row.lastError.at)) return "error";
    if (busy && row.pendingTools.size > 0) return "tool";
    if (busy) return "thinking";
    if (row.lastTurn?.failed) return "error";
    if (row.lastTurn?.kind === "completed" && Date.now() - row.lastTurn.at < DONE_TTL_MS) return "done";
    return "idle";
  }

  detailFor(state, row) {
    switch (state) {
      case "tool": return row.lastTool?.name ?? "tool";
      case "thinking": return "Thinking…";
      case "error": return row.lastError?.message ?? (row.lastTurn?.kind === "max-tokens" ? "Max tokens reached" : "Turn failed");
      case "done": return "Done";
      case "approval": return "Approval required";
      default: return "";
    }
  }

  titleOfId(sessionId) {
    try {
      const session = this.ctx.sessions?.get?.(sessionId);
      if (session) return this.titleOf(session);
    } catch {
      /* optional service */
    }
    return String(sessionId).slice(0, 8);
  }

  titleOf(session) {
    try {
      const title = this.ctx.get?.("sessionTitle")?.get?.(session)?.title;
      if (typeof title === "string" && title.trim() !== "") return title;
    } catch {
      /* optional service */
    }
    return String(session.id).slice(0, 8);
  }

  projection(session, key) {
    try {
      return this.ctx.get?.("sessionProjections")?.stateOf?.(session, key);
    } catch {
      return undefined;
    }
  }

  snapshot() {
    const sessions = this.ctx.sessions.list() ?? [];
    const rows = [];
    for (const session of sessions) {
      const row = this.row(session.id);
      const state = this.stateFor(session, row);
      const usageRaw = this.projection(session, "tokenUsage") ?? {};
      // 0.2.1 projection shape: { totals: {...}, last: {...} }.
      const usage = usageRaw.totals ?? usageRaw;
      const selection = this.projection(session, "modelSelection");
      const pressure = this.projection(session, "contextPressure") ?? {};
      // Cache reads stay out of the headline number: they are real usage, but
      // tens of millions of cached tokens read as nonsense in a menu bar.
      const tokens = (usage.uncachedInputTokens ?? 0) + (usage.outputTokens ?? 0);
      if (session.header?.origin === "subagent") continue;
      const approval = this.heldApproval(session.id);
      const ask = this.heldAsk(session.id);
      rows.push({
        id: session.id,
        title: this.titleOf(session),
        state,
        child: false,
        busy: state === "thinking" || state === "tool",
        detail: this.detailFor(state, row),
        model: selection?.lastUsed?.model ?? row.model ?? "",
        tokens,
        usage: usageRaw,
        context: { pressureTokens: pressure.pressureTokens, projectedTokens: pressure.projectedTokens, contextWindow: pressure.contextWindow },
        lastTurn: row.lastTurn,
        startedAt: row.startedAt,
        approval: approval === undefined ? undefined : { id: approval.id, toolName: approval.toolName, reason: approval.reason },
        ask: ask === undefined ? undefined : { id: ask.id, questions: ask.questions },
      });
    }
    rows.sort((a, b) => (STATE_PRIORITY[a.state] ?? 9) - (STATE_PRIORITY[b.state] ?? 9)
      || (b.lastTurn?.at ?? 0) - (a.lastTurn?.at ?? 0));
    const active = rows[0];
    const counts = { busy: 0, waiting: 0, unread: 0, failed: 0 };
    for (const row of rows) {
      if (row.busy) counts.busy += 1;
      if (row.state === "approval") counts.waiting += 1;
      if (row.state === "error") counts.failed += 1;
    }
    const approvals = [];
    const questions = [];
    for (const held of this.pending.values()) {
      if (held.kind === "approval") {
        approvals.push({ id: held.id, sessionId: held.sessionId, title: held.title, toolName: held.toolName, reason: held.reason });
      } else {
        questions.push({ id: held.id, sessionId: held.sessionId, title: held.title, questions: held.questions });
      }
    }
    this.revision += 1;
    return {
      schemaVersion: 1,
      serverId: this.serverId,
      revision: this.revision,
      generatedAt: Date.now(),
      origin: this.origin,
      app: { bundleId: "com.deepseek.dsh", profile: process.env.DSH_PROFILE ?? "" },
      active: active === undefined ? null : {
        sessionId: active.id,
        title: active.title,
        state: active.state,
        detail: active.detail,
        child: false,
        busy: active.busy,
        unread: false,
        model: active.model,
        tokens: active.tokens,
        usage: active.usage,
        context: active.context,
        startedAt: active.startedAt,
      },
      counts,
      rows,
      approvals,
      questions,
    };
  }

  requestFocus(sessionId) {
    const exists = (this.ctx.sessions.list() ?? []).some((session) => session.id === sessionId);
    if (!exists) return false;
    this.focus = { sessionId, at: Date.now() };
    return true;
  }

  peekFocus() {
    if (this.focus === undefined) return null;
    if (Date.now() - this.focus.at > 60_000) {
      this.focus = undefined;
      return null;
    }
    return this.focus;
  }
}
