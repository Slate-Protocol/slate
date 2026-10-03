"use client";

import { useEffect, useRef, useState, useSyncExternalStore } from "react";
import { useChains, useConnection, useDisconnect, useSwitchChain } from "wagmi";
import { FallbackWalletDialog, openWalletModal, projectId, useResumeWalletConnect } from "./wallet";
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
  const { address, isConnected, isConnecting } = useConnection();
  const { disconnect } = useDisconnect();
  const [opening, setOpening] = useState(false);
  const [fallback, setFallback] = useState(false);
  useResumeWalletConnect();
  const open = async () => {
    if (!projectId) return setFallback(true);
    setOpening(true);
    try {
      await openWalletModal();
    } catch {
      setFallback(true); // the modal failed to load: still show the browser's own wallets and install links
    } finally {
      setOpening(false);
    }
  };

  if (isConnected && address) return <AccountMenu address={address} onDisconnect={() => disconnect()} />;
  return (
    <>
      <button
        type="button"
        disabled={opening}
        onClick={open}
        aria-haspopup="dialog"
        className="h-10 rounded-lg bg-accent px-3.5 text-sm font-semibold whitespace-nowrap text-on-accent hover:brightness-105 disabled:opacity-60"
      >
        {opening ? "Opening…" : isConnecting ? "Connecting…" : "Connect wallet"}
      </button>
      <FallbackWalletDialog open={fallback} onClose={() => setFallback(false)} />
    </>
  );
}

/** The connected wallet: address, copy, explorer, network (with a switch) and disconnect, in a dropdown. */
function AccountMenu({ address, onDisconnect }: { address: `0x${string}`; onDisconnect: () => void }) {
  const { chainId } = useConnection();
  const chains = useChains();
  const { mutate: switchChain, isPending: switching, variables, error } = useSwitchChain();
  const [open, setOpen] = useState(false);
  const [copied, setCopied] = useState(false);
  const ref = useRef<HTMLDivElement>(null);
  const chain = chains.find((c) => c.id === chainId);
  const explorer = (chain ?? chains[0]).blockExplorers?.default.url;

  useEffect(() => {
    if (!open) return;
    const onDown = (e: MouseEvent) => ref.current && !ref.current.contains(e.target as Node) && setOpen(false);
    const onKey = (e: KeyboardEvent) => e.key === "Escape" && setOpen(false);
    document.addEventListener("mousedown", onDown);
    document.addEventListener("keydown", onKey);
    return () => {
      document.removeEventListener("mousedown", onDown);
      document.removeEventListener("keydown", onKey);
    };
  }, [open]);

  const copy = async () => {
    try {
      await navigator.clipboard.writeText(address);
      setCopied(true);
      setTimeout(() => setCopied(false), 1500);
    } catch {}
  };
  const item = "flex min-h-10 w-full items-center gap-2 rounded-lg px-3 text-left text-sm hover:bg-surface-2";

  return (
    <div ref={ref} className="relative">
      <button
        type="button"
        aria-haspopup="menu"
        aria-expanded={open}
        onClick={() => setOpen((v) => !v)}
        className="flex h-10 items-center gap-2 rounded-lg border border-border px-3.5 font-mono text-sm whitespace-nowrap hover:border-faint"
      >
        <span className={`size-2 rounded-full ${chain ? "bg-ok" : "bg-warn"}`} aria-hidden="true" />
        {address.slice(0, 6)}…{address.slice(-4)}
        <svg viewBox="0 0 24 24" className="size-4 text-muted" fill="none" stroke="currentColor" strokeWidth="2" aria-hidden="true">
          <path d="m6 9 6 6 6-6" />
        </svg>
      </button>
      {open && (
        <div role="menu" aria-label="Wallet" className="absolute top-12 right-0 z-40 flex w-[min(92vw,320px)] flex-col gap-1 rounded-xl border border-border bg-surface p-2 shadow-xl">
          <div className="flex flex-col gap-1 px-3 py-2">
            <span className="text-xs text-muted">Connected</span>
            <span className="font-mono text-[13px] break-all">{address}</span>
          </div>
          <button type="button" role="menuitem" onClick={copy} className={item}>
            {copied ? "Copied" : "Copy address"}
          </button>
          {explorer && (
            <a role="menuitem" href={`${explorer}/address/${address}`} target="_blank" rel="noreferrer" className={item}>
              View on explorer <span className="text-muted">↗</span>
            </a>
          )}
          <div className="mt-1 flex flex-col gap-1 border-t border-border pt-2">
            <span className="px-3 text-xs text-muted">
              Network: <span className={chain ? "text-text" : "text-warn"}>{chain ? chain.name : `unsupported (chain ${chainId})`}</span>
            </span>
            {chains.map((c) => (
              <button
                key={c.id}
                type="button"
                role="menuitemradio"
                aria-checked={c.id === chainId}
                disabled={switching || c.id === chainId}
                onClick={() => switchChain({ chainId: c.id })}
                className={`${item} justify-between disabled:cursor-default`}
              >
                <span>{c.name}</span>
                <span className="text-xs text-muted">
                  {c.id === chainId ? "current" : switching && variables?.chainId === c.id ? "switching…" : "switch"}
                </span>
              </button>
            ))}
            {error && <span className="px-3 text-xs text-warn">{error.message.split("\n")[0]}</span>}
          </div>
          <div className="mt-1 border-t border-border pt-1">
            <button
              type="button"
              role="menuitem"
              onClick={() => {
                setOpen(false);
                onDisconnect();
              }}
              className={`${item} text-warn`}
            >
              Disconnect
            </button>
          </div>
        </div>
      )}
    </div>
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
