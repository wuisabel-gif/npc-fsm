# NPC-FSM Kaggle training guide

This guide is for running the PyTorch PPO policy training in a Kaggle Notebook.
It does not require Kaggle API credentials.

## Quickest option

The repository includes an uploadable notebook:

```text
training/kaggle_train.ipynb
```

In Kaggle, choose **New Notebook → File → Upload Notebook**, select that file,
and run the cells from top to bottom.

## Manual notebook cells

If you prefer to create a notebook manually, use these cells.

### Clone or update the repository

Run this only once in a fresh Kaggle session:

```python
from pathlib import Path

repo = Path("/kaggle/working/npc-fsm")
if repo.exists():
    print("Repository already exists; reusing it.")
else:
    !git clone https://github.com/wuisabel-gif/npc-fsm.git /kaggle/working/npc-fsm

%cd /kaggle/working/npc-fsm
```

If the repository already exists and you want the latest version:

```python
%cd /kaggle/working/npc-fsm
!git pull origin main
```

### Install dependencies

```python
!pip install -q -r training/requirements.txt
```

### Check the environment

```python
import torch

print("PyTorch:", torch.__version__)
print("CUDA available:", torch.cuda.is_available())
```

The policy is a small MLP, so CPU is normally the correct device. GPU training
can be requested with `--device cuda` if needed.

### Run the smoke test

```python
!python -m training.train --smoke
```

### Train PPO

Start with 20,000 steps to verify the pipeline:

```python
!python -m training.train \
    --timesteps 20000 \
    --device cpu \
    --output /kaggle/working/ppo_guard
```

For a longer run:

```python
!python -m training.train \
    --timesteps 100000 \
    --device cpu \
    --output /kaggle/working/ppo_guard
```

### Evaluate and export

```python
!python -m training.evaluate \
    --model /kaggle/working/ppo_guard \
    --episodes 100 \
    --export /kaggle/working/policy.json
```

Look for `win_rate` in the output. It should be substantially better than
zero. A short run is only a smoke experiment; compare multiple seeds and
training lengths before drawing conclusions.

### Inspect output files

```python
!ls -lh /kaggle/working/ppo_guard.zip
!ls -lh /kaggle/working/policy.json
```

### Create one downloadable archive

```python
!cd /kaggle/working && zip -j npc-fsm-trained-policy.zip ppo_guard.zip policy.json
```

Create a download link inside the notebook:

```python
from IPython.display import FileLink, display

display(FileLink("/kaggle/working/npc-fsm-trained-policy.zip"))
```

Download the archive from the displayed link or from the notebook's Output
panel. Do not type a file path by itself in a Python cell; that causes a
`NameError`.

## What the files mean

```text
ppo_guard.zip
    Stable-Baselines3 PPO checkpoint. Used by the Python evaluator.

policy.json
    Exported policy metadata and neural-network weights. It is currently an
    interchange artifact; guard.nut does not load it yet.
```

Do not commit these generated artifacts to the Git repository. The next runtime
integration step is a host-side inference adapter that converts the game's
world state into the same observation order and lets the FSM validate the
model's action recommendation.
