const root = document.documentElement;
root.classList.add("js");

const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;

/* reveal once, on enter */
const items = document.querySelectorAll(".reveal");
if ("IntersectionObserver" in window) {
  const io = new IntersectionObserver(
    (entries) => {
      for (const e of entries) {
        if (!e.isIntersecting) continue;
        e.target.classList.add("in");
        io.unobserve(e.target);
      }
    },
    { rootMargin: "0px 0px -8% 0px", threshold: 0.1 }
  );
  items.forEach((el) => io.observe(el));
} else {
  items.forEach((el) => el.classList.add("in"));
}

/* hero shot: starts a little small, grows to full width as it scrolls up.
   transform only, tied 1:1 to scroll position. */
const shot = document.getElementById("heroShot");
const glow = document.getElementById("glow");
if (shot && !reduce) {
  const from = 0.86;
  let ticking = false;

  const update = () => {
    ticking = false;
    const top = shot.getBoundingClientRect().top;
    const vh = innerHeight;
    // 0 when the shot enters the lower part of the view, 1 when it nears the top
    const p = Math.min(1, Math.max(0, (vh - top) / (vh * 0.75)));
    shot.style.transform = `scale(${from + (1 - from) * p})`;
    // glow builds as the editor rises: opacity + scale only
    glow.style.opacity = (0.15 + 0.85 * p).toFixed(3);
    glow.style.transform = `scale(${0.88 + 0.12 * p})`;
  };

  const onScroll = () => {
    if (ticking) return;
    ticking = true;
    requestAnimationFrame(update);
  };

  addEventListener("scroll", onScroll, { passive: true });
  addEventListener("resize", onScroll);
  update();
}

/* code tabs */
document.querySelectorAll("[data-tabs]").forEach((box) => {
  const tabs = box.querySelectorAll("[role=tab]");
  tabs.forEach((tab) => {
    tab.addEventListener("click", () => {
      tabs.forEach((t) => {
        const on = t === tab;
        t.setAttribute("aria-selected", on);
        box.querySelector("#" + t.getAttribute("aria-controls")).hidden = !on;
      });
    });
  });
});
