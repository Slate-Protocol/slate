"use client";

import { useEffect } from "react";

const ROUTES = ["feeds", "basket", "create", "lend", "lab", "signers"];

/** Before each section had its own route, links pointed at /#lend and the like: send those to /lend. */
export function HashForward() {
  useEffect(() => {
    const id = window.location.hash.slice(1);
    if (ROUTES.includes(id)) window.location.replace(`/${id}`);
  }, []);
  return null;
}
