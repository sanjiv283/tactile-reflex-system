# Tactile Reflex System: demonstration video

`tactile_reflex_demo.mp4` is a 1920×1080, 30 fps, H.264 + AAC technical demonstration of the project, 7 min 5 s long (425.7 s).
It is **entirely simulation**: every waveform and number comes from the project's own RTL simulation logs and experiment files.
No physical hardware was run, no Wokwi run was performed, and the AI dataset is simulated. The video says all of this on screen.

## What is in this folder

| Path | Content |
|---|---|
| `tactile_reflex_demo.mp4` | the final video |
| `captions.srt` | subtitles (also burned into the video) |
| `script_and_narration.md` | full transcript with timestamps and the exact speech text |
| `scene_breakdown.md` | scene-by-scene table: timing, what is on screen, evidence |
| `evidence_used.md` | every claim → value → source file; plus what is deliberately not claimed |
| `diagrams/` | PNG stills exported from the same renderer (architecture, waveforms, results) without captions |
| `build/` | all code that generated the video |
| `audio/` | per-sentence narration (`narration/*.wav`), `timeline.json` (single source of truth for timing), final mix as `mix.flac` (lossless; `build/mix.py` regenerates `mix.wav`) |
| `qa_report.txt` | output of the quality audit (claims check, media checks, sync check) |

## How it was generated

All visuals are drawn frame by frame with Python (Pillow) directly from real data files, piped to FFmpeg (libx264).
Nothing is a stock clip or a screen recording, and nothing is fabricated.

1. `build/script.py`: narration text (caption + pronunciation-safe speech text) for 46 sentences in 8 scenes.
2. `build/audio.py`: synthesises each sentence with **espeak-ng** (via the `espeakng-loader` wheel, no system install), builds `audio/timeline.json`.
3. `build/data.py`: read-only loaders for the project evidence (`results/`, `experiments/results_v2/`, `experiments/validation/results_v2/`, `rtl/`).
4. `build/scenes_a.py`, `build/scenes_b.py`: the eight scene renderers; each is driven by the beat times in `timeline.json`, so visuals and speech cannot drift apart.
5. `build/render.py`: renders the eight scenes in parallel and concatenates them.
6. `build/mix.py`: synthesises the ambient music bed (numpy), places narration at timeline positions, ducks music under speech, writes `audio/mix.wav` (stored here as `mix.flac`).
7. Final mux: FFmpeg (`loudnorm` to −16 LUFS, AAC 192 kbit/s, `+faststart`).
8. `build/docs.py`: generates the transcript, SRT, breakdown and evidence list from the same timeline and data files.
9. `build/qa.py`: the audit (see below).

### Reproduce
```bash
python3 -m venv v && v/bin/pip install espeakng-loader numpy scipy pillow     # FFmpeg and Icarus Verilog must be on PATH
cd demo_video/build
../../v/bin/python audio.py            # narration + timeline.json   (note: regenerates audio/narration and the timeline)
../../v/bin/python render.py video     # frames -> scenes -> video_only.mp4 (several minutes on 4 cores)
../../v/bin/python mix.py              # music + mix.wav
../../v/bin/python docs.py             # transcript, SRT, breakdown, evidence list
../../v/bin/python qa.py claims        # numbers vs evidence files
```
`render.py` writes its intermediate scene clips to a scratch directory set at the top of the file (`WORK`); change it for your machine.

## Quality audit (`qa_report.txt`)

* **Claims check:** `qa.py claims` re-reads the evidence files and asserts 22 facts quoted in the video (175/175 checks, replay violations, latency cycles, S08 trip at 2015 vs limit at 2569, hysteresis 2304/2303, 577/839/13 comparison counts, WD_CYCLES, etc.).
* **Media check:** codec, resolution, frame rate, audio/video duration agreement, clipping.
* **Sync check:** decodes the *final MP4's* audio, finds each narration onset, and compares it with the scripted beat time that drives the visuals.

## Status against the current repository (audit of 2026-11-06)

The video is a **snapshot** of the project as of git commit `96b5025`. Since then the RTL was hardened and the verification extended, so some headline numbers in the video are **older than the repository's**:

| Statement in the video | At render time | Now (`results/regression_summary.json`) |
|---|---|---|
| "All 175 directed checks across 12 testbenches pass" | true (that log is pinned in `evidence_snapshot/sim_log_at_render.txt`) | the same 12 testbenches now hold 178 assertions (monitor checks added); the full regression is 18 testbenches / 4236 assertions (460 directed + 2 x 1,888 replay invariant evaluations) |
| Replay: 1,800 vectors x 2 modes, 0 violations | true | still true (`tb_replay`, `tb_replay_adversarial`) |
| Latencies (4 / 5 / 105-192 clocks), 577 + 839 comparisons, 159/159, 157/159, 93/159, 13/839 | true | re-verified on the hardened RTL (`tools/check_experiments.sh`, `tools/check_validation.sh`: byte-identical outputs) |
| Simulated-ML numbers (91.9 %, 85.4 %, 72 % class-3 recall, 25/25 early, 6.5 % false early) | true | unchanged (`tools/check_artifacts.py`) |

Not mentioned in the video: the UART receiver repair, reset synchroniser, debounced clear key, 47-mutant campaign, safety monitor, bounded formal check. The video still says nothing false about hardware: it states on screen that everything is simulation.

`build/qa.py claims` passes (22/22) against the pinned snapshot. **The video was not re-rendered** because the render pipeline overwrites `audio/timeline.json` and the narration (this folder is not under version control, so the original would be lost). To update it: copy `demo_video/` elsewhere, change the sentence in `build/script.py` (scene 6) and the `175 ... 12 testbenches` text in `build/scenes_b.py`, switch `data.sim_log()` back to `results/sim_log.txt`, and run the steps in "Reproduce" there. This is recommended before external use, and needs the author's decision.

## Known limitations

* **Voice quality.** No neural TTS model could be downloaded here (HuggingFace was blocked), so the narration uses espeak-ng. It is clear but robotic. The transcript and subtitles are provided so the narration can be re-recorded; replacing the narration in the mix with a human voice at the timeline positions needs no change to the visuals.
* **Music** is a simple synthesised ambient bed, not composed or licensed music.
* **Small text.** Footer tags and chart tick labels are 15–19 px at 1080p: legible full-screen but small on a phone.
* **Waveforms** are drawn from logged simulation samples (results/trace_*.csv, RTL replay logs); they are not oscilloscope captures and are labelled as RTL simulation.
* **The PWM waveform in scene 4** is an illustration computed from the RTL's own equation and is labelled as such.
* The Wokwi software demonstration is shown only as "prepared, not yet run".
