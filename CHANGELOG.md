# Changelog

All notable changes to CaseWeave are recorded here.

## 0.1.1 - 2026-08-21

Documentation clarification release.

- Added a dedicated differentiation note for hackathon review.
- Clarified that CaseWeave is an original constrained combinatorial testing library, not a Mooncakes review, README/license checker, provenance checker, robot-policy package, or submission-material audit tool.
- Reworded public docs from broad "audit" wording to test-matrix coverage verification where the distinction matters.

## 0.1.0 - 2026-08-11

Initial hackathon release.

- Added validated parameter models and test cases.
- Added constraint DSL with equality, membership, boolean operators and implication.
- Added deterministic constrained covering-array generation.
- Added coverage audit with named missing interactions.
- Added CSV, JSON and Markdown exporters.
- Added scenario-spec parsing for model, constraints, included cases, excluded patterns and risk hints.
- Added risk-ranked scenario runs and Markdown risk reports.
- Added CI-oriented scenario quality gates and gate reports.
- Added coverage-repair planning for incomplete external suites.
- Added risk-aware repair planning and repair gate reports.
- Added runnable deployment-matrix example.
- Added unit tests, CI workflow and Mooncakes-ready metadata.
