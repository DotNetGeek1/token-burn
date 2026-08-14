import type { Metadata } from "next";
import { Button, Panel, Section, Shot } from "@/components/ui";

export const metadata: Metadata = {
  title: "Overview",
  description:
    "How Token Burn works: the round loop, contracts, heat, hardware, locations, perks and the angel investor who owns your rig.",
};

const loop = [
  {
    accent: "action" as const,
    step: "01",
    name: "Prep",
    body: "Read the job board. Demand, reputation and whatever advertising you bought decide what turns up. Take the work you can actually finish.",
  },
  {
    accent: "heat" as const,
    step: "02",
    name: "Work",
    body: "Burn tokens through your pipeline. Boost for speed, cool when the rig complains, burst into the cloud if you can stomach the invoice.",
  },
  {
    accent: "money" as const,
    step: "03",
    name: "Resolve",
    body: "Quality is checked against the brief. Late, buggy or under the bar and you get revisions, complications and a smaller fee.",
  },
  {
    accent: "danger" as const,
    step: "04",
    name: "Bills",
    body: "Rent, power and cloud land whether you delivered or not. Miss rent twice and the run ends there.",
  },
  {
    accent: "perk" as const,
    step: "05",
    name: "Angel draft",
    body: "Corrigan puts one free pick on his table. Then the market opens and you spend what is left on hardware, cooling and cloud tiers.",
  },
];

const jobs = [
  { tier: "Tier 0", name: "Write 200 Product Reviews", note: "rent money, barely" },
  { tier: "Tier 1", name: "FAQ Chatbot for a Dentist", note: "a real client, allegedly" },
  { tier: "Tier 2", name: "Migrate a Bank System", note: "quality bar you will hate" },
  { tier: "Tier 3", name: "Generate an Open-World Game", note: "burn measured in gigatokens" },
  { tier: "Tier 4", name: "Simulate a Civilisation", note: "why the moon facility exists" },
];

const locations = [
  { name: "Bedroom", note: "one laptop, a fan, and Corrigan's name on the lease" },
  { name: "Garage", note: "space and power, so now you have heat" },
  { name: "Office", note: "real slots, real rent" },
  { name: "Warehouse", note: "racks, chillers, noise complaints" },
  { name: "Datacentre Campus", note: "industrial cooling, industrial invoices" },
  { name: "Private Power Grid", note: "stop paying for electricity, start making it" },
  { name: "Moon Facility", note: "orbital cooling; teratoken contracts" },
];

const perks = [
  { name: "Ship It", note: "quality is a suggestion" },
  { name: "Technical Debt", note: "borrow throughput from future you" },
  { name: "Infinite Context", note: "the prompt never ends" },
  { name: "The Wrapper", note: "somebody else's model, your margin" },
  { name: "Cloud Baron", note: "burst first, read the bill later" },
  { name: "Bare Metal", note: "own the iron, own the heat" },
  { name: "Deploy On Friday", note: "exactly what it sounds like" },
  { name: "Vibe Check", note: "reputation as a resource" },
];

