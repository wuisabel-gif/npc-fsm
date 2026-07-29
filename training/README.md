# Synthetic tactical policy training

This training package is intentionally separate from the Squirrel runtime. It contains a small Gymnasium environment inspired by the public contract and constants in [`guard.nut`](../guard.nut): PATROL, CHASE, ATTACK, SEARCH, RETURN, gradual suspicion, sight/attack/lose-target ranges, and a cooldown. It is a **synthetic surrogate**, not a behavioral replacement or engine integration. `guard.nut` is unchanged.

For the full observation, reward, PPO, Kaggle, and deployment logic, see [`doc/ML-TRAINING-LOGIC.md`](../doc/ML-TRAINING-LOGIC.md).

## Local setup and smoke test

```bash
cd /Users/harvardsummer/npc-fsm
python3 -m venv .venv && . .venv/bin/activate
python -m pip install -r training/requirements.txt
python -m training.train --smoke
```

`--smoke` uses a seeded hand-coded tactical baseline and does not need Kaggle or a trained artifact. It still needs NumPy and Gymnasium. The environment gives a one-time `+10` defeat reward, capped distance-progress shaping (at most `+0.75` per episode), a `-2` timeout penalty, and penalties for invalid or out-of-range attacks. Thus farming CHASE/SEARCH steps cannot outweigh winning. PPO training defaults to CPU for this small MLP; use `--device cuda` or `--device auto` to override:

```bash
python -m training.train --timesteps 20000 --device cpu --output training/artifacts/ppo_guard
python -m training.evaluate --model training/artifacts/ppo_guard --export training/artifacts/policy.json
```

The JSON contains the SB3 policy state dict, observation ordering, and action names for a future Squirrel-side inference adapter. It is not currently loaded by Squirrel and should not be treated as a compatible runtime policy without validation.

## Kaggle

Create a Kaggle notebook with Internet enabled, add this repository as a Dataset (or upload its files), and run:

```python
!pip install -q -r /kaggle/input/npc-fsm/training/requirements.txt
%cd /kaggle/input/npc-fsm
!python -m training.train --timesteps 100000 --device cpu --output /kaggle/working/ppo_guard
!python -m training.evaluate --model /kaggle/working/ppo_guard --export /kaggle/working/policy.json
```

If the dataset is mounted under another slug, replace `/kaggle/input/npc-fsm`. Download `policy.json` and the PPO zip from notebook output. Kaggle execution has not been assumed to happen in this repository, and no trained artifact is committed; generated files under `training/artifacts/` are ignored by git.

For a quick notebook sanity check before training, run `!python -m training.train --smoke`.
