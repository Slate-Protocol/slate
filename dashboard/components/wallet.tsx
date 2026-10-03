"use client";

import type { AppKitNetwork } from "@reown/appkit/networks";
import { useEffect, useRef } from "react";
import { arbitrum } from "viem/chains";
import { createConfig, http, injected, useConnect, useConnectors, type Config } from "wagmi";
import { robinhoodChain, robinhoodTestnet } from "@/lib/chains";

/**
 * Wallet connection. Reown AppKit is the one wallet library that supports wagmi 3 (RainbowKit and ConnectKit need
 * wagmi 2): its modal lists installed wallets, links to install the rest, and pairs a mobile wallet by WalletConnect
 * QR. It weighs ~240 KB gzipped, so the page starts on a plain wagmi config and AppKit is imported on the first click
 * (or at load, if the last session was a WalletConnect one, so it can resume). Its wagmi adapter is handed this same
 * config instead of building its own, so every hook on the page sees the connection it makes.
 *
 * WalletConnect needs a Reown project id (NEXT_PUBLIC_REOWN_PROJECT_ID). Without one, the button opens a small
 * fallback that lists the browser's own wallets and links to install one, so it never does nothing.
 */
export const projectId = process.env.NEXT_PUBLIC_REOWN_PROJECT_ID ?? "";

const networks: [AppKitNetwork, ...AppKitNetwork[]] = [robinhoodTestnet, robinhoodChain, arbitrum];
const transports = { [robinhoodTestnet.id]: http(), [robinhoodChain.id]: http(), [arbitrum.id]: http() };

export const wagmiConfig: Config = createConfig({
  chains: [robinhoodTestnet, robinhoodChain, arbitrum],
  connectors: [injected()],
  transports,
  ssr: true,
});

type Kit = {
  open: () => Promise<unknown>;
  setThemeMode: (m: "dark" | "light") => void;
  setThemeVariables: (v: Record<string, string>) => void;
};
let kit: Promise<Kit> | null = null;

const theme = () => (document.documentElement.dataset.theme === "light" ? "light" : "dark");
// The dashboard's own accent: gold, darkened in light mode for contrast (--accent-text in globals.css).
const accent = () => (theme() === "light" ? "#7a5b00" : "#e8c547");

function loadKit(): Promise<Kit> {
  kit ??= Promise.all([import("@reown/appkit/react"), import("@reown/appkit-adapter-wagmi")]).then(([{ createAppKit }, { WagmiAdapter }]) => {
    // The adapter's (TypeScript-private) createConfig would build a second wagmi config; give it the page's instead.
    class SharedConfigAdapter extends WagmiAdapter {}
    Object.defineProperty(SharedConfigAdapter.prototype, "createConfig", {
      value(this: { wagmiChains: unknown; wagmiConfig: Config }, params: { networks: { chainNamespace?: string }[] }) {
        this.wagmiChains = params.networks.filter((n) => n.chainNamespace === "eip155");
        this.wagmiConfig = wagmiConfig;
      },
    });
    const adapter = new SharedConfigAdapter({ projectId, networks, transports });
    return createAppKit({
      adapters: [adapter],
      networks,
      defaultNetwork: robinhoodTestnet,
      projectId,
      metadata: {
        name: "Slate",
        description: "Multiplier-correct, fail-closed price feeds for Robinhood stock tokens",
        url: "https://app.slate.0xo.in",
        icons: ["https://app.slate.0xo.in/favicon.svg"],
      },
      themeMode: theme(),
      // The page's IBM Plex, already loaded, instead of AppKit's fonts from Reown's server. AppKit has no option for its
      // monospace face, so globals.css sets that variable (--apkt-fontFamily-mono) too.
      themeVariables: { "--w3m-accent": accent(), "--w3m-font-family": '"IBM Plex Sans", ui-sans-serif, system-ui, sans-serif', "--w3m-border-radius-master": "2px" },
      features: { analytics: false, email: false, socials: false, swaps: false, onramp: false, send: false, receive: false, history: false },
    });
  });
  return kit;
}

