
const test = require("node:test");
const assert = require("node:assert/strict");
const app = require("../app");

test("GET /health returns 200 and OK v0.2", async () => {
  const server = app.listen(0);

  try {
    const port = server.address().port;
    const response = await fetch(
      `http://localhost:${port}/health`
    );

    const body = await response.text();

    assert.equal(response.status, 200);
    assert.equal(body, "OK v0.2");
  } finally {
    server.close();
  }
});
