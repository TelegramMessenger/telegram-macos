from pathlib import Path
import ctypes
import gzip
import sys

root = Path(__file__).resolve().parents[3]
lib = ctypes.CDLL(sys.argv[1])
lib.tlottie_new_with_options.argtypes = [ctypes.c_char_p, ctypes.c_size_t, ctypes.c_uint32, ctypes.c_void_p, ctypes.c_size_t, ctypes.c_void_p, ctypes.c_size_t, ctypes.c_uint32]
lib.tlottie_new_with_options.restype = ctypes.c_void_p
lib.tlottie_render.argtypes = [ctypes.c_void_p, ctypes.c_float, ctypes.c_uint32, ctypes.c_uint32, ctypes.POINTER(ctypes.c_uint32), ctypes.c_size_t, ctypes.c_uint32]
lib.tlottie_render.restype = ctypes.c_int32
lib.tlottie_drop.argtypes = [ctypes.c_void_p]
lib.tlottie_drop.restype = None
source = gzip.decompress((root / "Resources/tgs/duck_empty.tgs").read_bytes())
animation = lib.tlottie_new_with_options(source, len(source), 0, None, 0, None, 0, 1)
assert animation
pixels = (ctypes.c_uint32 * (240 * 240))()
assert lib.tlottie_render(animation, 20, 240, 240, pixels, 240 * 240, 1) == 0
Path(sys.argv[2]).write_bytes(bytes(pixels))
lib.tlottie_drop(animation)
