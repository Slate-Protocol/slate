"use client";

import Link from "next/link";
import { useState, useSyncExternalStore } from "react";
import { nav } from "@/lib/nav";
import { Search } from "./search";

const DASHBOARD = process.env.NEXT_PUBLIC_DASHBOARD_URL ?? "https://app.slate.0xo.in";
const GITHUB = "https://github.com/Slate-Protocol/slate";

function Mark({ className = "size-[22px]" }: { className?: string }) {
  return (
    <svg viewBox="0 0 32 32" aria-hidden="true" className={className} fill="currentColor">
      <rect x="13" y="3" width="6" height="26" />
      <rect x="4" y="8" width="9" height="5" />
      <rect x="19" y="19" width="9" height="5" />
    </svg>
  );
}

type Theme = "dark" | "light";
const readTheme = (): Theme => (document.documentElement.dataset.theme === "light" ? "light" : "dark");
const subscribeTheme = (onChange: () => void) => {
  const o = new MutationObserver(onChange);
  o.observe(document.documentElement, { attributes: true, attributeFilter: ["data-theme"] });
  return () => o.disconnect();
};

function ThemeToggle() {
  const theme = useSyncExternalStore(subscribeTheme, readTheme, () => "dark" as Theme);
  const next: Theme = theme === "dark" ? "light" : "dark";
  return (
    <button
      type="button"
      aria-label={`Switch to ${next} theme`}
      onClick={() => {
        document.documentElement.dataset.theme = next;
        try {
          localStorage.setItem("slate-theme", next);
        } catch {}
      }}
      className="flex size-10 items-center justify-center rounded-lg border border-border text-muted hover:text-text"
    >
      {theme === "dark" ? (
        <svg viewBox="0 0 24 24" className="size-4" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" aria-hidden="true">
          <circle cx="12" cy="12" r="4" />
          <path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4" />
        </svg>
      ) : (
        <svg viewBox="0 0 24 24" className="size-4" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
          <path d="M21 12.8A9 9 0 1 1 11.2 3a7 7 0 0 0 9.8 9.8Z" />
        </svg>
      )}
    </button>
  );
}

function Sidebar({ current, onNavigate }: { current: string; onNavigate?: () => void }) {
  return (
    <nav aria-label="Documentation" className="flex flex-col gap-6">
      {nav.map((group) => (
        <div key={group.title} className="flex flex-col gap-0.5">
          <span className="px-3 pb-1.5 text-xs font-semibold tracking-[0.05em] text-faint uppercase">{group.title}</span>
          {group.items.map((item) => {
            const active = item.slug === current;
            return (
              <Link
                key={item.slug}
                href={`/${item.slug}`}
                onClick={onNavigate}
                aria-current={active ? "page" : undefined}
                className={`rounded-lg border-l-2 px-3 py-1.5 text-[14.5px] ${
                  active ? "border-active-bar bg-surface-2 font-semibold text-text" : "border-transparent text-muted hover:text-text"
                }`}
              >
                {item.title}
              </Link>
            );
          })}
        </div>
      ))}
    </nav>
  );
}

export function DocsShell({ current, children }: { current: string; children: React.ReactNode }) {
  const [drawer, setDrawer] = useState(false);
  return (
    <div className="min-h-screen">
      <header className="sticky top-0 z-30 border-b border-border bg-bg/90 backdrop-blur">
        <div className="mx-auto flex h-16 max-w-[1440px] items-center gap-3 px-4 lg:px-6">
          <button
            type="button"
            aria-label={drawer ? "Close navigation" : "Open navigation"}
            aria-expanded={drawer}
            onClick={() => setDrawer(!drawer)}
            className="flex size-10 items-center justify-center rounded-lg border border-border lg:hidden"
          >
            <svg viewBox="0 0 24 24" className="size-5" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" aria-hidden="true">
              {drawer ? <path d="M6 6l12 12M18 6 6 18" /> : <path d="M4 7h16M4 12h16M4 17h16" />}
            </svg>
          </button>
          <Link href="/" className="flex items-center gap-2 font-semibold whitespace-nowrap">
            <Mark />
            <span>Slate</span>
            <span className="font-normal text-muted">docs</span>
          </Link>
          <div className="ml-auto flex flex-1 items-center justify-end gap-2 lg:ml-10 lg:justify-between">
            <Search />
            <div className="flex items-center gap-1">
              <a href={DASHBOARD} target="_blank" rel="noreferrer" className="hidden rounded-lg px-3 py-2 text-sm text-muted hover:text-text md:block">
                Dashboard ↗
              </a>
              <a href={GITHUB} target="_blank" rel="noreferrer" className="hidden rounded-lg px-3 py-2 text-sm text-muted hover:text-text md:block">
                GitHub ↗
              </a>
              <ThemeToggle />
            </div>
          </div>
        </div>
      </header>

      {drawer && (
        <div className="fixed inset-0 top-16 z-20 flex lg:hidden">
          <div className="w-[300px] max-w-[85vw] overflow-y-auto border-r border-border bg-bg px-3 py-5">
            <Sidebar current={current} onNavigate={() => setDrawer(false)} />
            <div className="mt-6 flex flex-col gap-1 border-t border-border pt-4 text-sm">
              <a href={DASHBOARD} target="_blank" rel="noreferrer" className="rounded-lg px-3 py-2 text-muted hover:text-text">
                Dashboard ↗
              </a>
              <a href={GITHUB} target="_blank" rel="noreferrer" className="rounded-lg px-3 py-2 text-muted hover:text-text">
                GitHub ↗
              </a>
            </div>
          </div>
          <button type="button" aria-label="Close navigation" onClick={() => setDrawer(false)} className="flex-1 bg-scrim" />
        </div>
      )}

      <div className="mx-auto flex max-w-[1440px]">
        <aside className="sticky top-16 hidden h-[calc(100vh-4rem)] w-[280px] shrink-0 overflow-y-auto border-r border-border px-3 py-7 lg:block">
          <Sidebar current={current} />
        </aside>
        <main className="min-w-0 flex-1 px-4 py-9 sm:px-8 lg:px-12">
          <div className="mx-auto max-w-[1000px]">{children}</div>
        </main>
      </div>
    </div>
  );
}
