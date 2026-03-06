const http = require("http");
const fs = require("fs");
const path = require("path");

const STATUS_FILE = process.env.STATUS_FILE || path.join(__dirname, ".task-status.json");
const PORT = process.env.STATUS_PORT || 8080;

// Initialize status file
if (!fs.existsSync(STATUS_FILE)) {
  fs.writeFileSync(STATUS_FILE, JSON.stringify({ status: "pending", steps: [], updated: new Date().toISOString() }, null, 2));
}

const server = http.createServer((req, res) => {
  if (req.method === "GET" && req.url === "/status") {
    try {
      const data = fs.readFileSync(STATUS_FILE, "utf-8");
      res.writeHead(200, { "Content-Type": "application/json" });
      res.end(data);
    } catch {
      res.writeHead(500, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ error: "Could not read status file" }));
    }
  } else if (req.method === "POST" && req.url === "/status") {
    let body = "";
    req.on("data", (chunk) => (body += chunk));
    req.on("end", () => {
      try {
        const update = JSON.parse(body);
        let current = {};
        try { current = JSON.parse(fs.readFileSync(STATUS_FILE, "utf-8")); } catch {}
        const merged = { ...current, ...update, updated: new Date().toISOString() };
        if (update.step) {
          merged.steps = [...(current.steps || []), { ...update.step, timestamp: new Date().toISOString() }];
          delete merged.step;
        }
        fs.writeFileSync(STATUS_FILE, JSON.stringify(merged, null, 2));
        res.writeHead(200, { "Content-Type": "application/json" });
        res.end(JSON.stringify(merged));
      } catch {
        res.writeHead(400, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ error: "Invalid JSON" }));
      }
    });
  } else {
    res.writeHead(404);
    res.end("Not found");
  }
});

server.listen(PORT, () => {
  console.log(`Status server listening on http://localhost:${PORT}/status`);
});
