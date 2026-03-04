import express from "express";
import { config } from "./config.js";
import { prisma } from "./db.js";
import orderRoutes from "./routes/orders.js";
import { startConsumer } from "./sqs-consumer.js";

const app = express();
app.use(express.json());

app.get("/health", async (_req, res) => {
  try {
    await prisma.$queryRaw`SELECT 1`;
    res.json({ status: "ok" });
  } catch {
    res.status(503).json({ status: "unhealthy" });
  }
});

app.use(orderRoutes);

app.use(
  (
    err: Error,
    _req: express.Request,
    res: express.Response,
    _next: express.NextFunction
  ) => {
    console.error("Unhandled error:", err);
    res.status(500).json({ error: "Internal server error" });
  }
);

app.listen(config.port, () => {
  console.log(`Order service listening on port ${config.port}`);
  startConsumer();
});
