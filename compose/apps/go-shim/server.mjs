// go-shim — minimal OpenAI-compatible proxy for OpenCode Go.
//
// OpenCode Go requires `x-opencode-session` (and a real User-Agent) on every
// chat/completions request, which Job Ops' provider cannot send. This shim sits
// in front of it, injects those headers, and forwards to Go.
//
// Job Ops is pointed at:  http://go-shim:8090/v1
import http from "node:http";

const PORT = Number(process.env.PORT || 8090);
const UPSTREAM = (process.env.GO_UPSTREAM || "https://opencode.ai/zen/go").replace(/\/+$/, "");
const SESSION = process.env.GO_SESSION || "job-ops";
const USER_AGENT = process.env.GO_USER_AGENT || "job-ops/1.0";

function readBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    req.on("data", (c) => chunks.push(c));
    req.on("end", () => resolve(Buffer.concat(chunks)));
    req.on("error", reject);
  });
}

// OpenCode Go (via DeepSeek/Kimi/MiMo) rejects response_format json_schema with
// an opaque 400. Job Ops only retries a different mode when the error is tagged
// CAPABILITY:, so it would hard-fail. Downgrade json_schema -> json_object here;
// Job Ops' prompts already demand JSON-only output.
function normalizeBody(buf) {
  if (!buf || buf.length === 0) return buf;
  try {
    const obj = JSON.parse(buf.toString("utf8"));
    if (obj?.response_format?.type === "json_schema") {
      obj.response_format = { type: "json_object" };
    }
    return Buffer.from(JSON.stringify(obj));
  } catch {
    return buf;
  }
}

const server = http.createServer(async (req, res) => {
  if (req.url === "/healthz") {
    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ ok: true, upstream: UPSTREAM }));
    return;
  }

  const target = UPSTREAM + req.url;
  let body;
  if (req.method !== "GET" && req.method !== "HEAD") {
    body = normalizeBody(await readBody(req));
  }

  const headers = {
    Accept: req.headers["accept"] || "application/json",
    "Content-Type": req.headers["content-type"] || "application/json",
    "User-Agent": USER_AGENT,
    "x-opencode-session": SESSION,
  };
  if (req.headers["authorization"]) {
    headers.Authorization = req.headers["authorization"];
  }

  try {
    const upstream = await fetch(target, { method: req.method, headers, body });
    const outHeaders = {
      "Content-Type": upstream.headers.get("content-type") || "application/json",
    };
    res.writeHead(upstream.status, outHeaders);
    if (upstream.body) {
      for await (const chunk of upstream.body) res.write(chunk);
    }
    res.end();
  } catch (err) {
    res.writeHead(502, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ error: { message: `go-shim upstream error: ${err}` } }));
  }
});

server.listen(PORT, () => {
  console.log(`go-shim listening on :${PORT} -> ${UPSTREAM} (session=${SESSION})`);
});
