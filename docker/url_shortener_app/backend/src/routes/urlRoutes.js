const express = require("express");
const controller = require("../controllers/urlController");

const router = express.Router();

/* =========================
   HEALTH (PUT FIRST)
========================= */

router.get("/health", (req, res) => {
  res.json({
    status: "ok",
    service: "url_shortener",
    uptime: process.uptime()
  });
});

router.get("/live", (req, res) => {
  res.json({
    status: "alive",
    service: "url_shortener"
  });
});

/* =========================
   CORE API
========================= */

router.post("/shorten", controller.shorten);
router.get("/urls", controller.list);

router.get("/stats/:code", controller.stats);
router.delete("/urls/:code", controller.remove);

/* =========================
   IMPORTANT: CATCH-LAST ROUTE
========================= */

// MUST BE LAST
router.get("/:code", controller.redirect);

module.exports = router;
