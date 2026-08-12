import { Button, Terminal } from "@/components/ui";

export default function NotFound() {
  return (
    <section className="mx-auto max-w-3xl px-5 py-20 sm:py-28">
      <p className="kicker">Error 404</p>
      <h1 className="heading mt-2 text-5xl sm:text-7xl">
        Nothing on the <span className="text-heat">bench</span>
      </h1>
      <div className="mt-8">
        <Terminal title="TOKEN_BURN · [ 404 ] · NO CONTRACT">
          <p>&gt; That page does not exist, and the rent is still due.</p>
          <p className="text-phosphor-dim">— Corrigan out.</p>
        </Terminal>
      </div>
      <div className="mt-8">
        <Button href="/">Back to the desk</Button>
      </div>
    </section>
  );
}
