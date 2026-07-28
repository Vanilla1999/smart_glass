# Project Documentation Index

This file indexes canonical, reviewable documentation for the `smart_glasses` project.

## Root

- [ARCHITECTURE.md](../ARCHITECTURE.md) — Canonical project architecture: dual runtime, MethodChannel bridge, voice, scanner, wear integration
- [README.md](../README.md) — Project overview and quick start
- [AGENTS.md](../AGENTS.md) — Agent instructions

## Modules

- [wear_ARCHITECTURE.md](wear_ARCHITECTURE.md) — Canonical Wear module architecture: flow controller, voice modes, glasses projection
- [wear_voice_background_navigation_problem.md](wear_voice_background_navigation_problem.md) — Background voice navigation constraints and historical problem statement

## Non-Canonical Notes

- `arhitecture.md` is a legacy duplicate and is not a source of truth.
- `lib/modules/wear/GLASSES_DUPLICATION_PLAN.md` is a historical implementation plan; prefer `ARCHITECTURE.md` and `docs/wear_ARCHITECTURE.md` for current behavior.

## Roadmap

- [NATIVE_UAC4_VOICE_MIGRATION_PLAN.md](NATIVE_UAC4_VOICE_MIGRATION_PLAN.md) - Active plan to replace Flutter `record` capture with native four-microphone UAC4/SSP audio for Vosk.
