"""Exercise the actual game's quantity constructor in isolated test memory.

Copies only this verified arithmetic helper, relocates its read-only constants,
and substitutes a deterministic rand callback. Does not load, run or patch the
game, UE4SS or a save. This verifies the Windows x64 nine-argument ABI as well
as fractional-world-rate and additive-bonus behavior.
"""
from pathlib import Path
import ctypes as c
import hashlib
import struct
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / 'tools'))
from palmods import GAME_EXE
import pefile
from capstone import Cs, CS_ARCH_X86, CS_MODE_64
from capstone.x86 import X86_OP_MEM, X86_REG_RIP

EXPECTED = 'e590b5e7bfaa3fea40fab1a02cc72c8fc5fd6f8631ef2308e95ac56c25195837'
start, length = 0x2e6bf70, 0x13f
if '--server' in sys.argv:
    GAME_EXE = Path(r'G:\PalworldTestServer\Pal\Binaries\Win64\PalServer-Win64-Shipping-Cmd.exe')
    EXPECTED = '6f929673e7ac637d591d6f3454dbd396be7911093311cb8b24af3a152b217f49'
    start = 0x2d16750
assert hashlib.file_digest(GAME_EXE.open('rb'), 'sha256').hexdigest() == EXPECTED
pe = pefile.PE(str(GAME_EXE), fast_load=True)
code = bytearray(pe.get_data(start, length))
decoder = Cs(CS_ARCH_X86, CS_MODE_64)
decoder.detail = True
random_sample = [0]
rand = c.CFUNCTYPE(c.c_int)(lambda: random_sample[0])
pool = bytearray()
for instruction in decoder.disasm(code, start):
    for operand in instruction.operands:
        if operand.type != X86_OP_MEM or operand.mem.base != X86_REG_RIP:
            continue
        target = instruction.address + instruction.size + operand.mem.disp
        relocated = 512 + len(pool)
        value = struct.pack('<Q', c.cast(rand, c.c_void_p).value) if instruction.mnemonic == 'call' else pe.get_data(target, 8)
        pool.extend(value)
        offset = instruction.address - start
        assert instruction.disp_size == 4
        struct.pack_into('<i', code, offset + instruction.disp_offset,
                         relocated - (offset + instruction.size))
image = code + bytes(512 - len(code)) + pool

kernel = c.WinDLL('kernel32', use_last_error=True)
kernel.VirtualAlloc.argtypes = [c.c_void_p, c.c_size_t, c.c_ulong, c.c_ulong]
kernel.VirtualAlloc.restype = c.c_void_p
kernel.VirtualProtect.argtypes = [c.c_void_p, c.c_size_t, c.c_ulong, c.POINTER(c.c_ulong)]
kernel.VirtualFree.argtypes = [c.c_void_p, c.c_size_t, c.c_ulong]
memory = kernel.VirtualAlloc(None, 4096, 0x3000, 0x04)
assert memory
try:
    c.memmove(memory, bytes(image), len(image))
    previous = c.c_ulong()
    assert kernel.VirtualProtect(memory, 4096, 0x20, c.byref(previous))

    class Location(c.Structure):
        _fields_ = [('x', c.c_double), ('y', c.c_double), ('z', c.c_double)]
    class Drop(c.Structure):
        _fields_ = [('item', c.c_uint64), ('count', c.c_int32), ('padding', c.c_int32), ('location', Location)]
    assert c.sizeof(Drop) == 40 and Drop.location.offset == 16
    function = c.CFUNCTYPE(c.POINTER(Drop), c.c_void_p, c.POINTER(Drop), c.c_uint64,
                          c.c_float, c.c_float, c.c_int32, c.c_int32, c.c_float, c.POINTER(Location))(memory)
    def calculate(world, bonus, chance=100.0):
        entry = Drop()
        position = Location(10, 20, 30)
        result = function(None, c.byref(entry), 12345, chance, bonus, 1, 1, world, c.byref(position))
        assert c.addressof(result.contents) == c.addressof(entry)
        assert entry.item == 12345 and entry.location.y == 20
        return entry.count
    assert calculate(1, 0) == 1
    assert calculate(3, 0) == 3
    assert calculate(0, 0) == 0
    assert calculate(3, 1) == 4  # native addition, not applying a second multiplier
    assert calculate(1, 2) == 3
    assert calculate(1, -1) == 1
    for world in (0.1, 0.25, 0.5, 1.5, 2.5, 3.0):
        print(f'Native quantity: world={world} bonus=0 -> {calculate(world, 0)}')
    for _ in range(10000):
        assert calculate(3, 1) == 4
    random_sample[0] = 32767
    assert calculate(3, 1, 50.0) == 0
    assert calculate(3, 1, 100.0) == 4
    random_sample[0] = 0
    assert calculate(3, 1, 50.0) == 4
    successes = 0
    for value in range(32768):
        random_sample[0] = value
        successes += calculate(1, 0, 50.0) == 1
    assert successes == 16384
    print('PASS: native quantity ABI/modifiers, 10000 calls, 50% hit/miss and all 32768 RNG outcomes')
finally:
    assert kernel.VirtualFree(memory, 0, 0x8000)
