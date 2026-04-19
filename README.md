# MTSleepScoring

Interactive MATLAB GUI for manual sleep-stage scoring on multitaper EEG spectrograms, from the [Prerau Laboratory](https://prerau.bwh.harvard.edu/). Built on the `MTSleepScorer` class plus the lab's [`EventMarker`](https://github.com/preraulab/EventMarker) and [`multitaper_toolbox`](https://github.com/preraulab/multitaper_toolbox).

## What it does

Loads EDF polysomnography, computes a whole-night multitaper spectrogram plus stage-level high-resolution spectrograms, and provides a keyboard-driven GUI for marking 30 s (or arbitrary-length) stages, flagging artifacts, and exporting scored data.

Key features:

- Overview multitaper spectrogram (0.5–35 Hz, 30 s / 15 s window/step) + stage-level high-res spectrogram (6 s / 1 s)
- Full keyboard-driven stage entry (3-stage or 5-stage scoring)
- Automatic artifact detection (`x`) and manual artifact marking (`a`)
- Slice power-spectrum overlay (`u`), 3-D regional popouts (`d`)
- Electrode cycling (`,` / `.`), pan/zoom via arrow keys and scroll wheel
- JSON-like save/load of scoring sessions keyed by scorer initials

## Keyboard shortcuts

| Key | Action |
|---|---|
| `←` / `→` (or scroll wheel) | Pan one screen-width |
| `↑` / `↓` (or shift + scroll) | Zoom |
| `z` | Set zoom window size |
| `,` / `.` | Cycle through electrodes |
| `w` / `5` | Mark Wake |
| `r` / `4` | Mark REM |
| `n` then `1`/`2`/`3` | Mark NREM N1 / N2 / N3 |
| `x` | Automatic artifact detection |
| `a` | Add manual artifact |
| `u` | Toggle slice power spectrum |
| `d` | 3-D popout of selected region |
| `h` | Toggle help window |
| `q` | Quit |

## Quick start

```matlab
% 1. Edit the paths at the top of MT_scoring_init_script.m:
%    root      = '<path to this repo>';
%    data_path = fullfile(root, 'data');
%    save_path = fullfile(root, 'scoring');
%
% 2. Launch the scorer:
obj = MTSleepScorer();
```

The included `data/Test_Subject.edf` provides a one-night example. Scoring sessions are saved under `save_path` and tagged with the scorer's initials so multiple scorers can work on the same recording.

## Install

```bash
git clone https://github.com/preraulab/MTSleepScoring.git
```

Add the repo plus its dependencies to the MATLAB path:

```matlab
addpath(genpath('/path/to/MTSleepScoring'));
addpath(genpath('/path/to/EventMarker'));
addpath(genpath('/path/to/multitaper_toolbox/matlab'));
```

## Dependencies

- MATLAB R2020a+
- [`EventMarker`](https://github.com/preraulab/EventMarker) — event marking on MATLAB axes
- [`multitaper_toolbox`](https://github.com/preraulab/multitaper_toolbox) — multitaper spectrogram

## Citation

See [`CITATION.cff`](CITATION.cff).

## License

BSD 3-Clause. See [`LICENSE`](LICENSE).

## Contact

Michael J. Prerau, Ph.D. — <prerau@bwh.harvard.edu> — [sleepEEG.org](https://prerau.bwh.harvard.edu/)
