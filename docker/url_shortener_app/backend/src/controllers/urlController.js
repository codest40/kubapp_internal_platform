const service = require("../services/urlService");

exports.shorten = (req, res) => {
  const { url } = req.body;

  if (!url) return res.status(400).json({ error: "URL required" });

  const code = service.createShortUrl(url);

  res.json({
    code,
    shortUrl: `${req.headers.host}/${code}`
  });
};

exports.redirect = (req, res) => {
  const { code } = req.params;
  const data = service.getUrl(code);

  if (!data) return res.status(404).send("Not found");

  service.incrementClick(code);
  res.redirect(data.longUrl);
};

exports.list = (req, res) => {
  res.json(service.getAll());
};

exports.remove = (req, res) => {
  service.deleteUrl(req.params.code);
  res.json({ message: "deleted" });
};

exports.stats = (req, res) => {
  const data = service.getUrl(req.params.code);
  if (!data) return res.status(404).json({ error: "not found" });

  res.json({
    code: req.params.code,
    clicks: data.clicks,
    createdAt: data.createdAt
  });
};
