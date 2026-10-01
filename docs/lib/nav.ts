export type NavItem = { slug: string; title: string };
export type NavGroup = { title: string; items: NavItem[] };

/** Sidebar order. `slug` is the path under /, and the file under content/ (index for ""). */
export const nav: NavGroup[] = [
  {
    title: "Getting started",
    items: [
      { slug: "", title: "Introduction" },
      { slug: "quickstart", title: "Quickstart" },
      { slug: "verify-crwd", title: "Verify CRWD yourself" },
    ],
  },
  {
    title: "Concepts",
    items: [
      { slug: "concepts/multipliers", title: "The multiplier problem" },
      { slug: "concepts/statuses", title: "Feed statuses" },
      { slug: "concepts/calendar", title: "Market calendar" },
      { slug: "concepts/signed-prices", title: "Signed prices" },
    ],
  },
  {
    title: "Building with Slate",
    items: [
      { slug: "slatefeed", title: "SlateFeed" },
      { slug: "basket", title: "Basket and NAV feed" },
      { slug: "router", title: "Router and the refused route" },
      { slug: "usdg", title: "USDG integration" },
    ],
  },
  {
    title: "Try it",
    items: [
      { slug: "lab", title: "Corporate Action Lab" },
      { slug: "deployments", title: "Deployments" },
    ],
  },
  {
    title: "Project",
    items: [
      { slug: "publisher", title: "Publisher" },
      { slug: "stylus", title: "Stylus benchmark" },
      { slug: "prior-art", title: "Prior art" },
      { slug: "disclosures", title: "Disclosures" },
      { slug: "security", title: "Security and limitations" },
    ],
  },
];

export const flat: (NavItem & { group: string })[] = nav.flatMap((g) => g.items.map((i) => ({ ...i, group: g.title })));
