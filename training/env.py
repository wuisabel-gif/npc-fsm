"""A small, deterministic-friendly Gymnasium environment inspired by guard.nut.

This is a training surrogate, not an engine adapter. It models the guard's
observable tactical choices and the thresholds/constants documented in
``guard.nut`` without importing or executing Squirrel.
"""

from __future__ import annotations

from typing import Optional

import gymnasium as gym
import numpy as np
from gymnasium import spaces


STATES = ("PATROL", "CHASE", "ATTACK", "SEARCH", "RETURN", "DEAD")
ACTIONS = STATES[:5]


class SyntheticGuardEnv(gym.Env):
    """One guard versus a moving target on a bounded 2-D plane.

    Action values 0..4 request PATROL, CHASE, ATTACK, SEARCH, or RETURN.
    The simulator applies guard.nut-like perception/suspicion and combat
    dynamics, then rewards sensible tactical choices.  It deliberately has no
    Squirrel/runtime dependency.
    """

    metadata = {"render_modes": []}

    def __init__(self, episode_seconds: float = 30.0, dt: float = 0.25):
        super().__init__()
        self.dt = float(dt)
        self.max_steps = int(episode_seconds / self.dt)
        self.action_space = spaces.Discrete(len(ACTIONS))
        # [guard x/y, target relative x/y, distance, visible, suspicion,
        # health, attack timer, target alive, state one-hot(6)]
        self.observation_space = spaces.Box(0.0, 1.0, shape=(16,), dtype=np.float32)
        self._rng = np.random.default_rng()
        self.guard = np.zeros(2, dtype=np.float32)
        self.target = np.zeros(2, dtype=np.float32)
        self.health = 100.0
        self.suspicion = 0.0
        self.attack_timer = 0.0
        self.target_alive = True
        self.state = 0
        self.steps = 0
        self.target_velocity = np.zeros(2, dtype=np.float32)

    def _visible(self) -> bool:
        distance = float(np.linalg.norm(self.target - self.guard))
        return self.target_alive and distance <= 8.0

    def _obs(self) -> np.ndarray:
        delta = np.clip((self.target - self.guard) / 16.0, -1.0, 1.0)
        distance = min(float(np.linalg.norm(self.target - self.guard)) / 16.0, 1.0)
        state = np.zeros(6, dtype=np.float32)
        state[self.state] = 1.0
        return np.concatenate((
            np.clip((self.guard + 8.0) / 16.0, 0.0, 1.0),
            (delta + 1.0) / 2.0,
            [distance, float(self._visible()), self.suspicion, self.health / 100.0,
             min(self.attack_timer / 1.25, 1.0), float(self.target_alive)],
            state,
        )).astype(np.float32)

    def reset(self, *, seed: Optional[int] = None, options=None):
        super().reset(seed=seed)
        rng = self.np_random
        self.guard = np.array([0.0, 0.0], dtype=np.float32)
        self.target = np.array([rng.uniform(-7.0, 7.0), rng.uniform(-7.0, 7.0)], dtype=np.float32)
        self.target_velocity = rng.uniform(-0.7, 0.7, size=2).astype(np.float32)
        self.health, self.suspicion, self.attack_timer = 100.0, 0.0, 0.0
        self.target_alive, self.state, self.steps = True, 0, 0
        return self._obs(), {"state": ACTIONS[self.state]}

    def step(self, action: int):
        action = int(action)
        if not self.action_space.contains(action):
            raise ValueError(f"action must be in [0, {len(ACTIONS) - 1}]")
        self.steps += 1
        self.attack_timer = max(0.0, self.attack_timer - self.dt)
        distance = float(np.linalg.norm(self.target - self.guard))
        visible = self._visible()
        if visible:
            closeness = max(0.2, min(1.0, 1.0 - distance / 8.0))
            self.suspicion = min(1.0, self.suspicion + 1.6 * closeness * self.dt)
        else:
            self.suspicion = max(0.0, self.suspicion - 0.5 * self.dt)

        requested = action
        reward = -0.01  # small time cost
        if self.target_alive and visible and self.suspicion >= 1.0:
            self.state = 1  # detection commits to CHASE, as in guard.nut
            reward += 0.15
        elif self.state == 0 and requested == 0:
            self.state = 0
        elif requested == 2 and distance <= 1.4 and self.target_alive:
            self.state = 2
            if self.attack_timer <= 0.0:
                self.target_alive = False  # one successful 12-damage hit in this toy task
                self.attack_timer = 1.25
                reward += 5.0
        elif requested == 1 and self.target_alive:
            self.state = 1
            self._move(3.4)
            reward += 0.05 if visible else -0.02
        elif requested == 3:
            self.state = 3
            self._move(1.8)
            reward += 0.03 if not visible else 0.0
        elif requested == 4:
            self.state = 4
            self._move(1.8)
        else:
            self.state = 0
            self._move(1.8)

        if self.target_alive:
            self.target += self.target_velocity * self.dt
            self.target = np.clip(self.target, -7.5, 7.5)
        distance = float(np.linalg.norm(self.target - self.guard))
        if requested == 2 and distance > 1.4:
            reward -= 0.08
        if requested == 1 and distance > 11.0:
            self.state = 3  # lost target -> SEARCH
            reward += 0.05
        terminated = not self.target_alive
        truncated = self.steps >= self.max_steps
        return self._obs(), float(reward), terminated, truncated, {
            "state": ACTIONS[self.state], "visible": visible, "distance": distance,
        }

    def _move(self, speed: float) -> None:
        delta = self.target - self.guard
        length = float(np.linalg.norm(delta))
        if length > 1e-6:
            self.guard += delta / length * speed * self.dt
            self.guard = np.clip(self.guard, -8.0, 8.0)
