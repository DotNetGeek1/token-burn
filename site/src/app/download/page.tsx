import type { Metadata } from "next";
import { Button, Panel, Section } from "@/components/ui";
import { site } from "@/lib/site";

export const metadata: Metadata = {
  title: "Download",
  description: `Play Token Burn v${site.version} in the browser, or download the Android playtest APK.`,
};

const installSteps = [
  {
    step: "01",
    title: "Download the APK",
    body: "Tap the button above on your Android phone. Chrome will warn you that this file type can harm your device — that warning appears for every APK, signed or not. Choose to keep it.",
  },
  {
    step: "02",
    title: "Allow installs from your browser",
    body: "Open the downloaded file. If Android blocks it, it will offer a link to Settings → Install unknown apps. Enable it for whichever app you downloaded with, then go back and open the file again.",
  },
  {
    step: "03",
    title: "Install and play",
    body: "Tap Install, then Open. Play Protect may ask to scan the app first; let it, then continue. Token Burn runs in landscape, so turn rotation on.",
  },
  {
    step: "04",
    title: "Tell me what broke",
    body: "This is a playtest, not a release. Crashes, confusing screens, numbers that feel wrong, runs that end for reasons you did not understand — all of it is useful. Note the round and the location if you can.",
  },
];

const facts = [
  { label: "Platform", value: "Android (APK)" },
  { label: "Version", value: `v${site.version} playtest` },
  { label: "Size", value: site.apkSize },
  { label: "Requires", value: site.androidMinimum },
  { label: "Price", value: "Free — friends and playtesters only" },
];

export default function DownloadPage() {
  return (
    <>
      <Section
        kicker="Play"
        title="Token Burn in the browser"
        lead="The same playtest, running as WebAssembly. Needs WebGL 2.0 — Chrome or Firefox on a desktop or laptop is the comfortable way to play. Phone browsers work in landscape; the Android APK below is still the better mobile build."
      >
        <Panel accent="action" className="p-8">
          <div className="flex flex-col gap-6 sm:flex-row sm:items-center sm:justify-between">
            <div>
              <p className="kicker">Web playtest</p>
              <p className="heading mt-1 text-4xl">
                v{site.version} <span className="text-action">in-browser</span>
              </p>
              <p className="mt-2 text-sm text-muted">No install. Saves live in this browser.</p>
            </div>
            <Button href="/play/">Play now</Button>
          </div>
        </Panel>
      </Section>

      <Section
        kicker="Download"
        title="Token Burn on Android"
        lead="A playtest build for phones and tablets, distributed as an APK you install yourself. It is not on the Play Store, and it is not finished."
      >
        <Panel accent="money" className="p-8">
          <div className="flex flex-col gap-6 sm:flex-row sm:items-center sm:justify-between">
            <div>
              <p className="kicker">Android APK</p>
              <p className="heading mt-1 text-4xl">
                v{site.version} <span className="text-money">playtest</span>
              </p>
              <p className="mt-2 text-sm text-muted">
                {site.apkSize} &middot; {site.androidMinimum}
              </p>
            </div>
            <Button href={site.apkHref} download>
              Download APK
            </Button>
          </div>
        </Panel>

        <dl className="mt-4 grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
          {facts.map((fact) => (
            <Panel key={fact.label} className="p-5">
              <dt className="kicker">{fact.label}</dt>
              <dd className="mt-1 font-mono text-sm text-ink">{fact.value}</dd>
            </Panel>
          ))}
        </dl>
      </Section>

      <Section
        kicker="Installing"
        title="Sideloading, briefly"
        lead="Android treats anything from outside the Play Store as suspicious. Nothing here is unusual for a test build, but you do have to click through a couple of warnings."
      >
        <ol className="space-y-4">
          {installSteps.map((item) => (
            <li key={item.step}>
              <Panel accent="action" className="p-6">
                <div className="flex flex-col gap-1 sm:flex-row sm:items-baseline sm:gap-5">
                  <span className="font-mono text-xs text-action">{item.step}</span>
                  <div>
                    <h3 className="heading text-2xl">{item.title}</h3>
                    <p className="mt-3 text-sm leading-relaxed text-muted sm:text-base">{item.body}</p>
                  </div>
                </div>
              </Panel>
            </li>
          ))}
        </ol>
      </Section>

      <Section kicker="Small print" title="This is a playtest build">
        <Panel accent="heat" className="space-y-3 p-6 text-sm leading-relaxed text-muted sm:text-base">
          <p>
            Balance is still moving, art is placeholder in places, and saves may not survive the
            next build. If a run ends in a way that feels like a bug rather than a bad decision, it
            probably is one.
          </p>
          <p>
            The Android build has no analytics, no account and no network requirement — it runs
            entirely on your device. The browser build needs a network connection to load, then
            plays on this machine; progress is stored in this browser.
          </p>
        </Panel>
      </Section>
    </>
  );
}
