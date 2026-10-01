import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { DocsShell } from "@/components/shell";
import { Toc } from "@/components/toc";
import { getPage } from "@/lib/content";
import { flat } from "@/lib/nav";

type Params = { slug?: string[] };

export const dynamicParams = false;

export function generateStaticParams(): Params[] {
  return flat.map((p) => ({ slug: p.slug ? p.slug.split("/") : [] }));
}

const slugOf = (params: Params) => (params.slug ?? []).join("/");

export async function generateMetadata({ params }: { params: Promise<Params> }): Promise<Metadata> {
  const slug = slugOf(await params);
  if (!flat.some((p) => p.slug === slug)) return {};
  const page = await getPage(slug);
  return { title: slug ? page.title : { absolute: "Slate docs" }, description: page.description };
}

export default async function DocPage({ params }: { params: Promise<Params> }) {
  const slug = slugOf(await params);
  const index = flat.findIndex((p) => p.slug === slug);
  if (index < 0) notFound();
  const page = await getPage(slug);
  const prev = flat[index - 1];
  const next = flat[index + 1];
  const href = (s: string) => `/${s}`;

  return (
    <DocsShell current={slug}>
      <div className="flex gap-10">
        <article className="min-w-0 flex-1">
          <p className="text-sm font-medium text-accent-text">{flat[index].group}</p>
          <h1 className="mt-1.5 text-[32px] leading-tight font-semibold tracking-[-0.02em]">{page.title}</h1>
          {page.description && <p className="mt-2.5 text-lg text-muted">{page.description}</p>}
          <div className="prose mt-8" dangerouslySetInnerHTML={{ __html: page.html }} />
          <nav aria-label="Pages" className="mt-14 grid grid-cols-1 gap-3 border-t border-border pt-6 sm:grid-cols-2">
            {prev ? (
              <Link href={href(prev.slug)} className="rounded-xl border border-border p-4 hover:border-faint">
                <span className="text-xs text-muted">Previous</span>
                <span className="mt-0.5 block font-semibold">{prev.title}</span>
              </Link>
            ) : (
              <span />
            )}
            {next && (
              <Link href={href(next.slug)} className="rounded-xl border border-border p-4 text-right hover:border-faint">
                <span className="text-xs text-muted">Next</span>
                <span className="mt-0.5 block font-semibold">{next.title}</span>
              </Link>
            )}
          </nav>
          <p className="mt-8 text-sm text-faint">
            <a
              href={`https://github.com/Slate-Protocol/slate/blob/main/docs/content/${slug || "index"}.md`}
              target="_blank"
              rel="noreferrer"
              className="hover:text-muted"
            >
              Edit this page on GitHub
            </a>
          </p>
        </article>
        <Toc headings={page.headings} />
      </div>
    </DocsShell>
  );
}
