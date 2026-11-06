"""Render the full demo video: scenes -> frames (piped to ffmpeg) -> concat -> audio mix -> final MP4.
Usage: python3 render.py video   (video only, parallel)   |   python3 render.py mix   (audio mix + mux)   |   python3 render.py all"""
import sys, json, os, subprocess, time, importlib
from multiprocessing import Pool
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
HERE = "/home/user/tactile-reflex-system/demo_video/"
WORK = "/tmp/claude-0/-home-user-tactile-reflex-system/9b6cb197-2d64-5301-8a19-d5cb01423396/scratchpad/videowork/render/"
TL = json.load(open(HERE + "audio/timeline.json")); FPS = TL["fps"]
CLASSES = [("scenes_a", "S1"), ("scenes_a", "S2"), ("scenes_a", "S3"), ("scenes_a", "S4"), ("scenes_b", "S5"), ("scenes_b", "S6"), ("scenes_b", "S7"), ("scenes_b", "S8")]

def render_scene(i):
    mod, cls = CLASSES[i]; sc = getattr(importlib.import_module(mod), cls)(TL["scenes"][i]); n = TL["scenes"][i]["frames"]
    out = WORK + f"scene_{i + 1}.mp4"
    p = subprocess.Popen(["ffmpeg", "-y", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", "1920x1080", "-r", str(FPS), "-i", "-", "-c:v", "libx264", "-preset", "medium", "-crf", "18", "-pix_fmt", "yuv420p", "-r", str(FPS), out], stdin=subprocess.PIPE)
    t0 = time.time()
    for f in range(n): p.stdin.write(sc.frame(f / FPS).tobytes())
    p.stdin.close(); p.wait(); return i + 1, n, round(time.time() - t0, 1)

def video():
    os.makedirs(WORK, exist_ok=True)
    order = [4, 5, 3, 2, 1, 0, 6, 7]   # longest scenes first
    with Pool(4) as pool:
        for r in pool.imap_unordered(render_scene, order): print("scene", r[0], "frames", r[1], "sec", r[2], flush=True)
    with open(WORK + "list.txt", "w") as f:
        for i in range(8): f.write(f"file '{WORK}scene_{i + 1}.mp4'\n")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "concat", "-safe", "0", "-i", WORK + "list.txt", "-c", "copy", WORK + "video_only.mp4"], check=True)

if __name__ == "__main__":
    if sys.argv[1] in ("video", "all"): video()
