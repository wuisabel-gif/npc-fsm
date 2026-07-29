"""Evaluate an SB3 PPO model and export a JSON policy artifact.

The JSON is an interchange/debug artifact, not yet consumed by guard.nut.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

from .env import ACTIONS, SyntheticGuardEnv


def export_json(model, path: Path) -> None:
    weights = {}
    for name, tensor in model.policy.state_dict().items():
        weights[name] = tensor.detach().cpu().numpy().tolist()
    artifact = {
        "format": "npc-fsm-tactical-policy-v1",
        "source": "Stable-Baselines3 PPO MlpPolicy",
        "observation_size": 16,
        "observation_order": ["guard_xy", "target_delta_xy", "distance", "visible",
                              "suspicion", "health", "attack_timer", "target_alive",
                              "state_one_hot"],
        "actions": {str(i): action for i, action in enumerate(ACTIONS)},
        "notes": "Synthetic surrogate; validate in the game before integration. Squirrel does not load this yet.",
        "policy_state_dict": weights,
    }
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(artifact), encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", type=Path, required=True, help="SB3 .zip path (without .zip is accepted)")
    parser.add_argument("--episodes", type=int, default=20)
    parser.add_argument("--export", type=Path, default=Path("training/artifacts/policy.json"))
    args = parser.parse_args()
    try:
        from stable_baselines3 import PPO
    except ImportError as exc:
        raise SystemExit("Evaluation needs requirements.txt installed") from exc
    model = PPO.load(str(args.model), device="cpu")
    env = SyntheticGuardEnv()
    returns = []
    wins = 0
    for episode in range(args.episodes):
        obs, _ = env.reset(seed=10_000 + episode)
        total = 0.0
        for _ in range(env.max_steps):
            action, _ = model.predict(obs, deterministic=True)
            obs, reward, terminated, truncated, _ = env.step(action)
            total += reward
            if terminated:
                wins += 1
            if terminated or truncated:
                break
        returns.append(total)
    export_json(model, args.export)
    print(json.dumps({"episodes": args.episodes, "mean_return": sum(returns) / len(returns),
                      "win_rate": wins / args.episodes, "json": str(args.export)}, indent=2))


if __name__ == "__main__":
    main()
