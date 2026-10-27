/**
 * Loopback HTTP surface, mounted as a prefix on the Host's own web server.
 *
 * Native clients authenticate with the Bearer token from runtime.json; the GUI
 * page uses same-origin/bridge trust (no secret in page JS). The Desktop shell
 * forwards page requests with Origin/cookie/sec-fetch-site stripped, so the
 * browser-trust check has a script-header fallback, exactly like the shipped
 * workspace file panel.
 */
const PREFIX = "/dsh-bar";
const BODY_LIMIT = 64 * 1024;

function isLoopback(req) {
  const ip = req.socket?.remoteAddress ?? "";
  return ip === "127.0.0.1" || ip === "::1" || ip === "::ffff:127.0.0.1";
}

function authorized(req, token) {
  if (req.headers.authorization === "Bearer " + token) return true;
  try {
    return new URL(req.url ?? "/", "http://127.0.0.1").searchParams.get("token") === token;
  } catch {
    return false;
  }
}

function browserTrusted(req) {
  if (!isLoopback(req)) return false;
  if (req.headers["sec-fetch-site"] === "cross-site") return false;
  const host = req.headers.host;
  if (host === undefined) return false;
  const origin = req.headers.origin;
  if (origin === undefined) return true;
  try {
    return new URL(origin).host === new URL("http://" + host).host;
  } catch {
    return false;
  }
}

function sidebarTrusted(req, origin) {
  if (!browserTrusted(req) || !String(req.headers["content-type"] ?? "").startsWith("application/json")) return false;
  if (req.headers.origin !== undefined) return true;
  return req.headers["x-dsh-bar-client"] === "1"
    && req.headers["sec-fetch-site"] === undefined
    && req.headers.host === new URL(origin).host;
}

function send(res, status, body) {
  res.writeHead(status, { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" });
  res.end(JSON.stringify(body));
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let size = 0;
    req.on("data", (chunk) => {
      size += chunk.length;
      if (size > BODY_LIMIT) {
        reject(new Error("body too large"));
        req.destroy();
        return;
      }
      chunks.push(chunk);
    });
    req.on("end", () => resolve(Buffer.concat(chunks).toString("utf8")));
    req.on("error", reject);
  });
}

export function attachHttp(ctx, board, token, origin) {
  const startedAt = Date.now();

  const handler = async (req, res) => {
    const url = new URL(req.url ?? "/", "http://127.0.0.1");
    const path = url.pathname;
    const method = req.method ?? "GET";

    // GUI half: same-origin only, no token ever lands in page JS.
    if (method === "GET" && path === PREFIX + "/pending-focus") {
      if (!sidebarTrusted(req, origin) && !browserTrusted(req)) {
        send(res, 403, { ok: false, error: "forbidden" });
        return;
      }
      send(res, 200, { ok: true, focus: board.peekFocus() });
      return;
    }

    // Everything else is native-channel only.
    if (!isLoopback(req) || !authorized(req, token)) {
      send(res, 403, { ok: false, error: "forbidden" });
      return;
    }

    if (method === "GET" && path === PREFIX + "/status") {
      send(res, 200, board.snapshot());
      return;
    }

    if (method === "GET" && path === PREFIX + "/health") {
      send(res, 200, { ok: true, pid: process.pid, uptimeMs: Date.now() - startedAt, schemaVersion: 1 });
      return;
    }

    if (method === "POST" && path === PREFIX + "/focus") {
      const body = JSON.parse((await readBody(req)) || "{}");
      if (!body.sessionId) {
        send(res, 400, { ok: false, error: "sessionId required" });
        return;
      }
      if (!board.requestFocus(String(body.sessionId))) {
        send(res, 404, { ok: false, error: "unknown session" });
        return;
      }
      send(res, 200, { ok: true });
      return;
    }

    // Approvals, answers and stop land in M3; say so instead of pretending.
    if (method === "POST" && (path === PREFIX + "/approve" || path === PREFIX + "/answer"
      || path === PREFIX + "/seen" || path === PREFIX + "/stop")) {
      send(res, 501, { ok: false, error: "not implemented in this version" });
      return;
    }

    send(res, 404, { ok: false, error: "not found" });
  };

  const dispose = ctx.webServer.register({
    kind: "prefix",
    path: PREFIX,
    handler: (req, res) => {
      void handler(req, res).catch((error) => {
        if (!res.headersSent) send(res, 400, { ok: false, error: String(error?.message ?? error) });
      });
    },
  });

  return () => {
    dispose();
  };
}
