async function shorten() {
  const url = document.getElementById("url").value;

  const res = await fetch("/api/shorten", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ url })
  });

  const data = await res.json();

  document.getElementById("result").innerHTML =
    `Short URL: <a href="/${data.code}" target="_blank">${data.code}</a>`;
}

async function loadAll() {
  const res = await fetch("/api/urls");
  const data = await res.json();

  document.getElementById("list").innerText =
    JSON.stringify(data, null, 2);
}
