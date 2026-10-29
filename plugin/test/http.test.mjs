import test from "node:test";
import assert from "node:assert/strict";
import http from "node:http";
import { attachHttp } from "../lib/http.js";

test("SSE endpoint streams the first status frame", async () => {
  let handler;
  const board = {
    revision: 0,
    snapshot() {
      this.revision += 1;
      return {
        schemaVersion: 1,
        serverId: "fake",
        revision: this.revision,
        active: { sessionId: "s1", state: "thinking", title: "Fake" },
      };
    },
    subscribe() {
      return () => {};
    },
    peekFocus() {
      return null;
    },
  };
  const ctx = { webServer: { register: ({ handler: registered }) => { handler = registered; return () => {}; } } };
  attachHttp(ctx, board, "tok", "http://127.0.0.1");
  const server = http.createServer((req, res) => handler(req, res));
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  const port = server.address().port;

  let status = 0;
  let contentType = "";
  const body = await new Promise((resolve, reject) => {
    const req = http.get({
      host: "127.0.0.1",
      port,
      path: "/dsh-bar/events",
      headers: { authorization: "Bearer tok" },
    }, (res) => {
      status = res.statusCode;
      contentType = String(res.headers["content-type"] ?? "");
      let text = "";
      res.on("data", (chunk) => {
        text += chunk.toString();
        if (text.includes("\n\n")) {
          req.destroy();
          resolve(text);
        }
      });
    });
    req.on("error", (error) => {
      if (error.code !== "ECONNRESET") reject(error);
    });
  });

  assert.equal(status, 200);
  assert.match(contentType, /text\/event-stream/);
  assert.match(body, /event: status/);
  assert.match(body, /"thinking"/);
  await new Promise((resolve) => server.close(resolve));
});
