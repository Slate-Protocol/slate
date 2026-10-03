"use client";

import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { createContext, useContext, useState } from "react";
import { WagmiProvider } from "wagmi";
import { wagmiConfig } from "./wallet";

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
