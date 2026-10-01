"use client";

import { useEffect, useState } from "react";
import type { Heading } from "@/lib/types";

/** "On this page", highlighting the section nearest the top of the viewport. */
export function Toc({ headings }: { headings: Heading[] }) {
  const [active, setActive] = useState<string | null>(null);

  useEffect(() => {
    const els = headings.map((h) => document.getElementById(h.id)).filter((x): x is HTMLElement => !!x);
    const io = new IntersectionObserver(
      (entries) => {
        const visible = entries.filter((e) => e.isIntersecting).sort((a, b) => a.boundingClientRect.top - b.boundingClientRect.top);
        if (visible[0]) setActive(visible[0].target.id);
      },
      { rootMargin: "-80px 0px -65% 0px" },
    );
    els.forEach((el) => io.observe(el));
    return () => io.disconnect();
  }, [headings]);

  if (headings.length === 0) return <div className="hidden w-[220px] shrink-0 xl:block" />;
  return (
    <aside className="sticky top-24 hidden h-fit max-h-[calc(100vh-7rem)] w-[220px] shrink-0 overflow-y-auto xl:block">
      <p className="mb-3 text-xs font-semibold tracking-[0.05em] text-faint uppercase">On this page</p>
      <ul className="flex flex-col gap-1.5 border-l border-border text-[13.5px]">
        {headings.map((h) => (
          <li key={h.id}>
            <a
              href={`#${h.id}`}
              className={`-ml-px block border-l-2 py-0.5 ${h.depth === 3 ? "pl-6" : "pl-3"} ${
                active === h.id ? "border-active-bar text-text" : "border-transparent text-muted hover:text-text"
              }`}
            >
              {h.text}
            </a>
          </li>
        ))}
      </ul>
    </aside>
  );
}
