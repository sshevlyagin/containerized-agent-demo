import { Router, type Router as RouterType } from "express";
import { prisma } from "../db.js";

const router: RouterType = Router();

router.get("/orders/:orderNumber", async (req, res) => {
  const order = await prisma.order.findUnique({
    where: { orderNumber: req.params.orderNumber },
  });

  if (!order) {
    res.status(404).json({ error: "Order not found" });
    return;
  }

  res.json(order);
});

export default router;
