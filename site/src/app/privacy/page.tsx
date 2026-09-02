import type { Metadata } from "next";
import { Section } from "@/components/ui";
import { site } from "@/lib/site";

export const metadata: Metadata = {
  title: "Privacy",
  description: "What Token Burn stores on your device, and what it does not collect.",
};

export default function PrivacyPage() {
  return (
    <Section
      kicker="Privacy"
      title="Token Burn does not collect your data"
      lead="This policy matches the shipping game and the Google Play Data safety form. If that ever changes, this page changes in the same release."
    >
      <div className="prose prose-invert max-w-3xl space-y-6 text-sm leading-relaxed text-muted">
        <p>
          Token Burn is a single-player game. It does not require an account, does
          not show ads, and does not include analytics or crash-reporting SDKs.
        </p>
        <h2 className="heading text-2xl text-ink">What stays on your device</h2>
        <p>
          The game writes a run save and a meta profile to local app storage so
          you can continue a campaign and keep unlocks. Those files do not leave
          the device. Android backup of that storage is disabled in the release
          export.
        </p>
        <h2 className="heading text-2xl text-ink">What we do not collect</h2>
        <ul className="list-disc space-y-2 pl-5">
          <li>Name, email, or other identity</li>
          <li>Location, contacts, photos, or microphone input</li>
          <li>Advertising IDs or analytics events</li>
          <li>Crash dumps or diagnostics sent to a server</li>
        </ul>
        <h2 className="heading text-2xl text-ink">Web play</h2>
        <p>
          The browser build only talks to the page in order to resume the Web
          Audio context after a tap. There is no game backend.
        </p>
        <h2 className="heading text-2xl text-ink">Contact</h2>
        <p>
          Questions about this policy: the support email listed on the{" "}
          <a className="text-ink underline" href={site.url}>
            Token Burn site
          </a>{" "}
          and in Google Play Console.
        </p>
        <p className="font-mono text-xs">Last updated 2 September 2026.</p>
      </div>
    </Section>
  );
}
