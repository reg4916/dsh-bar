import test from "node:test";
import assert from "node:assert/strict";
import { Board } from "../lib/state.js";

function fakeCtx(sessions) {
  const agents = new Map();
  return {
    sessions: { list: () => sessions },
    agents: { get: (id) => agents.get(id) },
    get: (name) => (name === "sessionProjections" ? { stateOf: () => undefined } : undefined),
    __agents: agents,
  };
}

const session = (id, header = { origin: "root" }) => ({ id, header });

test("idle with no activity", () => {
  const ctx = fakeCtx([session("s1")]);
  const board = new Board(ctx, "srv");
  board.origin = "http://127.0.0.1:1";
  const snap = board.snapshot();
  assert.equal(snap.schemaVersion, 1);
  assert.equal(snap.serverId, "srv");
  assert.equal(snap.active.state, "idle");
  assert.equal(snap.revision, 1);
});

test("thinking while the agent is running", () => {
  const ctx = fakeCtx([session("s1")]);
  const board = new Board(ctx, "srv");
  board.origin = "http://127.0.0.1:1";
  ctx.__agents.set("s1", { status: "running" });
  assert.equal(board.snapshot().active.state, "thinking");
});

test("tool while a tool call has no result", () => {
  const ctx = fakeCtx([session("s1")]);
  const board = new Board(ctx, "srv");
  board.origin = "http://127.0.0.1:1";
  ctx.__agents.set("s1", { status: "running" });
  board.onSessionEvent(session("s1"), { type: "tool/call", time: Date.now(), data: { callId: "c1", name: "bash" } });
  const snap = board.snapshot();
  assert.equal(snap.active.state, "tool");
  assert.equal(snap.active.detail, "bash");
  board.onSessionEvent(session("s1"), { type: "tool/result", time: Date.now(), data: { callId: "c1" } });
  assert.equal(board.snapshot().active.state, "thinking");
});

test("error after a failed turn", () => {
  const ctx = fakeCtx([session("s1")]);
  const board = new Board(ctx, "srv");
  board.origin = "http://127.0.0.1:1";
  board.onSessionEvent(session("s1"), { type: "turn/end", time: Date.now(), data: { reason: { kind: "error" } } });
  const snap = board.snapshot();
  assert.equal(snap.active.state, "error");
  assert.equal(snap.counts.failed, 1);
});

test("done right after a completed turn, then idle", () => {
  const ctx = fakeCtx([session("s1")]);
  const board = new Board(ctx, "srv");
  board.origin = "http://127.0.0.1:1";
  board.onSessionEvent(session("s1"), { type: "turn/end", time: Date.now(), data: { reason: { kind: "completed" } } });
  assert.equal(board.snapshot().active.state, "done");
  board.fold.get("s1").lastTurn.at = Date.now() - 60_000;
  assert.equal(board.snapshot().active.state, "idle");
});

test("subagent sessions roll up into the root row", () => {
  const ctx = fakeCtx([session("root"), session("child", { origin: "subagent", parentSession: "root" })]);
  const board = new Board(ctx, "srv");
  board.origin = "http://127.0.0.1:1";
  assert.equal(board.snapshot().rows.length, 1);
});

test("focus wish validates the session and expires", () => {
  const ctx = fakeCtx([session("s1")]);
  const board = new Board(ctx, "srv");
  board.origin = "http://127.0.0.1:1";
  assert.equal(board.requestFocus("nope"), false);
  assert.equal(board.requestFocus("s1"), true);
  assert.equal(board.peekFocus().sessionId, "s1");
  board.focus.at = Date.now() - 61_000;
  assert.equal(board.peekFocus(), null);
});

test("token totals come from the nested projection shape", () => {
  const ctx = fakeCtx([session("s1")]);
  ctx.get = (name) => {
    if (name === "sessionProjections") {
      return {
        stateOf: (_session, key) => {
          if (key === "tokenUsage") {
            return { totals: { uncachedInputTokens: 388200, outputTokens: 308259, cacheReadTokens: 94_000_000 }, last: {} };
          }
          return undefined;
        },
      };
    }
    return undefined;
  };
  const board = new Board(ctx, "srv");
  board.origin = "http://127.0.0.1:1";
  const snap = board.snapshot();
  assert.equal(snap.active.tokens, 696459);
  assert.equal(snap.active.usage.totals.uncachedInputTokens, 388200);
});
