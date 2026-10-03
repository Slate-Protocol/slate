// Gate only: /history from the test Postgres, /board proxied from the live publisher. Signs and submits nothing.
import { createServer } from "node:http";
import { readHistory } from "./history.ts";
createServer(async (req, res) => {
  const h = { "content-type": "application/json", "access-control-allow-origin": "*" };
  if (req.url?.startsWith("/history")) { res.writeHead(200, h); res.end(JSON.stringify(await readHistory())); return; }
  const r = await fetch("https://publisher-production-891d.up.railway.app" + req.url); res.writeHead(r.status, h); res.end(await r.text());
}).listen(3199);
