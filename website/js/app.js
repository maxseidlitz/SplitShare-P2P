const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

const digitsEl = document.getElementById("digits");
const noteTop = document.getElementById("form-note");
const noteBottom = document.getElementById("form-note-bottom");

let currentCount = 0;

function padCount(value) {
  return String(Math.max(0, value)).padStart(4, "0").slice(-4);
}

function renderCount(value, animate = false) {
  const next = padCount(value);
  const spans = [...digitsEl.querySelectorAll("span")];
  spans.forEach((span, index) => {
    if (span.textContent !== next[index]) {
      span.textContent = next[index];
      if (animate) {
        span.classList.remove("flip");
        void span.offsetWidth;
        span.classList.add("flip");
        setTimeout(() => span.classList.remove("flip"), 360);
      }
    }
  });
  digitsEl.setAttribute("aria-label", `${value} Personen auf der Waitlist`);
  currentCount = value;
}

async function fetchCount() {
  const response = await fetch("/api/waitlist");
  if (!response.ok) throw new Error("count failed");
  const data = await response.json();
  return Number(data.count) || 0;
}

async function refreshCount(animate = true) {
  try {
    const count = await fetchCount();
    renderCount(count, animate && count !== currentCount);
  } catch {
    /* still show last known count */
  }
}

function setNote(kind, message) {
  [noteTop, noteBottom].forEach((el) => {
    if (!el) return;
    el.classList.remove("ok", "err");
    if (kind) el.classList.add(kind);
    el.textContent = message;
  });
}

async function submitEmail(form) {
  const input = form.querySelector('input[type="email"]');
  const button = form.querySelector("button");
  const email = (input.value || "").trim().toLowerCase();

  if (!EMAIL_RE.test(email)) {
    setNote("err", "Bitte eine gültige E-Mail eingeben.");
    input.focus();
    return;
  }

  button.disabled = true;
  try {
    const response = await fetch("/api/waitlist", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ email }),
    });
    const data = await response.json();

    if (response.status === 409 || data.alreadyJoined) {
      renderCount(data.count ?? currentCount, true);
      setNote("ok", "Diese Mail steht schon auf der Liste. Wir sehen uns zum Launch.");
      return;
    }

    if (!response.ok) {
      setNote("err", data.error || "Hat nicht geklappt. Versuch’s gleich nochmal.");
      return;
    }

    renderCount(data.count ?? currentCount + 1, true);
    form.reset();
    setNote("ok", "Du bist dabei. Wir schreiben dir, sobald SplitShare live ist.");
  } catch {
    setNote("err", "Keine Verbindung zum Server. Ist die Waitlist-Seite gestartet?");
  } finally {
    button.disabled = false;
  }
}

document.querySelectorAll(".waitlist").forEach((form) => {
  form.addEventListener("submit", (event) => {
    event.preventDefault();
    submitEmail(form);
  });
});

refreshCount(false);
setInterval(() => refreshCount(true), 8000);
