"use client";

import { useEffect } from "react";

export default function PlayPage() {
  useEffect(() => {
    window.location.replace("/game/index.html");
  }, []);

  return (
    <section className="flex h-[calc(100dvh-3.75rem)] items-center justify-center font-mono text-sm text-muted">
      Opening the playtest…
    </section>
  );
}
