import type { Metadata } from "next";
import { Button, Panel, Section, Shot, Terminal } from "@/components/ui";

export const metadata: Metadata = {
  title: "Tutorial",
  description:
    "How to play Token Burn: take a contract, burn tokens, manage heat, pay the rent, take the free angel pick, and hit the burn target before the year ends.",
};

const checklist = [
  {
    accent: "action" as const,
    label: "Contracts",
    body: "No contract on the bench means no tokens burned and no money in. Take work every round, even when it looks thin.",
  },
  {
    accent: "money" as const,
    label: "Upgrade rig",
    body: "Throughput is the only thing that makes the burn target reachable. Spend on the rig before you spend on comfort.",
  },
  {
    accent: "heat" as const,
    label: "Stay cool",
    body: "Heat throttles your burn and eventually ends the run. Cool between batches, and buy cooling before you need it.",
  },
];

const steps = [
  {
    step: "01",
    title: "Take a contract",
    body: "Open JOBS and pick something inside your throughput. The card tells you the burn required, the deadline in rounds, the quality bar and the fee. Taking two small jobs is often safer than one you cannot finish — an unfinished contract pays nothing and still costs you the round.",
    note: "Ohh risky! I like it. One bug and that deadline is toast.",
  },
  {
    step: "02",
    title: "Build a pipeline",
    body: "BUILD is where operations become a workflow: prompts, context, agents and the rest, arranged into the pipeline that runs each batch. More stages means more tokens burned per batch, more heat, and more chances to introduce a bug that costs you quality.",
    note: null,
  },
  {
    step: "03",
    title: "Burn, and watch the bars",
    body: "On the burn board you run batches against the contract. BURN is progress, QUAL is whether the client will accept it, TIME is what is left of the deadline, and HEAT is how close the rig is to throttling. Boost when you are behind. Cool when the heat bar gets loud.",
    note: null,
  },
  {
    step: "04",
    title: "Deliver before the deadline",
    body: "Ship above the quality bar and you get the full fee plus reputation, which pulls better work onto the board. Ship under it and you did the whole job for a discount you gave yourself.",
    note: "Under the quality bar means under the fee.",
  },
  {
    step: "05",
    title: "Survive the bills",
    body: "Rent and power are taken at the end of every round regardless of how the work went. Miss the rent once and Corrigan phones. Miss it twice and the run is over.",
    note: "The landlord phoned me. Do you understand how little I want the landlord to phone me?",
  },
  {
    step: "06",
    title: "Take the free pick",
    body: "Corrigan puts perks and modules on his table each round and one of them is free. Perks change rules rather than nudge numbers, so read them and pick the one your build actually wants — then spend cash in the market on hardware and cooling.",
    note: null,
  },
  {
    step: "07",
    title: "Hit the number, change rooms",
    body: "The location contract is the only score that matters. Burn 40.0M in the bedroom inside twelve rounds and you ascend to the garage, where the contract is bigger and so is the rent. Keep going until the numbers stop being words you recognise.",
    note: null,
  },
];

const mistakes = [
  "Buying cooling only after the rig is already throttling — it is cheaper as insurance than as a rescue.",
  "Taking a tier above your throughput because the fee looked good. The fee is zero if you do not deliver.",
  "Buying the next machine before you can cool the current one. Heat does not wait for the invoice.",
  "Ignoring reputation. It is the only thing in this business that compounds without a bill attached.",
];

export default function TutorialPage() {
  return (
    <>
      <Section
        kicker="Tutorial"
        title="How to play"
        lead="There is no tutorial screen in Token Burn. There is Corrigan on the phone and a checklist on your bedroom wall. This page is the version you can read without him talking over it."
      >
        <Terminal title="TOKEN_BURN · [ THE DEAL ] · INCOMING CALL">
          <p>&gt; Right. Here&apos;s the deal, and I&apos;m only saying it once.</p>
          <p>
            &gt; You think you can make money out of this vibe coding nonsense. Fine. Prove it.
            I&apos;ve put a rig in your bedroom and my name on the lease.
          </p>
          <p>
            &gt; 12 rounds. In that time you burn 40.0M — that&apos;s the first scale-up, and
            it&apos;s the only thing I&apos;m measuring. Miss the rent, or run this thing at a loss,
            and I take the hardware back and we never speak again.
          </p>
          <p>&gt; We clear? Good. Get to it.</p>
          <p className="text-phosphor-dim">— Vince Corrigan. Corrigan out.</p>
        </Terminal>
      </Section>

      <Section
        kicker="The wall checklist"
        title="Three things, every round"
        lead="It is pinned above the desk for the entire run, because it never stops being the answer."
      >
        <div className="grid gap-4 md:grid-cols-3">
          {checklist.map((item) => (
            <Panel key={item.label} accent={item.accent} className="p-6">
              <p className="font-mono text-xs text-muted">[ ]</p>
              <h3 className="heading mt-1 text-2xl uppercase">{item.label}</h3>
              <p className="mt-3 text-sm leading-relaxed text-muted">{item.body}</p>
            </Panel>
          ))}
        </div>
      </Section>

      <Section kicker="First run" title="Walkthrough">
        <ol className="space-y-4">
          {steps.map((item) => (
            <li key={item.step}>
              <Panel accent="action" className="p-6">
                <div className="flex flex-col gap-1 sm:flex-row sm:items-baseline sm:gap-5">
                  <span className="font-mono text-xs text-action">{item.step}</span>
                  <div>
                    <h3 className="heading text-2xl">{item.title}</h3>
                    <p className="mt-3 text-sm leading-relaxed text-muted sm:text-base">{item.body}</p>
                    {item.note && (
                      <p className="mt-4 border-l border-line-hot pl-4 font-mono text-xs text-phosphor-dim">
                        {item.note}
                      </p>
                    )}
                  </div>
                </div>
              </Panel>
            </li>
          ))}
        </ol>
      </Section>

      <Section kicker="Reading the screen" title="What the board is telling you">
        <div className="grid gap-4 lg:grid-cols-2">
          <Shot src="/img/shot-board.webp" alt="The burn board" caption="BURN, QUAL, TIME, HEAT — in that order of urgency." />
          <Shot src="/img/shot-statement.webp" alt="End of round statement" caption="The statement: what came in, what went out, what is left." />
        </div>
      </Section>

      <Section kicker="Avoid these" title="Ways a first run ends early">
        <Panel accent="danger" className="divide-y divide-line/60">
          {mistakes.map((mistake) => (
            <p key={mistake} className="p-5 text-sm leading-relaxed text-muted sm:text-base">
              {mistake}
            </p>
          ))}
        </Panel>

        <div className="mt-8 flex flex-wrap gap-3">
          <Button href="/play/">Play in browser</Button>
          <Button href="/overview/" variant="ghost">
            Back to overview
          </Button>
        </div>
      </Section>
    </>
  );
}
