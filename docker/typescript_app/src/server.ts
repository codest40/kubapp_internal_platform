import { createServer } from "node:http";
import { createApp } from "./app.js";

const port = Number(process.env.PORT ?? 3000);
const host = process.env.HOST ?? "0.0.0.0";

if (!Number.isInteger(port) || port < 1 || port > 65535) {
  throw new Error("PORT must be a valid TCP port");
}

const app = createApp();
const server = createServer(app);

server.listen(port, host, () => {
  console.log(`TypeScript API listening on ${host}:${port}`);
});

function shutdown(signal: string): void {
  console.log(`Received ${signal}; shutting down`);

  server.close((error) => {
    if (error) {
      console.error("Server shutdown failed", error);
      process.exitCode = 1;
    }
  });
}

process.once("SIGTERM", () => shutdown("SIGTERM"));
process.once("SIGINT", () => shutdown("SIGINT"));
