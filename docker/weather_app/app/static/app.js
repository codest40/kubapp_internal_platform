// static/app.js
const form = document.getElementById("prefForm");

if (form) {
    form.addEventListener("submit", async (e) => {
        e.preventDefault();

        const formData = new FormData(form);

        const response = await fetch("/preferences", {
            method: "POST",
            body: formData,
        });

        const messageBox = document.getElementById("message");

        if (response.ok) {
            const result = await response.json();
            messageBox.innerText = result.message;
            messageBox.classList.add("show");
            form.reset();
        } else {
            messageBox.innerText = "Failed to save preferences.";
            messageBox.classList.add("show");
        }
    });
}

// ------------------ Real-Time Clock ------------------
function updateTime() {
    const now = new Date();
    const timeString = now.toLocaleTimeString(); // e.g., "14:35:08"
    const dateString = now.toLocaleDateString(); // optional: "1/24/2026"
    const el = document.getElementById("current-time");
    if (el) {
        el.innerText = `${dateString} ${timeString}`;
    }
}

// Update every second
setInterval(updateTime, 1000);
updateTime(); // initial call
