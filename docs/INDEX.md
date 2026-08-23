# Project Documentation Index

This file indexes canonical, reviewable documentation for the `smart_glasses` project.

## Root

- [ARCHITECTURE.md](../ARCHITECTURE.md) — Canonical project architecture: dual runtime, MethodChannel bridge, voice, scanner, wear integration
- [README.md](../README.md) — Project overview and quick start
- [AGENTS.md](../AGENTS.md) — Agent instructions

## Wear runtime ownership

- [WEAR_STACK_MERGE_REPORT.md](audits/WEAR_STACK_MERGE_REPORT.md) — Merge ledger, committed stabilization state, historical host-validation snapshot, compatibility-layer status and remaining release gates
- [WEAR_STACK_REVIEW_FIX_PLAN.md](audits/WEAR_STACK_REVIEW_FIX_PLAN.md) — Bounded plan for print-success contract and audit-evidence corrections after the final stack review
- [ADR-0001-WEAR_SINGLE_STATE_OWNER.md](decisions/ADR-0001-WEAR_SINGLE_STATE_OWNER.md) — Accepted decision: one authoritative aggregate Wear state and one writable owner per value during migration
- [ADR-0002-WEAR_STORE_EXECUTION_ORDER.md](decisions/ADR-0002-WEAR_STORE_EXECUTION_ORDER.md) — Accepted dispatch queue, commit/effect/receipt ordering, effect concurrency and terminal dispose contract
- [WEAR_SINGLE_STATE_RUNTIME_PLAN.md](WEAR_SINGLE_STATE_RUNTIME_PLAN.md) — Target migration roadmap from transitional controller/feature runtimes to `WearRuntimeStore`; aggregate business slices are migrated, while full phone presentation cleanup remains open
- [WEAR_BACKGROUND_RUNTIME_PLAN.md](WEAR_BACKGROUND_RUNTIME_PLAN.md) — Variant A screen-off/runtime implementation history and hardware constraints; the single-state documents above are authoritative for future state ownership

## Modules

- [wear_ARCHITECTURE.md](wear_ARCHITECTURE.md) — Wear module inventory and current/transitional implementation map. Some state-management sections describe pre-migration structures; do not use them as the target ownership contract
- [wear_voice_background_navigation_problem.md](wear_voice_background_navigation_problem.md) — Background voice navigation constraints and historical problem statement

## Validation and review checklists

- [WEAR_RUNTIME_STABILIZATION_VALIDATION.md](checklists/WEAR_RUNTIME_STABILIZATION_VALIDATION.md) — Local and T2151 acceptance checks for runtime barcode/scanner stabilization merged in PR #1
- [WEAR_SINGLE_STATE_MR_REVIEW.md](checklists/WEAR_SINGLE_STATE_MR_REVIEW.md) — Required ownership, async-safety, dispatch, projection and test review template for each single-state migration MR
- [WEAR_MR_S7_INPUT_UI_EFFECTS_VALIDATION.md](checklists/WEAR_MR_S7_INPUT_UI_EFFECTS_VALIDATION.md) — MR-S7 ownership, unified semantic-input and bounded UI-effect validation record
- [WEAR_MR_S8_UNIFIED_PROJECTION_VALIDATION.md](checklists/WEAR_MR_S8_UNIFIED_PROJECTION_VALIDATION.md) — MR-S8 deterministic phone/glasses projection, versioned envelope, stale/reconnect and overlay validation record
- [WEAR_MR_S9_LEGACY_CLEANUP_VALIDATION.md](checklists/WEAR_MR_S9_LEGACY_CLEANUP_VALIDATION.md) — MR-S9 migrated writable-owner cleanup, static repository gates and explicitly retained compatibility adapters

## Non-canonical notes

- `arhitecture.md` is a legacy duplicate and is not a source of truth.
- `lib/modules/wear/GLASSES_DUPLICATION_PLAN.md` is a historical implementation plan; prefer `ARCHITECTURE.md`, the accepted ADRs and the active single-state roadmap.
- Existing screen/provider lists in older architecture documents are descriptive snapshots, not permission to add another mutable state owner.

## Roadmap

- [WEAR_SINGLE_STATE_RUNTIME_PLAN.md](WEAR_SINGLE_STATE_RUNTIME_PLAN.md) — Target Wear state-ownership roadmap through MR-S9 plus the remaining phone presentation compatibility cleanup documented in the merge report
- [NATIVE_UAC4_VOICE_MIGRATION_PLAN.md](NATIVE_UAC4_VOICE_MIGRATION_PLAN.md) — Active native UAC4/SSP audio roadmap. Keep audio transport work separate from Wear state-ownership MRs unless a dependency is explicitly proven
