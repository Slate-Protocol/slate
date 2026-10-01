import { getPage } from "@/lib/content";
import { flat } from "@/lib/nav";

export const dynamic = "force-static";

/** The search index: built once, fetched by the search dialog the first time it opens. */
export async function GET() {
  const pages = await Promise.all(
    flat.map(async (p) => {
      const page = await getPage(p.slug);
      return { slug: p.slug, title: page.title, group: p.group, headings: page.headings, text: page.text };
    }),
  );
  return Response.json(pages);
}
