"use client";

import { SiteFooter } from "@/components/site-footer";
import { SiteHeader } from "@/components/site-header";
import { usePathname } from "next/navigation";
import type { ReactNode } from "react";

export function SiteChrome({ children }: { children: ReactNode }) {
  const pathname = usePathname();
  const play = pathname.startsWith("/play");

  return (
    <>
      <SiteHeader />
      <main>{children}</main>
      {!play && <SiteFooter />}
    </>
  );
}
