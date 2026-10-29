#!/usr/bin/env python3
"""Print the A/B state of every _a/_b partition pair on the given GPT disks (primary + backup table).
Read-only. Usage: gptstate.py /dev/sda /dev/sdb ... """
import struct, sys, uuid, zlib
INACTIVE=uuid.UUID('77036cd4-03d5-42bb-8ed1-37e5a88baa34')
def rd(f,off,n): f.seek(off); return f.read(n)
def hdr(b):
    f=struct.unpack('<8sIIIIQQQQ16sQIII',b[:92])
    if f[0]!=b'EFI PART': return None
    return dict(hsz=f[2],hcrc=f[3],cur=f[5],bak=f[6],pe_lba=f[10],npe=f[11],pesz=f[12],pecrc=f[13])
def table(f,bs,h):
    blob=rd(f,h['pe_lba']*bs,h['npe']*h['pesz']); crc=zlib.crc32(blob)&0xffffffff
    ents={}
    for i in range(h['npe']):
        e=blob[i*h['pesz']:(i+1)*h['pesz']]
        if e==bytes(len(e)): continue
        name=e[56:128].decode('utf-16-le').rstrip('\0')
        ents[name]=(uuid.UUID(bytes_le=e[:16]), struct.unpack('<Q',e[48:56])[0])
    return ents, crc==h['pecrc']
def attrs(a):
    ab=(a>>48)&0xffff
    return f"pri={ab&3} act={(ab>>2)&1} retry={(ab>>3)&7} succ={(ab>>6)&1} unboot={(ab>>7)&1}"
for dev in sys.argv[1:]:
    f=open(dev,'rb'); bs=4096
    p=hdr(rd(f,bs,bs))
    if not p: bs=512; p=hdr(rd(f,bs,bs))
    if not p: print(dev,'no GPT'); continue
    b=hdr(rd(f,p['bak']*bs,bs))
    P,pok=table(f,bs,p); B,bok=table(f,bs,b) if b else ({},False)
    print(f"== {dev} bs={bs} entries={len(P)} primaryCRC={'ok' if pok else 'BAD'} backupCRC={'ok' if bok else 'BAD'} backup_matches_primary={'yes' if P==B else 'NO'}")
    for n in sorted(P):
        if not n.endswith('_a'): continue
        m=n[:-2]+'_b'
        if m not in P: continue
        ta,aa=P[n]; tb,ab=P[m]
        def g(t): return 'MARKER' if t==INACTIVE else str(t)[:8]
        print(f"  {n[:-2]:<12} a:{g(ta):<8} {attrs(aa)}   b:{g(tb):<8} {attrs(ab)}")
    if len(P) <= 6:
        for n in sorted(P): print(f"  {n:<16} type={'MARKER' if P[n][0]==INACTIVE else str(P[n][0])} {attrs(P[n][1])}")
