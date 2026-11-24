
const express = require("express");
const client = require("prom-client");

const app = express();
const PORT = process.env.PORT || 3000;

client.collectDefaultMetrics();

const httpRequests = new client.Counter({
  name: "http_requests_total",
  help: "Total HTTP requests",
  labelNames: ["method", "route", "status"],
});

const httpDuration = new client.Histogram({
  name: "http_request_duration_seconds",
  help: "Request latency in seconds",
  labelNames: ["method", "route"],
  buckets: [0.05, 0.1, 0.3, 0.5, 1, 2],
});

function log(level, fields) {
  console.log(JSON.stringify({
    timestamp: new Date().toISOString(),
    level,
    ...fields,
  }));
}

app.use((req, res, next) => {
  const { method, path } = req;
  const end = httpDuration.startTimer();

  res.on("finish", () => {
    // Use the route pattern, not the URL, to keep label cardinality bounded.
    const route = req.route ? req.baseUrl + req.route.path : "unmatched";
    const status = res.statusCode;

    httpRequests.inc({ method, route, status });
    const seconds = end({ method, route });

    log(status >= 500 ? "error" : "info", {
      method,
      path,
      status,
      duration_ms: Math.round(seconds * 1000),
    });
  });

  next();
});

app.get("/health", (req, res) => {
  res.status(200).send("OK v0.2");
});

app.get("/slow", async (req, res) => {
  const delayMs = Math.round(Math.random() * 2000);
  await new Promise((resolve) => setTimeout(resolve, delayMs));
  res.status(200).send(`Done after ${delayMs} ms`);
});

app.get("/error", (req, res) => {
  if (Math.random() < 0.3) {
    res.status(500).send("Simulated error");
    return;
  }
  res.status(200).send("OK");
});

app.get("/metrics", async (req, res) => {
  res.set("Content-Type", client.register.contentType);
  res.end(await client.register.metrics());
});

if (require.main === module) {
  app.listen(PORT, "0.0.0.0", () => {
    log("info", { message: "Server started", port: Number(PORT) });
  });
}

module.exports = app;
