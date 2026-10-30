# Absolute-address references in .text: every lis rD,hi followed (within 12 instructions, rD
# untouched) by an addi / d-form load or store off rD, folded into the address it names. Lists
# the sites and their functions for the addresses asked for. Read-only on the image; no game
# data is printed beyond addresses.
#   python -I tools/find_refs.py private/xex/default.bin private/xex/pdata_funcs.txt 820FFE80 820144BC ...
import struct, sys, bisect
img=open(sys.argv[1],'rb').read(); base=0x82000000
TEXT=(0x82020000,0x82020000+0xC2A34)
funcs=[]
for line in open(sys.argv[2]):
    p=line.split()
    try: funcs.append((int(p[0],16), int(p[1],16) if len(p)>1 else 0))
    except: pass
funcs.sort(); starts=[f[0] for f in funcs]
def func_of(pc):
    i=bisect.bisect_right(starts,pc)-1
    return funcs[i][0] if i>=0 else 0
def ins(pc): return struct.unpack('>I', img[pc-base:pc-base+4])[0]
refs={}  # target -> list of (pc, kind)
pc=TEXT[0]
while pc<TEXT[1]:
    w=ins(pc)
    if (w>>26)==15 and ((w>>16)&31)==0:   # lis rD, imm
        rd=(w>>21)&31; hi=(w&0xFFFF)<<16
        for k in range(1,12):
            q=pc+4*k
            if q>=TEXT[1]: break
            w2=ins(q); op=w2>>26; ra=(w2>>16)&31; rd2=(w2>>21)&31
            if op in (14,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49,50,51,52,53,54,55,58,62) and ra==rd:
                simm=w2&0xFFFF
                if simm&0x8000: simm-=0x10000
                t=(hi+simm)&0xFFFFFFFF
                refs.setdefault(t,[]).append((q,'addi' if op==14 else 'mem%d'%op))
                if op!=14 or rd2==rd: pass
            if op==15 and rd2==rd: break
            if rd2==rd and op in (14,) : break
            if rd2==rd and op not in (14,36,37,38,39,44,45,52,53,54,55) and op>=32: break
    pc+=4
if __name__=='__main__':
    for a in sys.argv[3:]:
        t=int(a,16)
        print('%08X:'%t, ' '.join('%08X(%s,%s)'%(pc,k,'sub_%08X'%func_of(pc)) for pc,k in refs.get(t,[])))
