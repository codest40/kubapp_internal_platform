import express, { type Express } from "express";

export function createApp(): Express {
  const app = express();

  app.disable("x-powered-by");
  app.use(express.json());

  app.get("/", (_req, res) => {
    res.status(200).json({
      name: "typescript-ci-sample",
      runtime: "node",
      language: "typescript",
      status: "running"
    });
  });

  app.get("/health", (_req, res) => {
    res.status(200).json({
      status: "healthy"
    });
  });

  app.get("/api/message", (_req, res) => {
    res.status(200).json({
      message: "TypeScript application is working",
      timestamp: new Date().toISOString()
    });
  });

  return app;
}
