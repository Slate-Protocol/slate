"use client";

import { useRouter } from "next/navigation";
import { useEffect, useMemo, useRef, useState } from "react";

type Entry = { slug: string; title: string; group: string; headings: { id: string; text: string }[]; text: string };
type Hit = { href: string; title: string; context: string; snippet: string; score: number };

function snippet(text: string, terms: string[]): string {
  const lower = text.toLowerCase();
  const at = Math.max(0, ...terms.map((t) => lower.indexOf(t)).filter((i) => i >= 0).slice(0, 1));
  const start = Math.max(0, at - 50);
  return (start > 0 ? "…" : "") + text.slice(start, start + 150).trim() + "…";
}

function search(index: Entry[], query: string): Hit[] {
  const terms = query.toLowerCase().split(/\s+/).filter(Boolean);
  if (!terms.length) return [];
  const hits: Hit[] = [];
  for (const e of index) {
    const title = e.title.toLowerCase();
    const body = e.text.toLowerCase();
    if (!terms.every((t) => title.includes(t) || body.includes(t) || e.headings.some((h) => h.text.toLowerCase().includes(t)))) continue;
    const score = terms.reduce((s, t) => s + (title.includes(t) ? 10 : 0) + Math.min(5, body.split(t).length - 1), 0);
    hits.push({ href: `/${e.slug}`, title: e.title, context: e.group, snippet: snippet(e.text, terms), score });
    for (const h of e.headings) {
      const ht = h.text.toLowerCase();
      if (terms.every((t) => ht.includes(t))) {
        hits.push({ href: `/${e.slug}#${h.id}`, title: h.text, context: e.title, snippet: "", score: score + 8 });
      }
    }
  }
  return hits.sort((a, b) => b.score - a.score).slice(0, 12);
}

export function Search() {
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState("");
  const [index, setIndex] = useState<Entry[] | null>(null);
  const [selected, setSelected] = useState(0);
  const input = useRef<HTMLInputElement>(null);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "k") {
        e.preventDefault();
        setOpen(true);
      }
      if (e.key === "/" && !(e.target instanceof HTMLInputElement)) {
        e.preventDefault();
        setOpen(true);
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, []);

  useEffect(() => {
    if (!open) return;
    input.current?.focus();
    if (!index) {
      fetch("/search.json")
        .then((r) => r.json())
        .then(setIndex)
        .catch(() => setIndex([]));
    }
  }, [open, index]);

  const hits = useMemo(() => (index ? search(index, query) : []), [index, query]);

  const go = (href: string) => {
    setOpen(false);
    setQuery("");
    router.push(href);
  };

  return (
    <>
      <button
        type="button"
        aria-label="Search the docs"
        onClick={() => setOpen(true)}
        className="flex h-10 min-w-0 items-center gap-2.5 rounded-lg border border-border bg-surface px-3 text-sm text-muted hover:border-faint md:w-[340px]"
      >
        <svg viewBox="0 0 24 24" className="size-4 shrink-0" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" aria-hidden="true">
          <circle cx="11" cy="11" r="7" />
          <path d="m20 20-3.5-3.5" />
        </svg>
        <span className="hidden sm:inline">Search the docs</span>
        <kbd className="ml-auto hidden rounded border border-border px-1.5 font-mono text-xs md:inline">⌘K</kbd>
      </button>

      {open && (
        <div className="fixed inset-0 z-50 flex items-start justify-center bg-scrim px-4 pt-[12vh]" onClick={() => setOpen(false)}>
          <div
            role="dialog"
            aria-label="Search the docs"
            className="w-full max-w-[620px] overflow-hidden rounded-2xl border border-border bg-surface shadow-2xl"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="flex items-center gap-3 border-b border-border px-4">
              <svg viewBox="0 0 24 24" className="size-5 text-muted" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" aria-hidden="true">
                <circle cx="11" cy="11" r="7" />
                <path d="m20 20-3.5-3.5" />
              </svg>
              <input
                ref={input}
                value={query}
                placeholder="Search: CRWD, STRADDLE, USDG…"
                onChange={(e) => {
                  setQuery(e.target.value);
                  setSelected(0);
                }}
                onKeyDown={(e) => {
                  if (e.key === "Escape") setOpen(false);
                  if (e.key === "ArrowDown") setSelected((s) => Math.min(s + 1, hits.length - 1));
                  if (e.key === "ArrowUp") setSelected((s) => Math.max(s - 1, 0));
                  if (e.key === "Enter" && hits[selected]) go(hits[selected].href);
                }}
                className="h-14 flex-1 bg-transparent text-base outline-none placeholder:text-faint"
              />
              <kbd className="rounded border border-border px-1.5 font-mono text-xs text-muted">esc</kbd>
            </div>
            <ul className="max-h-[55vh] overflow-y-auto p-2">
              {query && hits.length === 0 && <li className="px-3 py-6 text-center text-sm text-muted">No results for “{query}”.</li>}
              {hits.map((h, i) => (
                <li key={h.href}>
                  <button
                    type="button"
                    onMouseEnter={() => setSelected(i)}
                    onClick={() => go(h.href)}
                    className={`flex w-full flex-col items-start gap-0.5 rounded-lg px-3 py-2.5 text-left ${i === selected ? "bg-surface-2" : ""}`}
                  >
                    <span className="text-xs text-muted">{h.context}</span>
                    <span className="font-semibold">{h.title}</span>
                    {h.snippet && <span className="line-clamp-2 text-sm text-muted">{h.snippet}</span>}
                  </button>
                </li>
              ))}
            </ul>
          </div>
        </div>
      )}
    </>
  );
}
