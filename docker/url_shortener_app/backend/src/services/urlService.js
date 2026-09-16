const store = require("../db/memoryStore");

function generateCode() {
  return Math.random().toString(36).substring(2, 8);
}

function createShortUrl(longUrl) {
  const code = generateCode();

  store.urls[code] = {
    longUrl,
    clicks: 0,
    createdAt: new Date()
  };

  return code;
}

function getUrl(code) {
  return store.urls[code];
}

function incrementClick(code) {
  if (store.urls[code]) {
    store.urls[code].clicks++;
  }
}

function deleteUrl(code) {
  delete store.urls[code];
}

function getAll() {
  return store.urls;
}

module.exports = {
  createShortUrl,
  getUrl,
  incrementClick,
  deleteUrl,
  getAll
};
