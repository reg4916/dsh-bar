/**
 * runtime.json is the only contract between the Host plugin and the native app:
 * where the loopback server listens, which Bearer token opens it, and which pid
 * to watch. The native side re-reads it before every request because Desktop
 * starts the Host with "--port 0" (a new port on every restart).
 */
import { chmodSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { randomBytes } from "node:crypto";

export function dshHome() {
  return process.env.DSH_HOME || join(homedir(), ".dsh");
}

export function runtimePath() {
  return process.env.DSH_BAR_RUNTIME_FILE || join(dshHome(), "dsh-bar", "runtime.json");
}

function readJson(path) {
  try {
    return JSON.parse(readFileSync(path, "utf8"));
  } catch {
    return undefined;
  }
}

/** Reuse the token across Host restarts: an already-running native app must not
 *  start receiving 403s just because the Host was restarted. */
export function loadOrCreateToken() {
  const existing = readJson(runtimePath());
  if (existing?.token && String(existing.token).length >= 16) return String(existing.token);
  return randomBytes(24).toString("hex");
}

export function writeRuntime(file) {
  const path = runtimePath();
  mkdirSync(dirname(path), { recursive: true, mode: 0o700 });
  writeFileSync(path, JSON.stringify(file, null, 2) + "\n", { encoding: "utf8", mode: 0o600 });
  try {
    chmodSync(path, 0o600);
  } catch {
    /* best effort on exotic filesystems */
  }
}
