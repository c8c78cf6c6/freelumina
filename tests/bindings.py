"""The small public C ABI, kept separate from test expectations."""

import ctypes as ct


X64 = 1
ARM64 = 2
SYSV = 0
WINDOWS = 1


class Region(ct.Structure):
    _fields_ = [
        ("address", ct.c_int64),
        ("size", ct.c_int64),
        ("bytes", ct.c_void_p),
        ("executable", ct.c_int32),
        ("reserved", ct.c_int32),
    ]


class Result(ct.Structure):
    _fields_ = [
        ("target", ct.c_int64),
        ("status", ct.c_int32),
        ("candidates", ct.c_int32),
        ("references", ct.c_int32),
        ("reason", ct.c_int32),
    ]


class Instruction(ct.Structure):
    _fields_ = [
        (name, ct.c_int64)
        for name in ("address", "target", "immediate", "writes")
    ] + [
        (name, ct.c_int32)
        for name in (
            "size", "kind", "dst", "src", "base", "index",
            "displacement_offset", "displacement_size", "relative", "unsafe",
        )
    ]


class Core:
    def __init__(self, path):
        self.library = ct.CDLL(str(path))
        self.library.fl_analyze.argtypes = [
            ct.c_int, ct.c_int, ct.POINTER(Region), ct.c_int,
            ct.c_int64, ct.c_int64, ct.POINTER(Result),
        ]
        self.library.fl_analyze.restype = None
        self.library.fl_plan.argtypes = [
            ct.c_int, ct.c_int, ct.c_void_p, ct.c_size_t,
            ct.c_int64, ct.c_int64, ct.c_void_p, ct.POINTER(ct.c_int),
            ct.c_void_p, ct.POINTER(ct.c_int),
        ]
        self.library.fl_plan.restype = ct.c_int
        self.library.fl_decoder_open.argtypes = [ct.c_int]
        self.library.fl_decoder_open.restype = ct.c_void_p
        self.library.fl_decoder_close.argtypes = [ct.c_void_p]
        self.library.fl_decoder_close.restype = None
        self.library.fl_decode.argtypes = [
            ct.c_void_p, ct.c_void_p, ct.c_size_t, ct.c_int64,
            ct.POINTER(Instruction),
        ]
        self.library.fl_decode.restype = ct.c_int

    def analyze(self, arch, abi, spans, exported=0, license_address=0):
        """Spans are (virtual address, immutable bytes, executable flag)."""
        owners = [ct.create_string_buffer(data) for _, data, _ in spans]
        regions = (Region * len(spans))(*(
            Region(address, len(data), ct.addressof(owner), executable, 0)
            for (address, data, executable), owner in zip(spans, owners)
        ))
        result = Result()
        self.library.fl_analyze(
            arch, abi, regions, len(regions), exported, license_address,
            ct.byref(result),
        )
        return result

    def plan(self, arch, abi, prefix, address=0x100000, trampoline=0x110000):
        source = ct.create_string_buffer(prefix)
        code = (ct.c_ubyte * 512)()
        patch = (ct.c_ubyte * 32)()
        code_size = ct.c_int()
        patch_size = ct.c_int()
        success = self.library.fl_plan(
            arch, abi, source, len(prefix), address, trampoline,
            code, ct.byref(code_size), patch, ct.byref(patch_size),
        )
        return success, bytes(code[:code_size.value]), bytes(patch[:patch_size.value])

    def decode(self, arch, data, address=0x100000):
        decoder = self.library.fl_decoder_open(arch)
        if not decoder:
            raise RuntimeError("decoder initialization failed")
        try:
            source = ct.create_string_buffer(data)
            result = Instruction()
            if not self.library.fl_decode(decoder, source, len(data), address, ct.byref(result)):
                return None
            return result
        finally:
            self.library.fl_decoder_close(decoder)
