# Token Burn

Mobile-first roguelike economic engine-builder about taking software jobs, burning absurd quantities of AI tokens, and constructing increasingly unstable compute infrastructure.

Built with **Godot 4** and **GDScript**.

## Getting started

1. Install [Godot 4.x](https://godotengine.org/download).
2. Open this folder as a Godot project (`project.godot`).
3. Press **F5** (or **Play**) to run the placeholder app.

### Headless tests

```bash
godot --headless res://tests/run_tests.tscn
```

The runner exits with a status code equal to the number of failed assertions.

It must be launched as a scene. Godot does not register project autoloads
(`ContentDatabase`, `EventBus`, `Simulation`) under `--script`, so the systems
under test fail to compile in that mode.

On a fresh clone, import the project once before the first run:

```bash
godot --headless --import
```

### UI playtests

Slower suite that boots the real `ui/main.tscn` shell. Separate from the
fast headless tests.

```bash
godot --headless res://tests/run_playtests.tscn
```

Or `./tools/run_playtests.ps1`, which tees output to `build/playtests.log`
and also fails if the log contains `SCRIPT ERROR`. Godot does not fail a
test when a UI callback throws.

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

## Documentation

See [docs/README.md](docs/README.md) for the full design overview and linked specs:

- [Game Design Overview](docs/GAME_DESIGN.md)
- [Technical Architecture](docs/TECHNICAL_ARCHITECTURE.md)
- [UX and Production Plan](docs/UX_AND_PRODUCTION.md)

## Project structure

```text
token-burn/
├── core/           # Simulation engine (run state, events, effects, RNG)
├── definitions/    # Godot Resource types for content definitions
├── systems/        # Domain systems (jobs, economy, compute, heat, etc.)
├── content/        # Game data (jobs, perks, upgrades, events, balance)
├── ui/             # Screens and navigation
├── presentation/   # Office diorama, effects, audio
├── tests/          # Headless test runner and test suites
└── docs/           # Design and architecture documents
```

## Current status

**Vertical slice (Milestone 1-3)** — playable turn-based 12-month run with jobs, perks, upgrades, events, save/load, Burn Lab, and headless batch testing.
