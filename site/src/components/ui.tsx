import Link from "next/link";
import type { ReactNode } from "react";

const accentRail: Record<string, string> = {
  action: "border-l-action",
  money: "border-l-money",
  heat: "border-l-heat",
  perk: "border-l-perk",
  energy: "border-l-energy",
  lab: "border-l-lab",
  danger: "border-l-danger",
  neutral: "border-l-line-hot",
};

export type Accent = keyof typeof accentRail;

export function Panel({
  accent = "neutral",
  className = "",
  children,
}: {
  accent?: Accent;
  className?: string;
  children: ReactNode;
}) {
  return <div className={`panel ${accentRail[accent]} ${className}`}>{children}</div>;
}

export function Section({
  kicker,
  title,
  lead,
  children,
  className = "",
  id,
}: {
  kicker?: string;
  title: string;
  lead?: string;
  children?: ReactNode;
  className?: string;
  id?: string;
}) {
  return (
    <section id={id} className={`mx-auto max-w-6xl px-5 py-14 sm:py-20 ${className}`}>
      {kicker && <p className="kicker">{kicker}</p>}
      <h2 className="heading mt-2 text-3xl sm:text-5xl">{title}</h2>
      {lead && <p className="mt-4 max-w-2xl text-base text-muted sm:text-lg">{lead}</p>}
      {children && <div className="mt-8">{children}</div>}
    </section>
  );
}

export function Button({
  href,
  variant = "primary",
  children,
  download,
}: {
  href: string;
  variant?: "primary" | "ghost";
  children: ReactNode;
  download?: boolean;
}) {
  const base =
    "inline-flex items-center justify-center gap-2 rounded-[3px] px-6 py-3 font-display text-xl uppercase tracking-wider transition-colors";
  const styles =
    variant === "primary"
      ? "bg-action text-bay hover:bg-action-bright"
      : "border border-line text-ink hover:border-line-hot hover:text-action-bright";

  if (download) {
    return (
      <a href={href} download className={`${base} ${styles}`}>
        {children}
      </a>
    );
  }

  return (
    <Link href={href} className={`${base} ${styles}`}>
      {children}
    </Link>
  );
}

export function Terminal({ title, children }: { title: string; children: ReactNode }) {
  return (
    <div className="screen p-5 sm:p-7">
      <p className="text-xs uppercase tracking-[0.18em] text-phosphor-dim">{title}</p>
      <div className="relative z-10 mt-4 space-y-3 text-sm leading-relaxed sm:text-base">
        {children}
      </div>
    </div>
  );
}

export function Shot({
  src,
  alt,
  caption,
}: {
  src: string;
  alt: string;
  caption?: string;
}) {
  return (
    <figure>
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img
        src={src}
        alt={alt}
        loading="lazy"
        className="w-full rounded-[3px] border border-line"
      />
      {caption && <figcaption className="mt-2 font-mono text-xs text-muted">{caption}</figcaption>}
    </figure>
  );
}
