# Wear MR-S7 Unified Inputs and UI Effects Validation

## Ownership

| Value/action | Before MR-S7 | After MR-S7 |
|---|---|---|
| input modality | controller and screen callbacks selected business entry points | adapters create `WearSemanticInput`; modality is metadata only |
| barcode business admission | scanner queue called `WearFlowController.handleBarcode` after control admission | scanner queue dispatches one semantic barcode intent into `WearRuntimeStore` |
| UI-only request | widget callback opened context-owned UI directly | aggregate `WearUiEffectSlice` owns bounded pending identity |
| UI effect lifecycle | implicit callback/future lifetime | pending, claimed, completed or cancelled intents guarded by epoch and logical screen |
| inactive phone | callback-dependent | explicit `defer`: pending state remains until phone UI can claim it |

The migrated scan and availability reducers remain the S1-S6 business owners.
MR-S7 translates barcode semantics to their existing typed intents; it does not
introduce another feature state owner.

## Invariants

- [x] Touch, voice, button, barcode and manual adapters share one semantic envelope.
- [x] Input source cannot mutate aggregate state directly.
- [x] Expected logical screen is checked before semantic reduction.
- [x] Scanner production delivery has one post-admission barcode business path.
- [x] Every UI effect has `effectId`, `sessionEpoch`, kind and expected screen.
- [x] Effects are one-per-kind and preserve insertion order.
- [x] Rebuild/reconnect reads the same stable effect identity.
- [x] Claim is idempotent; completion/cancellation atomically removes the effect.
- [x] Stale epoch, stale identity and stale screen results are rejected.
- [x] Session/terminal epoch transitions clear pending effects.
- [x] Inactive-phone policy is `defer`; runtime never invokes `BuildContext`.

## Static Validation

- [x] Runtime imports contain no Flutter or widget APIs.
- [x] UI effect payload is part of `WearAggregatePayload` and terminal conversion.
- [x] `WearSemanticInputReducer` precedes S1-S6 feature reducers.
- [x] Barcode adapter retains existing serialized delivery and control admission.
- [x] No Flutter, analyzer, test, Gradle or build command was run for this MR.

## Specification Coverage

`test/wear_runtime_semantic_inputs_test.dart` specifies:

- modality parity;
- old-screen rejection;
- dispatch ordering;
- rebuild/reconnect stable identity and exactly-once claim;
- acknowledgement removal;
- stale identity and stale epoch rejection;
- one-per-kind bound;
- inactive-phone defer;
- terminal reset cleanup.

Existing scan and availability specification suites continue to cover the typed
business reducers reached by the semantic barcode translator.

## Deferred Adapter Removal

MR-S7 intentionally leaves `WearScreenActionHandler` compatibility callbacks for
unmigrated screens. Their final removal target is MR-S9, after MR-S8 replaces the
remaining projection callbacks and caches. No new business callback is added.

## Device Validation

- [ ] Confirm hardware scanner delivery reaches scan and availability once.
- [ ] Confirm a deferred manual-input request appears once after phone resume.
- [ ] Confirm screen change before completion rejects the old UI result.
