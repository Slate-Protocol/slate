// Screenshot gate for the docs: 1440 and 390, dark and light, plus the mobile drawer and the search dialog.
// Serves the production build (`pnpm build` first) and writes PNGs to ./screenshots.
//
//   node scripts/screenshots.mjs

import { spawn } from "node:child_process";
import { mkdirSync } from "node:fs";
import { chromium } from "@playwright/test";

const PORT = 4313;
const BASE = `http://127.0.0.1:${PORT}`;
const OUT = new URL("../screenshots/", import.meta.url).pathname;

const server = spawn("npx", ["next", "start", "-p", String(PORT)], { stdio: "ignore" });
const waitForServer = async () => {
  for (let i = 0; i < 60; i++) {
    try {
      if ((await fetch(BASE)).ok) return;
    } catch {}
    await new Promise((r) => setTimeout(r, 500));
  }
  throw new Error("server did not start");
};

const shots = [];
for (const page of ["", "disclosures", "router"]) {
  const name = page || "index";
  shots.push({ name: `${name}-1440-dark`, page, width: 1440, height: 900, theme: "dark" });
  shots.push({ name: `${name}-1440-light`, page, width: 1440, height: 900, theme: "light" });
  shots.push({ name: `${name}-390-dark`, page, width: 390, height: 844, theme: "dark", mobile: true });
  shots.push({ name: `${name}-390-light`, page, width: 390, height: 844, theme: "light", mobile: true });
}
shots.push({ name: "drawer-390-dark", page: "", width: 390, height: 844, theme: "dark", mobile: true, drawer: true, viewportOnly: true });
shots.push({ name: "drawer-390-light", page: "", width: 390, height: 844, theme: "light", mobile: true, drawer: true, viewportOnly: true });
shots.push({ name: "search-1440-dark", page: "", width: 1440, height: 900, theme: "dark", search: "USDG", viewportOnly: true });
shots.push({ name: "search-390-light", page: "", width: 390, height: 844, theme: "light", mobile: true, search: "straddle", viewportOnly: true });

try {
  await waitForServer();
  mkdirSync(OUT, { recursive: true });
  const browser = await chromium.launch();
  for (const s of shots) {
    const context = await browser.newContext({
      viewport: { width: s.width, height: s.height },
      deviceScaleFactor: s.mobile ? 2 : 1,
      isMobile: !!s.mobile,
      hasTouch: !!s.mobile,
      colorScheme: s.theme,
    });
    await context.addInitScript((theme) => localStorage.setItem("slate-theme", theme), s.theme);
    const page = await context.newPage();
    await page.goto(`${BASE}/${s.page}`, { waitUntil: "networkidle" });
    await page.evaluate(() => document.fonts.ready);
    if (s.drawer) await page.getByRole("button", { name: "Open navigation" }).click();
    if (s.search) {
      await page.getByRole("button", { name: /search the docs/i }).first().click();
      await page.getByPlaceholder(/Search/).fill(s.search);
      await page.waitForTimeout(400);
    }
    const scrollWidth = await page.evaluate(() => document.documentElement.scrollWidth);
    if (scrollWidth > s.width) console.warn(`${s.name}: horizontal overflow, scrollWidth ${scrollWidth}`);
    await page.screenshot({ path: `${OUT}${s.name}.png`, fullPage: !s.viewportOnly });
    console.log(`${s.name}.png`);
    await context.close();
  }
  await browser.close();
} finally {
  server.kill();
}
