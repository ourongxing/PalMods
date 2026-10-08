"""Read exception and stack module addresses from a Windows minidump."""
import struct
import sys
from pathlib import Path

data = Path(sys.argv[1]).read_bytes()
def u32(at): return struct.unpack_from('<I', data, at)[0]
def u64(at): return struct.unpack_from('<Q', data, at)[0]
streams = {u32(at): (u32(at+4),u32(at+8)) for at in range(u32(12),u32(12)+u32(8)*12,12)}
mods = []
at = streams[4][1]
for i in range(u32(at)):
    p=at+4+i*108
    s=u32(p+20)
    name=data[s+4:s+4+u32(s)].decode('utf-16-le')
    mods.append((u64(p),u32(p+8),name))
def describe(addr):
    for base,size,name in mods:
        if base <= addr < base+size: return f'{Path(name).name}+0x{addr-base:x}'
    return hex(addr)
exc=streams[6][1]
tid=u32(exc)
print('Exception:',hex(u32(exc+8)), 'at', describe(u64(exc+24)), 'thread',tid)
context=u32(exc+164)
print('RIP:',describe(u64(context+248)), 'RSP:',hex(u64(context+152)))
print('Registers:', {reg:hex(u64(context+offset)) for reg,offset in [('RAX',120),('RCX',128),('RDX',136),('RBX',144),('RBP',160),('RSI',168),('RDI',176),('R8',184),('R9',192)]})
threads=streams[3][1]
for i in range(u32(threads)):
    p=threads+4+i*48
    if u32(p)!=tid: continue
    start=u64(p+24);size=u32(p+32);rva=u32(p+36)
    rsp=u64(context+152)
    for off in range(max(0,rsp-start), min(size,max(0,rsp-start)+2048),8):
        addr=u64(rva+off)
        label=describe(addr)
        if '+' in label: print(f'Stack+0x{start+off-rsp:x}:',label)
for base,size,name in mods:
    if any(s in name.lower() for s in ('ue4ss','smartrecipe')): print('Module:',hex(base),name)
