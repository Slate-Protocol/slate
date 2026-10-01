"use client";

import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { createContext, useContext, useState } from "react";
import { createConfig, http, injected, WagmiProvider } from "wagmi";
import { arbitrum } from "viem/chains";
import { robinhoodChain, robinhoodTestnet } from "@/lib/chains";

const wagmiConfig = createConfig({
  chains: [robinhoodTestnet, robinhoodChain, arbitrum],
  connectors: [injected()],
  transports: {
    [robinhoodTestnet.id]: http(),
    [robinhoodChain.id]: http(),
    [arbitrum.id]: http(),
  },
  ssr: true,
});

export type Quote = "USD" | "USDG";
const QuoteContext = createContext<{ quote: Quote; setQuote: (q: Quote) => void }>({
  quote: "USD",
  setQuote: () => {},
});
export const useQuote = () => useContext(QuoteContext);

export function Providers({ children }: { children: React.ReactNode }) {
  const [queryClient] = useState(() => new QueryClient());
  const [quote, setQuote] = useState<Quote>("USD");
  return (
    <WagmiProvider config={wagmiConfig}>
      <QueryClientProvider client={queryClient}>
        <QuoteContext.Provider value={{ quote, setQuote }}>{children}</QuoteContext.Provider>
      </QueryClientProvider>
    </WagmiProvider>
  );
}
