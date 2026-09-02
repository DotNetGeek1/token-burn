# Token Burn

Roguelike economic engine-builder about taking software jobs, burning absurd quantities of AI tokens, and constructing increasingly unstable compute infrastructure.

Built with **Godot 4.7** and **GDScript**. Landscape desk-and-venue UI; playable in the editor, on the web, and as an Android playtest APK.

Play in the browser at [tokenburn.dotnetgeek.co.uk](https://tokenburn.dotnetgeek.co.uk).

## Getting started

1. Install [Godot 4.7.x](https://godotengine.org/download) (CI uses 4.7.1). Put `godot` on your `PATH`.
2. Open this folder as a Godot project (`project.godot`).
3. Press **F5** (or **Play**) to run the game.

On a fresh clone, import the project once before the first headless run:

```bash
godot --headless --import
```

### Headless tests

Fast correctness suite: simulation, effects, content validation, and a short batch of campaign runs.

```bash
godot --headless res://tests/run_tests.tscn
```

The runner exits with a status code equal to the number of failed assertions.

CI (`.github/workflows/tests.yml`) runs this suite and the UI playtests on every
pull request and push to `main`, using Godot 4.7.1. Playtests fail the job if
the log contains `SCRIPT ERROR`.

```bash
bash tools/run_tests.sh
bash tools/run_playtests.sh
```

It must be launched as a scene. Godot does not register project autoloads
(`ContentDatabase`, `EventBus`, `Simulation`, `SceneRouter`, `MetaProgress`)
under `--script`, so the systems under test fail to compile in that mode.

### UI playtests

Slower suite that boots the real `ui/main.tscn` shell and walks the venues.
Separate from the fast headless tests.

```bash
godot --headless res://tests/run_playtests.tscn
```

Or `./tools/run_playtests.ps1`, which tees output to `build/playtests.log`
and also fails if the log contains `SCRIPT ERROR`. Godot does not fail a
test when a UI callback throws.

Run one playtest while iterating with `--filter=`:

```powershell
./tools/run_playtests.ps1 -- --filter=pt_workflow_editor
```

Must be launched as a scene, same as the fast suite: autoloads are not
registered under `--script`.

Uses a scratch MetaProgress profile and a scratch save. Never writes the
developer's files.

Optional flags after `--`. `--shots` writes a PNG per audited screen into
`build/playtests/` and only works when not headless:

```bash
godot res://tests/run_playtests.tscn -- --shots --scale=8
```

Headless skips hover reachability (`gui_get_hovered_control` is null).
For those checks, run windowed with the dummy rendering driver:

```powershell
./tools/run_playtests.ps1 -Windowed
```

### Campaign balance sweeps

Longer pacing runs, separate from the correctness suite:

```bash
godot --headless --path . res://tests/run_balance.tscn -- --runs=50
```

Thresholds live in `content/balance/pacing_targets.json`.

## Web export and promo site

The promo site (Next.js, Azure Static Web Apps) lives in `site/` and hosts
the Godot HTML5 export at `/game/`. Local site docs: [site/README.md](site/README.md).

```powershell
./tools/export_web.ps1
cd site
npm install
npm run dev
```

Requires web export templates in Godot (including the no-threads variant).
Pushes to `main` that touch the game or site rebuild and deploy automatically.

## Documentation

See [docs/README.md](docs/README.md) for the design overview and linked specs:

- [Game Design Overview](docs/GAME_DESIGN.md)
- [Technical Architecture](docs/TECHNICAL_ARCHITECTURE.md)
- [Venue Layout Architecture](docs/VENUE_LAYOUT_ARCHITECTURE.md)
- [UX and Production Plan](docs/UX_AND_PRODUCTION.md)
- [Late-game escalation plan](docs/plans/late-game-escalation.md)

Feature toggles live in `config/feature_flags.json` ([ADR-003](docs/decisions/ADR-003-feature-flags.md)).

## Project structure

```text
token-burn/
├── core/           # Simulation, autoloads, routing, save
├── definitions/    # Godot Resource types for content
├── systems/        # Domain systems (jobs, economy, compute, heat, …)
├── content/        # JSON: jobs, perks, upgrades, events, balance
├── config/         # Feature flags
├── ui/             # Desk shell, venues, board, overlays
├── presentation/   # Art, fonts, asset catalog
├── tests/          # Headless suites, playtests, balance sweeps
├── tools/          # Playtest runner, web export, asset scripts
├── export/         # Web export preset and HTML shell
├── site/           # Promo site (Next.js → Azure Static Web Apps)
└── docs/           # Design and architecture
```

The player sits at the desk (`ui/main.tscn`). Jobs, market, build, workflows,
and records are separate venue scenes; `SceneRouter` swaps them without tearing
down the tree (required for the web export).

## Current status

**0.7.1** — playable twelve-month campaign from the bedroom through later
compute ages. Jobs, workflows, perks, hardware, heat and fire, angel rounds,
meta unlocks, save/load, title screen, and Burn Lab. Headless tests, UI
playtests, and a public web build plus Android playtest APK.
