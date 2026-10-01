"use client";

import { useSyncExternalStore } from "react";
import { useConnect, useConnection, useConnectors, useDisconnect } from "wagmi";
import { useQuote, type Quote } from "./providers";

export function Mark({ className = "size-[22px]" }: { className?: string }) {
  return (
    <svg viewBox="0 0 32 32" aria-hidden="true" className={className} fill="currentColor">
      <rect x="13" y="3" width="6" height="26" />
      <rect x="4" y="8" width="9" height="5" />
      <rect x="19" y="19" width="9" height="5" />
    </svg>
  );
}

export function QuoteToggle({ wide = false }: { wide?: boolean }) {
  const { quote, setQuote } = useQuote();
  const option = (q: Quote) => (
    <button
      key={q}
      type="button"
      aria-pressed={quote === q}
      onClick={() => setQuote(q)}
      className={`${wide ? "min-h-11 flex-1" : "px-3 py-2"} text-sm ${
        quote === q ? "bg-surface-2 font-semibold text-text" : "text-muted hover:text-text"
      }`}
    >
      {q}
    </button>
  );
  return (
    <div role="group" aria-label="Quote currency" className={`${wide ? "flex" : "inline-flex"} overflow-hidden rounded-lg border border-border`}>
      {option("USD")}
      {option("USDG")}
    </div>
  );
}

export function ConnectWallet() {
  const { address, isConnected } = useConnection();
  const connectors = useConnectors();
  const { connect, isPending } = useConnect();
  const { disconnect } = useDisconnect();

  if (isConnected && address) {
    return (
      <button
        type="button"
        onClick={() => disconnect()}
        title="Disconnect"
        className="h-10 rounded-lg border border-border px-3.5 font-mono text-sm whitespace-nowrap hover:border-faint"
      >
        {address.slice(0, 6)}…{address.slice(-4)}
      </button>
    );
  }
  return (
    <button
      type="button"
      disabled={isPending || connectors.length === 0}
      onClick={() => connectors[0] && connect({ connector: connectors[0] })}
      className="h-10 rounded-lg bg-accent px-3.5 text-sm font-semibold whitespace-nowrap text-on-accent hover:brightness-105 disabled:opacity-60"
    >
      {isPending ? "Connecting…" : "Connect wallet"}
    </button>
  );
}

type Theme = "dark" | "light";
const readTheme = (): Theme => (document.documentElement.dataset.theme === "light" ? "light" : "dark");
const subscribeTheme = (onChange: () => void) => {
  const o = new MutationObserver(onChange);
  o.observe(document.documentElement, { attributes: true, attributeFilter: ["data-theme"] });
  return () => o.disconnect();
};

export function ThemeToggle() {
  const theme = useSyncExternalStore(subscribeTheme, readTheme, () => "dark" as Theme);
  const next: Theme = theme === "dark" ? "light" : "dark";
  return (
    <button
      type="button"
      onClick={() => {
        document.documentElement.dataset.theme = next;
        try {
          localStorage.setItem("slate-theme", next);
        } catch {}
      }}
      className="flex min-h-10 w-full items-center gap-2 rounded-lg px-3 text-sm text-muted hover:text-text"
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
      {theme === "dark" ? "Light theme" : "Dark theme"}
    </button>
  );
}
