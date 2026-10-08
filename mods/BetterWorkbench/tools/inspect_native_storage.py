"""Read-only storage registration and function disassembly for the local game."""
from pathlib import Path
import json
import struct
import sys
import re
from bisect import bisect_right
from types import SimpleNamespace

import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[3] / 'tools'))
from palmods import GAME_EXE, build_directory

ROOT=Path(__file__).resolve().parents[1]
import pefile
from capstone import Cs, CS_ARCH_X86, CS_MODE_64

GAME = GAME_EXE
p=pefile.PE(str(GAME),fast_load=True)
directory=p.OPTIONAL_HEADER.DATA_DIRECTORY[pefile.DIRECTORY_ENTRY['IMAGE_DIRECTORY_ENTRY_EXCEPTION']]
ranges=[SimpleNamespace(BeginAddress=a,EndAddress=b) for a,b,_ in struct.iter_unpack('<III',p.get_data(directory.VirtualAddress,directory.Size))]
starts=[e.BeginAddress for e in ranges]
data=GAME.read_bytes()
base=p.OPTIONAL_HEADER.ImageBase
decoder=Cs(CS_ARCH_X86,CS_MODE_64)
def code(rva):
    return any(s.Characteristics & 0x20000000 and s.VirtualAddress<=rva<s.VirtualAddress+s.Misc_VirtualSize for s in p.sections)
def dump(rva):
    index=bisect_right(starts,rva)-1
    boundary=ranges[index] if index>=0 and ranges[index].BeginAddress<=rva<ranges[index].EndAddress else None
    if not boundary:
        print(f'RAW 0x{rva:x}')
        for i in decoder.disasm(p.get_data(rva,160),rva): print(f'{i.address:x} {i.mnemonic} {i.op_str}')
        return
    print(f'FUNCTION 0x{boundary.BeginAddress:x}..0x{boundary.EndAddress:x}')
    for i in decoder.disasm(p.get_data(boundary.BeginAddress,boundary.EndAddress-boundary.BeginAddress),boundary.BeginAddress):
        print(f'{i.address:x} {i.mnemonic} {i.op_str}')
if len(sys.argv)>1 and sys.argv[1]=='--strings':
    names=sys.argv[2:]
    targets={}
    for name in names:
        for encoding in ('ascii','utf-16-le'):
            token=name.encode(encoding); start=0
            while (at:=data.find(token,start))>=0:
                start=at+1
                targets[p.get_rva_from_offset(at)]=name
                beginning=at
                step=2 if encoding=='utf-16-le' else 1
                while beginning>=step:
                    c=int.from_bytes(data[beginning-step:beginning],'little')
                    if not 32<=c<=126: break
                    beginning-=step
                targets[p.get_rva_from_offset(beginning)]=name+' (full diagnostic string)'
    for section in p.sections:
        if not section.Characteristics&0x20000000: continue
        block=section.get_data()
        for match in re.finditer(rb'[\x48\x4c]\x8d[\x05\x0d\x15\x1d\x25\x2d\x35\x3d]',block):
            at=match.start(); rva=section.VirtualAddress+at
            target=rva+7+struct.unpack_from('<i',block,at+3)[0]
            if target not in targets: continue
            index=bisect_right(starts,rva)-1
            boundary=ranges[index]
            owner=boundary.BeginAddress if boundary.BeginAddress<=rva<boundary.EndAddress else None
            print(targets[target], 'string',hex(target),'xref',hex(rva),'function',hex(owner) if owner else 'unknown')
elif len(sys.argv)>1 and sys.argv[1]=='--calls':
    targets={int(value,16) for value in sys.argv[2:]}
    for section in p.sections:
        if not section.Characteristics&0x20000000: continue
        block=section.get_data()
        for match in re.finditer(rb'\xe8',block):
            at=match.start()
            if at+5>len(block): continue
            rva=section.VirtualAddress+at
            target=rva+5+struct.unpack_from('<i',block,at+1)[0]
            if target not in targets: continue
            index=bisect_right(starts,rva)-1
            boundary=ranges[index]
            if not boundary.BeginAddress<=rva<boundary.EndAddress: continue
            # Reject an E8 byte embedded in another instruction.
            instructions=decoder.disasm(p.get_data(boundary.BeginAddress,rva+5-boundary.BeginAddress),boundary.BeginAddress)
            if any(i.address==rva and i.mnemonic=='call' for i in instructions):
                print('target',hex(target),'call',hex(rva),'return',hex(rva+5),'function',hex(boundary.BeginAddress))
elif len(sys.argv)>1:
    for token in sys.argv[1:]: dump(int(token,16))
else:
    targets=['ExtendSlotNum_ServerInternal','UpdateSlotNum_ServerInternal','GetSlotNum',
        'GetSlotIndexesMaterialInput','GetItemContainer','GetItemContainerId','GetSlot','SetSlotNum',
        'GetInputItemContainer','GetOutputItemContainer','GetSlotNumInPage','GetOutputContainer']
    results={}
    for target in targets:
        candidates=set()
        for encoding,term in [('ascii',b'\0'),('utf-16-le',b'\0\0')]:
            token=target.encode(encoding)+term
            pos=0
            while (pos:=data.find(token,pos))>=0:
                name_offset=pos; pos+=1
                try: pointer=base+p.get_rva_from_offset(name_offset)
                except pefile.PEFormatError: continue
                pair=0; needle=struct.pack('<Q',pointer)
                while (pair:=data.find(needle,pair))>=0:
                    at=pair; pair+=1
                    if at%8 or at+16>len(data): continue
                    address=struct.unpack_from('<Q',data,at+8)[0]-base
                    if code(address): candidates.add(address)
        results[target]=[hex(rva) for rva in sorted(candidates)]
    (build_directory('BetterWorkbench')/'storage-registration.json').write_text(json.dumps(results,indent=2))
    print(json.dumps(results,indent=2))