/** Opens Reown's wallet modal, loading it on first use. */
export async function openWalletModal() {
  if (!projectId) throw new Error("no Reown project id");
  const k = await loadKit();
  k.setThemeMode(theme());
  k.setThemeVariables({ "--w3m-accent": accent() });
  await k.open();
}

/** If the last session was WalletConnect, load AppKit now so it can resume that session. */
export function useResumeWalletConnect() {
  useEffect(() => {
    if (!projectId) return;
    try {
      if (JSON.parse(localStorage.getItem("wagmi.recentConnectorId") ?? "null") === "walletConnect") void loadKit();
    } catch {}
  }, []);
}

const INSTALL = [
  { name: "MetaMask", url: "https://metamask.io/download/" },
  { name: "Rabby", url: "https://rabby.io/" },
  { name: "Base (Coinbase Wallet)", url: "https://www.coinbase.com/wallet/downloads" },
];

/** The fallback when no Reown project id is set: the browser's own wallets, or where to get one. */
export function FallbackWalletDialog({ open, onClose }: { open: boolean; onClose: () => void }) {
  const ref = useRef<HTMLDialogElement>(null);
  const connectors = useConnectors();
  const { connect, isPending, error } = useConnect();
  // A real installed wallet announces itself (EIP-6963); the generic "Injected" entry only exists if window.ethereum does.
  const found = connectors.filter((c) => c.type === "injected" && (c.id !== "injected" || (typeof window !== "undefined" && "ethereum" in window)));

  useEffect(() => {
    const d = ref.current;
    if (!d) return;
    if (open && !d.open) d.showModal();
    if (!open && d.open) d.close();
  }, [open]);

  return (
    <dialog
      ref={ref}
      onClose={onClose}
      onClick={(e) => e.target === ref.current && onClose()}
      aria-labelledby="wallet-title"
      className="m-auto w-[min(92vw,400px)] rounded-2xl border border-border bg-surface p-0 text-text backdrop:bg-black/60"
    >
      <div className="flex flex-col gap-4 p-5">
        <div className="flex items-center justify-between gap-3">
          <h2 id="wallet-title" className="text-lg font-semibold">
            Connect a wallet
          </h2>
          <button type="button" onClick={onClose} aria-label="Close" className="flex size-9 items-center justify-center rounded-lg text-muted hover:text-text">
            ✕
          </button>
        </div>
        {found.length > 0 ? (
          <ul className="flex flex-col gap-2">
            {found.map((c) => (
              <li key={c.uid}>
                <button
                  type="button"
                  disabled={isPending}
                  onClick={() => connect({ connector: c }, { onSuccess: onClose })}
                  className="flex min-h-12 w-full items-center gap-3 rounded-xl border border-border px-4 text-left font-medium hover:border-faint disabled:opacity-60"
                >
                  {/* eslint-disable-next-line @next/next/no-img-element */}
                  {c.icon && <img src={c.icon} alt="" className="size-6 rounded" />}
                  {c.name}
                </button>
              </li>
            ))}
          </ul>
        ) : (
          <p className="text-sm text-muted">No wallet was found in this browser. Install one, then reload this page:</p>
        )}
        <ul className="flex flex-col gap-2">
          {INSTALL.map((w) => (
            <li key={w.name}>
              <a
                href={w.url}
                target="_blank"
                rel="noreferrer"
                className="flex min-h-11 items-center justify-between rounded-xl border border-border px-4 text-sm hover:border-faint"
              >
                <span>Get {w.name}</span>
                <span className="text-muted">↗</span>
              </a>
            </li>
          ))}
        </ul>
        {error && <p className="text-sm text-warn">{error.message.split("\n")[0]}</p>}
        <p className="text-xs text-faint">You can read every feed without a wallet. You only need one to create, lend or run the Lab.</p>
      </div>
    </dialog>
  );
}
