// Wayfair Town site menu: a collapsible bar on the far left of every page.
// After changing this file, raise the ?v= number in each page's <script src="nav.js?v=..."> so browsers fetch the new copy.
// To add, rename or reorder pages, edit LINKS below. The menu has its own fixed colours
// (the --wn-* values at the top of the styles), so it looks the same on every page. Each page loads this file with
//   <script src="nav.js" defer></script>
(() => {
  const LINKS = [
    ["home.html", "Home", '<path d="M3 11l9-7 9 7"/><path d="M5 10v10h14V10"/><path d="M10 20v-6h4v6"/>'],
    ["index.html", "Town Inventory", '<path d="M3 7l9-4 9 4-9 4-9-4z"/><path d="M3 7v10l9 4 9-4V7"/><path d="M12 11v10"/>'],
    ["royaltea-bar.html", "Royaltea Bar", '<path d="M4 8h12v6a5 5 0 0 1-5 5H9a5 5 0 0 1-5-5V8z"/><path d="M16 10h2a2 2 0 0 1 0 4h-2"/><path d="M8 3v2M12 3v2"/>'],
    ["crafting.html", "Crafting", '<path d="M14 4l6 6-3 3-6-6z"/><path d="M11 7L3 15l3 3 8-8"/><path d="M4 21h8"/>'],
    ["archives.html", "Town Archives", '<path d="M6 3h11a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H6z"/><path d="M6 3a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2"/><path d="M9 8h7M9 12h7M9 16h4"/>'],
  ];
  const here = (location.pathname.split("/").pop() || "index.html").toLowerCase();
  const icon = d => `<svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${d}</svg>`;

  const css = `
/* The menu keeps its own Garnet & Gilt colours on every page. */
.wnav,.wbar{--wn-bg:#190a10;--wn-bg2:#2a1019;--wn-ink:#f6ece8;--wn-mute:#c2b3b6;--wn-rule:#4a1d2a;--wn-hover:#381522;
  --wn-icon:#b7bdc6;--wn-active:#e6c26a;--wn-brand:#e6c26a;--wn-font:Cinzel;color-scheme:dark}
:root{--navW:216px}
body.nav-mini{--navW:64px}
.wnav{position:fixed;left:0;top:0;bottom:0;z-index:40;width:var(--navW);display:flex;flex-direction:column;gap:4px;padding:12px 10px;
  background:linear-gradient(180deg,var(--wn-bg2),var(--wn-bg));border-right:1px solid var(--wn-rule);transition:width .18s;overflow:hidden}
.wnav .top{display:flex;align-items:center;justify-content:space-between;gap:6px;min-height:44px;margin-bottom:8px}
.wnav .brand{font:700 16px/1.1 var(--wn-font),serif;color:var(--wn-brand);white-space:nowrap;padding-left:6px}
.wnav .tog{all:unset;box-sizing:border-box;cursor:pointer;width:44px;height:44px;flex:none;display:grid;place-items:center;border-radius:10px;
  color:var(--wn-mute);border:1px solid var(--wn-rule)}
.wnav .tog:hover{color:var(--wn-ink);border-color:var(--wn-brand)}
.wnav a{display:flex;align-items:center;gap:12px;min-height:44px;padding:0 12px;border-radius:10px;color:var(--wn-ink);
  text-decoration:none;white-space:nowrap;font:500 15px/1.2 "Alegreya Sans",system-ui,sans-serif}
.wnav a svg{flex:none;color:var(--wn-icon)}
.wnav a:hover{background:var(--wn-hover)}
.wnav a[aria-current=page]{background:var(--wn-hover);box-shadow:inset 3px 0 0 var(--wn-active)}
.wnav a[aria-current=page] svg{color:var(--wn-active)}
.wnav a:focus-visible,.wnav .tog:focus-visible,.wbar button:focus-visible{outline:2px solid var(--green,#3ddc97);outline-offset:1px}
body.nav-mini .wnav .brand,body.nav-mini .wnav a span{display:none}
body.nav-mini .wnav .top{justify-content:center}
body.nav-mini .wnav a{justify-content:center;padding:0}
.wbar{display:none}
.wback{display:none}
@media(min-width:900px){body{padding-left:var(--navW)}}
@media(max-width:899px){
  .wnav{width:min(260px,82vw);transform:translateX(-105%);transition:transform .2s}
  body.nav-open .wnav{transform:none}
  body.nav-open .wback{display:block;position:fixed;inset:0;z-index:35;background:#000a}
  body.nav-mini .wnav .brand,body.nav-mini .wnav a span{display:inline}
  body.nav-mini .wnav a{justify-content:flex-start;padding:0 12px}
  body.nav-mini .wnav .top{justify-content:space-between}
  .wbar{display:flex;align-items:center;gap:10px;padding:10px max(4vw,14px);border-bottom:1px solid var(--wn-rule);background:var(--wn-bg)}
  .wbar button{all:unset;box-sizing:border-box;cursor:pointer;display:flex;align-items:center;gap:8px;min-height:44px;padding:0 14px;
    border-radius:10px;border:1px solid var(--wn-rule);color:var(--wn-ink);font:500 16px "Alegreya Sans",system-ui,sans-serif}
  .wbar b{font:700 16px var(--wn-font),serif;color:var(--wn-brand)}
}
@media(prefers-reduced-motion:reduce){.wnav{transition:none}}`;

  if (!document.querySelector('link[href*="family=Cinzel"]')) { // the menu's heading font
    const f = document.createElement("link"); f.rel = "stylesheet";
    f.href = "https://fonts.googleapis.com/css2?family=Cinzel:wght@600;700&family=Alegreya+Sans:wght@500&display=swap";
    document.head.appendChild(f);
  }
  const st = document.createElement("style"); st.textContent = css; document.head.appendChild(st);

  const nav = document.createElement("nav");
  nav.className = "wnav"; nav.id = "wnav"; nav.setAttribute("aria-label", "Site menu");
  nav.innerHTML = `<div class="top"><span class="brand">Wayfair Town</span>
      <button class="tog" type="button" aria-controls="wnav"></button></div>` +
    LINKS.map(([href, label, d]) =>
      `<a href="${href}" title="${label}"${href.toLowerCase() === here ? ' aria-current="page"' : ""}>${icon(d)}<span>${label}</span></a>`).join("");
  const bar = document.createElement("div");
  bar.className = "wbar";
  bar.innerHTML = `<button type="button" aria-controls="wnav" aria-expanded="false">☰ Menu</button><b>Wayfair Town</b>`;
  const back = document.createElement("div"); back.className = "wback";
  document.body.prepend(back); document.body.prepend(nav); document.body.prepend(bar);

  const narrow = () => matchMedia("(max-width:899px)").matches;
  const tog = nav.querySelector(".tog"), menuBtn = bar.querySelector("button");
  let mini = false; try { mini = localStorage.getItem("wt-nav") === "mini" } catch (e) {}
  function paint() {
    document.body.classList.toggle("nav-mini", mini && !narrow());
    if (narrow()) { tog.textContent = "✕"; tog.setAttribute("aria-label", "Close menu"); tog.title = "Close menu"; }
    else { tog.textContent = mini ? "»" : "«"; tog.setAttribute("aria-label", mini ? "Expand menu" : "Collapse menu"); tog.title = mini ? "Expand menu" : "Collapse menu"; }
  }
  const setOpen = o => { document.body.classList.toggle("nav-open", o); menuBtn.setAttribute("aria-expanded", String(o)); };
  tog.addEventListener("click", () => {
    if (narrow()) { setOpen(false); menuBtn.focus(); return; }
    mini = !mini; try { localStorage.setItem("wt-nav", mini ? "mini" : "full") } catch (e) {} paint();
  });
  menuBtn.addEventListener("click", () => { setOpen(true); nav.querySelector("a").focus(); });
  back.addEventListener("click", () => setOpen(false));
  document.addEventListener("keydown", e => { if (e.key === "Escape" && document.body.classList.contains("nav-open")) { setOpen(false); menuBtn.focus(); } });
  matchMedia("(max-width:899px)").addEventListener("change", () => { setOpen(false); paint(); });
  paint();
})();
