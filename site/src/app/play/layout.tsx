import type { Metadata } from "next";
import { site } from "@/lib/site";

export const metadata: Metadata = {
  title: "Play",
  description: `Play the Token Burn v${site.version} playtest in the browser. WebGL 2.0, landscape, Chrome or Firefox recommended.`,
};

export default function PlayLayout({ children }: { children: React.ReactNode }) {
  return children;
}
