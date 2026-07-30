# Changelog

All notable changes to `npc-fsm` are documented here.

## [0.2.0] - 2026-07-29

### Added

- Formal `world` adapter contract validation with clear errors.
- Reusable deterministic `mock_world.nut` test adapter.
- FOV-cone perception with optional occlusion support.
- Grid navigation adapter example with authoritative position updates.
- Native C++ embedding guidance and engine integration documentation.
- Godot 4 host-side integration example covering FOV, raycasts,
  `NavigationAgent2D`, target mapping, and event signals.
- Terminal demonstration GIF showing the guard FSM in action.
- PyTorch PPO training pipeline with a synthetic Gymnasium guard environment.
- Kaggle training instructions and an uploadable training workflow.
- Detailed ML training-logic documentation covering observations, actions,
  rewards, evaluation, and deployment boundaries.

### Changed

- Improved CI reliability by building Squirrel from source and locating the
  interpreter deterministically.
- Updated the PPO reward design so target completion dominates repeated
  chase/search reward farming.
- PPO training defaults to CPU for the small MLP policy, with an explicit
  `--device` override for other environments.
- Updated the README with architecture, engine integration, ML training, and
  roadmap documentation.

### Validation

- Squirrel FSM self-check passes.
- Single-guard, squad, and navigation demos pass.
- Python training modules compile successfully.
- PPO smoke test and short training/evaluation run pass.

### Scope note

The deterministic Squirrel FSM is the production-facing behavior layer. The
PyTorch policy is an experimental training pipeline using a synthetic surrogate
environment; the exported policy is not yet consumed by `guard.nut`.

## [0.1.1]

- Initial reusable Squirrel guard FSM release.
