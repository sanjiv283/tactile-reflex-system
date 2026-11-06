"""Export caption-free PNG stills from the scene renderers (same code as the video) into demo_video/diagrams/."""
import sys, json, os, importlib
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
HERE = "/home/user/tactile-reflex-system/demo_video/"
TL = json.load(open(HERE + "audio/timeline.json"))
# (file name, module, class, scene index, beat index, offset from the beat end)
ITEMS = [("01_title.png", "scenes_a", "S1", 0, 2, -0.1), ("02_problem_latency.png", "scenes_a", "S2", 1, 2, -0.1), ("03_architecture.png", "scenes_a", "S3", 2, 8, -0.1),
         ("04_adc_spi_frame.png", "scenes_a", "S4", 3, 0, -0.1), ("05_input_conditioning.png", "scenes_a", "S4", 3, 1, -0.1), ("06_lookup_table_curve.png", "scenes_a", "S4", 3, 2, -0.1),
         ("07_safety_governor.png", "scenes_a", "S4", 3, 3, -0.1), ("08_pwm_generation.png", "scenes_a", "S4", 3, 4, -0.1),
         ("09_force_limit_override_waveform.png", "scenes_b", "S5", 4, 0, -0.1), ("10_predictive_trip.png", "scenes_b", "S5", 4, 1, -0.1), ("11_predictive_trip_cost.png", "scenes_b", "S5", 4, 2, -0.1),
         ("12_hysteresis.png", "scenes_b", "S5", 4, 3, -0.1), ("13_emergency_stop.png", "scenes_b", "S5", 4, 4, -0.1), ("14_invalid_sensor_frames.png", "scenes_b", "S5", 4, 5, -0.1),
         ("15_watchdog.png", "scenes_b", "S5", 4, 6, -0.1), ("16_safe_state_rules.png", "scenes_b", "S5", 4, 7, -0.1),
         ("17_regression_checks.png", "scenes_b", "S6", 5, 0, -0.1), ("18_replay_zero_violations.png", "scenes_b", "S6", 5, 1, -0.1), ("19_model_rtl_baseline.png", "scenes_b", "S6", 5, 2, -0.1),
         ("20_noisy_crossing_baseline_vs_hysteresis.png", "scenes_b", "S6", 5, 3, -0.1), ("21_latency.png", "scenes_b", "S6", 5, 4, -0.1), ("22_validation_counts.png", "scenes_b", "S6", 5, 5, -0.1),
         ("23_simulated_ml_accuracy.png", "scenes_b", "S6", 5, 6, -0.1), ("24_what_is_not_established.png", "scenes_b", "S6", 5, 7, -0.1),
         ("25_end_to_end_4_cycles.png", "scenes_b", "S7", 6, 2, -0.1), ("26_contributions.png", "scenes_b", "S8", 7, 1, -0.1), ("27_proposed_next_steps.png", "scenes_b", "S8", 7, 3, -0.1)]
os.makedirs(HERE + "diagrams", exist_ok=True); cache = {}
for fn, mod, cls, si, bi, off in ITEMS:
    if cls not in cache: cache[cls] = getattr(importlib.import_module(mod), cls)(TL["scenes"][si])
    sc = cache[cls]; t = sc.beats[bi]["t1"] + off
    sc.frame(t, captions=False, fade=False).save(HERE + "diagrams/" + fn, optimize=True); print("saved", fn, f"scene {si + 1} t={t:.1f}s", flush=True)
