"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useState } from "react";
import { ConnectWallet, Mark, QuoteToggle, ThemeToggle } from "./controls";

const DOCS_URL = process.env.NEXT_PUBLIC_DOCS_URL ?? "https://docs.slate.0xo.in";

/** Every sidebar entry is its own route, so a section can be linked, opened in a tab and reached with Back. */
const routes = [
  { href: "/feeds", label: "Feeds" },
  { href: "/basket", label: "Basket" },
  { href: "/create", label: "Create & redeem" },
  { href: "/lend", label: "Lend" },
  { href: "/lab", label: "Lab", lab: true },
  { href: "/signers", label: "Signers" },
  { href: "/accuracy", label: "Accuracy vs Chainlink" },
  { href: "/playground", label: "Playground" },
];

function LabTag() {
  return <span className="rounded bg-lab-bg px-1.5 py-px text-[11px] font-semibold text-lab">LAB</span>;
}

function NavLinks({ onNavigate, tall = false }: { onNavigate?: () => void; tall?: boolean }) {
  const pathname = usePathname();
  const active = pathname === "/" ? "/feeds" : pathname;
  return (
    <nav aria-label="Dashboard" className="flex flex-col gap-0.5">
      {routes.map((r) => {
        const current = r.href === active;
        return (
          <Link
            key={r.href}
            href={r.href}
            onClick={onNavigate}
            aria-current={current ? "page" : undefined}
            className={`flex items-center gap-2 rounded-lg px-3 ${tall ? "min-h-11" : "min-h-10"} ${
              current ? "bg-surface-2 font-semibold text-text shadow-[inset_3px_0_0_var(--active-bar)]" : "text-muted hover:text-text"
            }`}
          >
            {r.label}
            {r.lab && <LabTag />}
          </Link>
        );
      })}
      <a href={DOCS_URL} onClick={onNavigate} className={`flex items-center gap-2 rounded-lg px-3 text-muted hover:text-text ${tall ? "min-h-11" : "min-h-10"}`}>
        Docs
        <svg viewBox="0 0 24 24" className="size-3.5" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" aria-hidden="true">
          <path d="M7 17 17 7M8 7h9v9" />
        </svg>
      </a>
    </nav>
  );
}

export function Shell({ children }: { children: React.ReactNode }) {
  const [drawer, setDrawer] = useState(false);

  return (
    <div className="min-h-screen">
      <header className="sticky top-0 z-20 flex h-[57px] items-center gap-3 border-b border-border bg-surface px-4">
        <button
          type="button"
          aria-label={drawer ? "Close navigation" : "Open navigation"}
          aria-expanded={drawer}
          aria-controls="drawer"
          onClick={() => setDrawer((v) => !v)}
          className="inline-flex size-11 items-center justify-center rounded-lg border border-border lg:hidden"
        >
          <svg viewBox="0 0 24 24" className="size-5" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" aria-hidden="true">
            {drawer ? <path d="M6 6l12 12M18 6 6 18" /> : <path d="M4 7h16M4 12h16M4 17h16" />}
          </svg>
        </button>
        <Link href="/feeds" className="flex items-center gap-2 text-text" aria-label="Slate dashboard home">
          <Mark />
          <span className="text-[17px] font-semibold">Slate</span>
        </Link>
        <div className="flex-1" />
        <div className="hidden lg:block">
          <QuoteToggle />
        </div>
        <ConnectWallet />
      </header>

      {drawer && (
        <div id="drawer" className="fixed inset-x-0 top-[57px] bottom-0 z-30 flex lg:hidden">
          <div className="flex h-full w-[280px] max-w-[82%] flex-col gap-3 overflow-y-auto border-r border-border bg-surface p-3">
            <NavLinks onNavigate={() => setDrawer(false)} tall />
            <div className="flex flex-col gap-2 border-t border-border pt-3">
              <span className="text-xs tracking-[0.04em] text-muted uppercase">Quote in</span>
              <QuoteToggle wide />
            </div>
            <div className="border-t border-border pt-2">
              <ThemeToggle />
            </div>
          </div>
          <button type="button" aria-label="Close navigation" onClick={() => setDrawer(false)} className="flex-1 bg-scrim" />
        </div>
      )}

      <div className="flex items-start">
        <div className="hidden w-[232px] shrink-0 self-stretch border-r border-border bg-surface lg:block">
        <aside className="sticky top-[57px] flex h-[calc(100vh-57px)] flex-col overflow-y-auto px-3 py-4">
          <NavLinks />
          <div className="mt-auto flex flex-col gap-1 border-t border-border pt-3">
            <span className="px-3 text-[13px] text-muted">Networks</span>
            <span className="px-3 text-[13px]">Robinhood Chain</span>
            <span className="px-3 text-[13px]">Robinhood Chain testnet</span>
            <span className="px-3 text-[13px]">Arbitrum One</span>
            <div className="mt-2">
              <ThemeToggle />
            </div>
          </div>
        </aside>
        </div>
        <main className="flex min-w-0 max-w-[1180px] flex-1 flex-col gap-5 px-4 pt-5 pb-12 lg:px-8 lg:pt-7 lg:pb-16">{children}</main>
      </div>
    </div>
  );
}
