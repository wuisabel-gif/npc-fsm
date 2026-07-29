"""Train PPO or run a dependency-light deterministic smoke test.

Examples:
  python -m training.train --smoke
  python -m training.train --timesteps 20000 --output training/artifacts/ppo_guard
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

from .env import SyntheticGuardEnv


def smoke(episodes: int = 3) -> dict:
    """Run a deterministic hand-coded policy; requires only env dependencies."""
    env = SyntheticGuardEnv()
    returns = []
    for episode in range(episodes):
        observation, _ = env.reset(seed=episode)
        total = 0.0
        for _ in range(env.max_steps):
            # Tactical baseline: pursue when visible, otherwise patrol/search;
            # attack only when the normalized distance indicates close range.
            distance = observation[4] * 16.0
            visible = observation[5] > 0.5
            action = 2 if visible and distance <= 1.4 else (1 if visible else 0)
            observation, reward, terminated, truncated, _ = env.step(action)
            total += reward
            if terminated or truncated:
                break
        returns.append(total)
    result = {"episodes": episodes, "returns": returns, "mean_return": sum(returns) / episodes}
    print(json.dumps(result, indent=2))
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--smoke", action="store_true")
    parser.add_argument("--timesteps", type=int, default=20_000)
    parser.add_argument("--output", type=Path, default=Path("training/artifacts/ppo_guard"))
    args = parser.parse_args()
    if args.smoke:
        smoke()
        return
    try:
        from stable_baselines3 import PPO
    except ImportError as exc:
        raise SystemExit("PPO mode needs requirements.txt installed; use --smoke for a local check") from exc
    env = SyntheticGuardEnv()
    model = PPO("MlpPolicy", env, verbose=1, seed=7)
    model.learn(total_timesteps=args.timesteps)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    model.save(str(args.output))
    print(f"Saved SB3 model to {args.output}.zip")
    print("Run `python -m training.evaluate --model", args.output, "` to export JSON.")


if __name__ == "__main__":
    main()
