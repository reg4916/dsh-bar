/**
 * DSH Bar — host half.
 *
 * Writes $DSH_HOME/dsh-bar/runtime.json, mounts /dsh-bar on the Host web server,
 * and folds session events into the small document the macOS menu bar renders.
 */
import { randomBytes } from "node:crypto";
import { attachHttp } from "./lib/http.js";
import { Board } from "./lib/state.js";
import { dshHome, loadOrCreateToken, runtimePath, writeRuntime } from "./lib/store.js";

const VERSION = "0.1.0";

export const name = "dsh-bar";
export const inject = ["sessions", "agents", "webServer"];

export function apply(ctx) {
  const serverId = randomBytes(8).toString("hex");
  const board = new Board(ctx, serverId);
  const token = loadOrCreateToken();
  const origin = "http://" + ctx.webServer.host + ":" + String(ctx.webServer.port);
  board.origin = origin;

  writeRuntime({
    schemaVersion: 1,
    origin,
    token,
    pid: process.pid,
    writtenAt: Date.now(),
    home: dshHome(),
    profile: process.env.DSH_PROFILE ?? "",
    plugin: { name, version: VERSION },
    appBundleId: "com.deepseek.dsh",
  });
  console.log("[dsh-bar] runtime " + runtimePath() + " -> " + origin);

  ctx.effect(() => attachHttp(ctx, board, token, origin), "dsh-bar: http");
  ctx.effect(() => ctx.on("session/created", (session) => board.row(session.id)), "dsh-bar: session-created");
  ctx.effect(() => ctx.on("session/disposed", (session) => board.forget(session.id)), "dsh-bar: session-disposed");
  ctx.effect(() => ctx.on("session/event", (session, event) => board.onSessionEvent(session, event)), "dsh-bar: session-events");
  ctx.effect(() => ctx.on("agent/status", ({ agent }) => {
    if (agent?.session?.id) board.row(agent.session.id);
  }), "dsh-bar: agent-status");
  ctx.effect(() => ctx.on("agent/error", ({ agent, error }) => {
    board.onAgentError(agent?.session?.id ?? agent?.id, error);
  }), "dsh-bar: agent-error");
}
