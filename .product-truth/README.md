# Source-local Product Truth worker

This directory is the `Vanilla1999/smart_glass` side of the federated DocAtlas
Product Truth reopening.

The first worker freezes eight historical fix candidates and audits their exact
single-parent patch identity, production/test path inventory and regression-test
signal. It intentionally does not mark a task valid.

A later slice must still prove:

1. the projected regression test fails on the first parent for the intended
   behavioral reason;
2. the exact historical gold patch passes twice in clean worktrees;
3. hidden/public tests and oracle evidence remain evaluator-only;
4. a real coding model passes the oracle-evidence control with the same tools and
   hard budgets used by the comparative conditions.

Device, camera and live-audio integration are not prerequisites for the initial
pack. Candidate promotion should prefer deterministic parser, matcher,
segmenter, state and flow-controller tests that run without physical hardware.
