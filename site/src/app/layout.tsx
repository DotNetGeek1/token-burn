import type { Metadata, Viewport } from "next";
import { SiteChrome } from "@/components/site-chrome";
import { site } from "@/lib/site";
import { bebas, inter, shareTech } from "./fonts";
import "./globals.css";

export const metadata: Metadata = {
  metadataBase: new URL(site.url),
  title: {
    default: `${site.name} — burn tokens, build an engine`,
    template: `%s — ${site.name}`,
  },
  description: site.tagline,
  icons: { icon: "/img/icon.svg" },
  openGraph: {
    title: site.name,
    description: site.tagline,
    url: site.url,
    siteName: site.name,
    images: ["/img/key-art.webp"],
    type: "website",
  },
};

export const viewport: Viewport = {
  themeColor: "#0d1013",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className={`${bebas.variable} ${inter.variable} ${shareTech.variable}`}>
      <body className="min-h-screen">
        <SiteChrome>{children}</SiteChrome>
      </body>
    </html>
  );
}
