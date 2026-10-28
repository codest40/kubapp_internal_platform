import assert from "node:assert/strict";
import { after, before, describe, it } from "node:test";
import { createServer, type Server } from "node:http";
import { createApp } from "../src/app.js";

describe("TypeScript API", () => {
  let server: Server;
  let baseUrl: string;

  before(async () => {
    server = createServer(createApp());

    await new Promise<void>((resolve, reject) => {
      server.once("error", reject);

      server.listen(0, "127.0.0.1", () => {
        server.off("error", reject);
        resolve();
      });
    });

    const address = server.address();

    if (!address || typeof address === "string") {
      throw new Error("Unable to determine test server address");
    }

    baseUrl = `http://127.0.0.1:${address.port}`;
  });

  after(async () => {
    await new Promise<void>((resolve, reject) => {
      server.close((error) => {
        if (error) {
          reject(error);
        } else {
          resolve();
        }
      });
    });
  });

  it("returns application information", async () => {
    const response = await fetch(baseUrl);
    const body = await response.json();

    assert.equal(response.status, 200);
    assert.equal(body.name, "typescript-ci-sample");
    assert.equal(body.language, "typescript");
    assert.equal(body.status, "running");
  });

  it("reports a healthy status", async () => {
    const response = await fetch(`${baseUrl}/health`);
    const body = await response.json();

    assert.equal(response.status, 200);
    assert.equal(body.status, "healthy");
  });

  it("returns the API message", async () => {
    const response = await fetch(`${baseUrl}/api/message`);
    const body = await response.json();

    assert.equal(response.status, 200);
    assert.equal(
      body.message,
      "TypeScript application is working"
    );
    assert.ok(Number.isFinite(Date.parse(body.timestamp)));
  });
});