export default function OverviewPage() {
  return (
    <>
      <Section
        kicker="Overview"
        title="What you actually do"
        lead="Token Burn is a roguelike engine-builder dressed as a freelance AI business. A run is twelve rounds — one year — in a single room. Hit the room's burn target before the year runs out and you ascend to a bigger room and a bigger number."
      >
        <div className="grid gap-4 lg:grid-cols-2">
          <Shot src="/img/shot-title.webp" alt="Token Burn title screen" caption="Every run starts on the same tired laptop." />
          <Shot src="/img/shot-jobs.webp" alt="The job board" caption="The job board — pick your poison." />
        </div>
      </Section>

      <Section kicker="The loop" title="Five phases, twelve rounds">
        <ol className="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
          {loop.map((phase) => (
            <li key={phase.step}>
              <Panel accent={phase.accent} className="h-full p-6">
                <p className="font-mono text-xs text-muted">{phase.step}</p>
                <h3 className="heading mt-1 text-2xl">{phase.name}</h3>
                <p className="mt-3 text-sm leading-relaxed text-muted">{phase.body}</p>
              </Panel>
            </li>
          ))}
        </ol>
      </Section>

      <Section
        kicker="Contracts"
        title="The work gets stupid quickly"
        lead="Five tiers of gig, each with a burn requirement, a deadline, a quality bar and a decent chance of a complication you did not plan for."
      >
        <Panel accent="action" className="divide-y divide-line/60">
          {jobs.map((job) => (
            <div key={job.name} className="flex flex-col gap-1 p-5 sm:flex-row sm:items-baseline sm:justify-between">
              <div className="flex items-baseline gap-4">
                <span className="kicker w-16 shrink-0">{job.tier}</span>
                <span className="font-display text-2xl uppercase tracking-wide">{job.name}</span>
              </div>
              <span className="font-mono text-xs text-muted">{job.note}</span>
            </div>
          ))}
        </Panel>
      </Section>

      <Section
        kicker="Hardware and heat"
        title="Everything you buy makes it hotter"
        lead="A used laptop becomes a desktop, a GPU rack, a garage datacentre, a warehouse, an industrial campus. Throughput climbs, heat climbs faster, and a rig that cooks itself earns nothing."
      >
        <div className="grid gap-4 lg:grid-cols-2">
          <Shot src="/img/shot-heat.webp" alt="The rig running hot" caption="Heat is the tax on every good idea you have." />
          <Shot src="/img/shot-market.webp" alt="Hardware market" caption="Air conditioning, immersion, chillers, cryo." />
        </div>
      </Section>

      <Section
        kicker="Locations"
        title="Seven rooms, one direction"
        lead="Each location sets the burn contract, the rent, the slot count and how much heat you can shed before the run turns into a fire."
      >
        <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
          {locations.map((location, index) => (
            <Panel key={location.name} accent={index === locations.length - 1 ? "lab" : "neutral"} className="p-5">
              <p className="font-mono text-xs text-muted">{String(index + 1).padStart(2, "0")}</p>
              <h3 className="heading mt-1 text-xl">{location.name}</h3>
              <p className="mt-2 text-sm text-muted">{location.note}</p>
            </Panel>
          ))}
        </div>
      </Section>

      <Section
        kicker="Perks and synergies"
        title="Rule-changers, not stat boosts"
        lead="Perks arrive free from the angel draft and rewrite how your engine behaves. Stack the right ones and you trigger named synergies — Reckless Scaling, Debt Spiral, Vibe Coding, Bare Metal Doctrine, Somebody Else's Computer."
      >
        <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
          {perks.map((perk) => (
            <Panel key={perk.name} accent="perk" className="p-5">
              <h3 className="heading text-xl">{perk.name}</h3>
              <p className="mt-2 text-sm text-muted">{perk.note}</p>
            </Panel>
          ))}
        </div>
      </Section>

      <Section
        kicker="Your investor"
        title="Vince Corrigan is not your friend"
        lead="Corrigan Seed put the rig in your bedroom and his name on the lease. He phones between rounds to tell you the number, to tell you that you are behind it, and occasionally to admit he did not wince."
      >
        <div className="grid gap-4 lg:grid-cols-2">
          <Shot src="/img/shot-call.webp" alt="A phone call from Vince Corrigan" caption="Every round ends with a call you cannot decline." />
          <Shot src="/img/shot-angel.webp" alt="The angel draft table" caption="His table — one free pick, no negotiation." />
        </div>
      </Section>

      <Section
        kicker="Endgame"
        title="Ascension, and then some"
        lead="Beat a location's contract and you move up. Keep going and the run stops being about rent: The Singularity, The Archive, The Simulation and The Ad Machine are all still on the table."
      >
        <div className="flex flex-wrap gap-3">
          <Button href="/play/">Play in browser</Button>
          <Button href="/tutorial/" variant="ghost">
            How to play
          </Button>
        </div>
      </Section>
    </>
  );
}
