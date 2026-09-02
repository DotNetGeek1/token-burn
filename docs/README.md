# Token Burn

**Token Burn** is a mobile-first roguelike economic engine-builder about taking software jobs, burning absurd quantities of AI tokens, and constructing increasingly unstable compute infrastructure.

The player balances:

- Job income and deadlines
- Token throughput and efficiency
- Hardware, cloud, power, heat, and space
- Advertising and job demand
- Rent and recurring costs
- Reputation, quality, and risk
- Perks that deliberately enable broken combinations

The target experience is closer to **Balatro-style build construction** than a realistic coding simulator. Software-development clichés become mechanics, and the player is encouraged to create outrageous but valid economic engines.

## Recommended direction

- **Engine:** Godot 4
- **Primary platform:** Mobile in landscape orientation
- **Secondary builds:** Desktop and web, with 1920×1080 as the supported desktop floor
- **Visual style:** 2D interface with a small orthographic 2.5D office diorama
- **Simulation model:** Data-driven, deterministic, and testable without rendering
- **Initial scope:** Local-only, no backend, no real AI API usage

## Documents

- [Game Design Overview](GAME_DESIGN.md)
- [Technical Architecture](TECHNICAL_ARCHITECTURE.md)
- [Venue Layout Architecture](VENUE_LAYOUT_ARCHITECTURE.md)
- [UX and Production Plan](UX_AND_PRODUCTION.md)
- [Late-game escalation plan](plans/late-game-escalation.md)
- [Android release build](ANDROID_RELEASE.md)
- [Android device matrix](ANDROID_DEVICE_MATRIX.md)
- [Release candidate checklist](RELEASE_CANDIDATE.md)
- [Play Console closed test](PLAY_CONSOLE.md)
- [Launch runbook](PLAY_LAUNCH.md)
- [Data safety inventory](DATA_SAFETY.md)
- [Store listing](STORE_LISTING.md)
- [1.0 content freeze](CONTENT_FREEZE.md)
- [Simulation facade](SIMULATION_FACADE.md)

## Core design principle

> Strong combinations should be allowed to break the economy. Invalid combinations must never break the simulation.
