const express = require("express");
const path = require("path");
const routes = require("./routes/urlRoutes");

const app = express();
const PORT = process.env.PORT || 3000;

/* =========================
   MIDDLEWARE
========================= */
app.use(express.json());

/* =========================
   API ROUTES
========================= */
app.use("/api", routes);

/* =========================
   FRONTEND
========================= */
const frontendPath = path.join(__dirname, "../../frontend");

app.use(express.static(frontendPath));

app.get("/", (req, res) => {
  res.sendFile(path.join(frontendPath, "index.html"));
});

/* =========================
   START SERVER
========================= */
app.listen(PORT, () => {
  console.log(`URL Shortener running on port ${PORT}`);
});
