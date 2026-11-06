"""Minimal espeak-ng text-to-speech via ctypes using the espeakng-loader wheel's bundled library (no system install)."""
import ctypes, wave, numpy as np
try:   # pip install espeakng-loader  (the wheel bundles libespeak-ng and its data; no system install needed)
    import espeakng_loader as _e
    LIB, DATA = _e.get_library_path(), _e.get_data_path()
except ImportError:
    import os
    LIB, DATA = os.environ["ESPEAK_LIB"], os.environ["ESPEAK_DATA"]
_lib = ctypes.CDLL(LIB); _buf = []
CB = ctypes.CFUNCTYPE(ctypes.c_int, ctypes.POINTER(ctypes.c_short), ctypes.c_int, ctypes.c_void_p)
def _cb(wav, n, ev):
    if wav and n > 0: _buf.append(np.ctypeslib.as_array(wav, shape=(n,)).copy())
    return 0
_cbf = CB(_cb)
_lib.espeak_Initialize.restype = ctypes.c_int
RATE = _lib.espeak_Initialize(1, 0, DATA.encode(), 0)   # AUDIO_OUTPUT_RETRIEVAL
_lib.espeak_SetSynthCallback(_cbf)
def synth(text, voice=b"en-us", wpm=150, pitch=50, rng=50):
    _buf.clear()
    _lib.espeak_SetVoiceByName(voice)
    _lib.espeak_SetParameter(1, wpm, 0); _lib.espeak_SetParameter(3, pitch, 0); _lib.espeak_SetParameter(4, rng, 0)
    b = text.encode("utf-8"); _lib.espeak_Synth(b, len(b) + 1, 0, 0, 0, 1, None, None); _lib.espeak_Synchronize()
    return (np.concatenate(_buf).astype(np.float32) / 32768.0) if _buf else np.zeros(1, np.float32), RATE
if __name__ == "__main__":
    x, sr = synth("The safety governor forces the PWM output low on the very next clock cycle.")
    print("sample rate", sr, "seconds", round(len(x) / sr, 2), "peak", float(np.abs(x).max()))
