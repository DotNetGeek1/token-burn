import Link from "next/link";
import { navLinks, site } from "@/lib/site";

export function SiteFooter() {
  return (
    <footer className="mt-24 border-t border-line bg-bay">
      <div className="mx-auto flex max-w-6xl flex-col gap-6 px-5 py-10 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <p className="heading text-xl">
            Token <span className="text-heat">Burn</span>
          </p>
          <p className="mt-1 max-w-sm text-sm text-muted">{site.tagline}</p>
        </div>
        <nav className="flex flex-wrap gap-x-5 gap-y-2">
          {navLinks.map((link) => (
            <Link key={link.href} href={link.href} className="kicker hover:text-ink">
              {link.label}
            </Link>
          ))}
        </nav>
      </div>
      <div className="border-t border-line/60">
        <p className="mx-auto max-w-6xl px-5 py-4 font-mono text-xs text-muted">
          v{site.version} playtest build &middot; not a commercial release
        </p>
      </div>
    </footer>
  );
}
