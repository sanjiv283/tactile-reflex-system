import sys, json
sys.path.insert(0, "/home/user/tactile-reflex-system/demo_video/build")
import importlib
tl = json.load(open("/home/user/tactile-reflex-system/demo_video/audio/timeline.json"))
mod, cls, sid, times = sys.argv[1], sys.argv[2], int(sys.argv[3]), [float(x) for x in sys.argv[4:]]
M = importlib.import_module(mod); sc = getattr(M, cls)(tl["scenes"][sid])
for t in times:
    sc.frame(t).save(f"/tmp/claude-0/-home-user-tactile-reflex-system/9b6cb197-2d64-5301-8a19-d5cb01423396/scratchpad/videowork/{cls}_{t:05.1f}.png"); print("saved", cls, t)
