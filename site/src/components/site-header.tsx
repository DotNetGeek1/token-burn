"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useState } from "react";
import { navLinks } from "@/lib/site";

function isActive(pathname: string, href: string) {
  if (href === "/") return pathname === "/";
  return pathname.startsWith(href);
}

export function SiteHeader() {
  const pathname = usePathname();
  const [open, setOpen] = useState(false);

  return (
    <header className="sticky top-0 z-50 border-b border-line bg-bg/90 backdrop-blur">
      <div className="mx-auto flex max-w-6xl items-center justify-between px-5 py-3">
        <Link
          href="/"
          onClick={() => setOpen(false)}
          className="group flex items-baseline gap-2"
        >
          <span className="heading text-2xl text-ink transition-colors group-hover:text-action-bright">
            Token
          </span>
          <span className="heading text-2xl text-heat transition-colors group-hover:text-heat-bright">
            Burn
          </span>
        </Link>

        <nav className="hidden items-center gap-1 md:flex">
          {navLinks.map((link) => (
            <Link
              key={link.href}
              href={link.href}
              className={`kicker rounded-[3px] px-3 py-2 transition-colors hover:text-ink ${
                isActive(pathname, link.href) ? "text-action" : ""
              }`}
            >
              {link.label}
            </Link>
          ))}
        </nav>

        <button
          type="button"
          aria-label="Toggle navigation"
          aria-expanded={open}
          onClick={() => setOpen((value) => !value)}
          className="flex h-10 w-10 items-center justify-center rounded-[3px] border border-line text-ink md:hidden"
        >
          <span className="sr-only">Menu</span>
          <svg width="18" height="14" viewBox="0 0 18 14" aria-hidden="true">
            {open ? (
              <path d="M2 2l14 10M16 2L2 12" stroke="currentColor" strokeWidth="1.5" fill="none" />
            ) : (
              <path d="M0 1h18M0 7h18M0 13h18" stroke="currentColor" strokeWidth="1.5" />
            )}
          </svg>
        </button>
      </div>

      {open && (
        <nav className="border-t border-line bg-panel md:hidden">
          {navLinks.map((link) => (
            <Link
              key={link.href}
              href={link.href}
              onClick={() => setOpen(false)}
              className={`kicker block border-b border-line/60 px-5 py-4 ${
                isActive(pathname, link.href) ? "text-action" : ""
              }`}
            >
              {link.label}
            </Link>
          ))}
        </nav>
      )}
    </header>
  );
}
