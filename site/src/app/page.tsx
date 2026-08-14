import { Button, Panel, Section, Shot, Terminal } from "@/components/ui";
import { site } from "@/lib/site";

const teasers = [
  {
    accent: "action" as const,
    kicker: "Contracts",
    title: "Take absurd work",
    body: "Two hundred product reviews for a dropshipper today, a bank migration next year. Deadlines, quality bars and clients who ask for revisions you cannot afford.",
  },
  {
    accent: "heat" as const,
    kicker: "Heat",
    title: "Keep the rig alive",
    body: "Every token you burn is heat. Throttle, cool, or spend on air conditioning, immersion tanks and eventually orbital radiators.",
  },
  {
    accent: "money" as const,
    kicker: "Bills",
    title: "Pay the rent",
    body: "Rent, power and cloud arrive every round whether the contract landed or not. Miss rent twice and Corrigan takes the hardware back.",
  },
  {
    accent: "perk" as const,
    kicker: "Perks",
    title: "Break the rules",
    body: "Ship It, Technical Debt, Infinite Context, Deploy On Friday. Stack perks into named synergies and let the engine run away with itself.",
  },
];

export default function HomePage() {
  return (
    <>
      <section className="relative overflow-hidden border-b border-line">
        <div
          className="pointer-events-none absolute inset-0 bg-cover bg-center opacity-60"
          style={{ backgroundImage: "url(/img/shot-title.webp)" }}
          aria-hidden="true"
        />
        <div
          className="pointer-events-none absolute inset-0 bg-gradient-to-r from-bg via-bg/85 to-bg/40"
          aria-hidden="true"
        />
        <div
          className="pointer-events-none absolute inset-0 bg-gradient-to-b from-bg/40 via-transparent to-bg"
          aria-hidden="true"
        />

        <div className="relative mx-auto grid max-w-6xl gap-10 px-5 py-16 sm:py-24 lg:grid-cols-[1.15fr_1fr] lg:items-center">
          <div>
            <p className="kicker">Roguelike engine-builder &middot; playtest build v{site.version}</p>
            <h1 className="heading mt-3 text-6xl leading-[0.9] sm:text-8xl">
              Token
              <br />
              <span className="text-heat">Burn</span>
            </h1>
            <p className="mt-6 max-w-xl text-lg text-ink/90 sm:text-xl">{site.tagline}</p>
            <p className="mt-4 max-w-xl text-base text-muted">
              You are a reckless vibe coder with a second-hand laptop, an angel investor who
              regrets everything, and twelve rounds to burn an impossible number of tokens.
            </p>

            <div className="mt-8 flex flex-wrap gap-3">
              <Button href="/play/">Play in browser</Button>
              <Button href="/download/" variant="ghost">
                Download APK
              </Button>
            </div>
          </div>

          <Terminal title={`TOKEN_BURN v${site.version} · [ THE DEAL ] · CORRIGAN SEED`}>
            <p>&gt; Right. Here&apos;s the deal, and I&apos;m only saying it once.</p>
            <p>
              &gt; You think you can make money out of this vibe coding nonsense. Fine. Prove it.
              I&apos;ve put a rig in your bedroom and my name on the lease.
            </p>
            <p>
              &gt; 12 rounds. In that time you burn 40.0M — and it&apos;s the only thing I&apos;m
              measuring.
            </p>
            <p className="text-phosphor-dim">— Vince Corrigan, Angel Investor. Corrigan out.</p>
          </Terminal>
        </div>
      </section>

      <Section
        kicker="The pitch"
        title="One year. One number. One very unstable rig."
        lead="Token Burn is a run-based economic engine-builder. Every run is a year of freelance AI work in one room, and every room wants more tokens burned than the last."
      >
        <div className="grid gap-4 sm:grid-cols-2">
          {teasers.map((teaser) => (
            <Panel key={teaser.title} accent={teaser.accent} className="p-6">
              <p className="kicker">{teaser.kicker}</p>
              <h3 className="heading mt-1 text-2xl">{teaser.title}</h3>
              <p className="mt-3 text-sm leading-relaxed text-muted">{teaser.body}</p>
            </Panel>
          ))}
        </div>

        <div className="mt-8">
          <Button href="/overview/" variant="ghost">
            Full overview
          </Button>
        </div>
      </Section>

      <Section
        kicker="Bedroom to moon"
        title="Scale until it is ridiculous"
        lead="Ascend out of the bedroom into a garage, an office, a warehouse, a datacentre campus, your own power grid, and finally a facility on the moon. The contracts go from megatokens to teratokens. The rent keeps pace."
      >
        <div className="grid gap-4 sm:grid-cols-2">
          <Shot src="/img/shot-board.webp" alt="The burn board terminal on a bedroom laptop" caption="The burn board — where contracts actually get burned." />
          <Shot src="/img/shot-market.webp" alt="The upgrade market" caption="The market — hardware, cooling and cloud contracts." />
        </div>
      </Section>

      <section className="mx-auto max-w-6xl px-5 pb-4">
        <Panel accent="action" className="flex flex-col gap-5 p-8 sm:flex-row sm:items-center sm:justify-between">
          <div>
            <h2 className="heading text-3xl sm:text-4xl">Play the playtest</h2>
            <p className="mt-2 text-sm text-muted">
              In the browser, or the Android build ({site.apkSize}). Bring bug reports and opinions.
            </p>
          </div>
          <div className="flex flex-wrap gap-3">
            <Button href="/play/">Play in browser</Button>
            <Button href="/download/" variant="ghost">
              Download APK
            </Button>
          </div>
        </Panel>
      </section>
    </>
  );
}
