import "server-only";
import { readFile } from "node:fs/promises";
import path from "node:path";
import rehypeShiki from "@shikijs/rehype";
import { toString } from "hast-util-to-string";
import type { Element, Root } from "hast";
import rehypeSlug from "rehype-slug";
import rehypeStringify from "rehype-stringify";
import remarkGfm from "remark-gfm";
import remarkParse from "remark-parse";
import remarkRehype from "remark-rehype";
import { unified } from "unified";
import { visit } from "unist-util-visit";

import type { Heading } from "./types";
export type { Heading };
export type Page = { slug: string; title: string; description: string; html: string; headings: Heading[]; text: string };

const root = path.join(process.cwd(), "content");

function frontmatter(source: string): { data: Record<string, string>; body: string } {
  const m = /^---\n([\s\S]*?)\n---\n/.exec(source);
  if (!m) return { data: {}, body: source };
  const data: Record<string, string> = {};
  for (const line of m[1].split("\n")) {
    const i = line.indexOf(":");
    if (i > 0) data[line.slice(0, i).trim()] = line.slice(i + 1).trim();
  }
  return { data, body: source.slice(m[0].length) };
}

/** Collects h2/h3 for the table of contents and opens external links in a new tab. */
function collect(headings: Heading[]) {
  return () => (tree: Root) => {
    visit(tree, "element", (node: Element) => {
      if ((node.tagName === "h2" || node.tagName === "h3") && node.properties?.id) {
        headings.push({ id: String(node.properties.id), text: toString(node), depth: node.tagName === "h2" ? 2 : 3 });
      }
      if (node.tagName === "a" && typeof node.properties?.href === "string" && /^https?:/.test(node.properties.href)) {
        node.properties.target = "_blank";
        node.properties.rel = ["noreferrer"];
      }
      if (node.tagName === "table") {
        node.properties = { ...node.properties, className: ["table"] };
      }
    });
  };
}

const cache = new Map<string, Promise<Page>>();

export function getPage(slug: string): Promise<Page> {
  let p = cache.get(slug);
  if (!p) {
    p = load(slug);
    cache.set(slug, p);
  }
  return p;
}

async function load(slug: string): Promise<Page> {
  const file = path.join(root, `${slug || "index"}.md`);
  const { data, body } = frontmatter(await readFile(file, "utf8"));
  const headings: Heading[] = [];
  const html = String(
    await unified()
      .use(remarkParse)
      .use(remarkGfm)
      .use(remarkRehype)
      .use(rehypeSlug)
      .use(collect(headings))
      .use(rehypeShiki, { themes: { light: "github-light", dark: "github-dark-dimmed" }, defaultColor: false })
      .use(rehypeStringify)
      .process(body),
  );
  const text = body
    .replace(/```[\s\S]*?```/g, " ")
    .replace(/[#>*_`|[\]()-]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
  return { slug, title: data.title ?? slug, description: data.description ?? "", html, headings, text };
}
