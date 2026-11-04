#!/usr/bin/env python3
"""Independent Python ChaCha20 reference, anchored to local Linux RFC7539 A.2 #1."""
import pathlib,re,struct,sys,hashlib
out=pathlib.Path(sys.argv[1]);out.mkdir(parents=True,exist_ok=True)
source=pathlib.Path(sys.argv[2]);text=source.read_text()
case=text.split('static const struct cipher_testvec chacha20_tv_template[] = {',1)[1].split('.len',1)[0]
cipher=case.split('.ctext',1)[1]
published=bytes(int(x,16) for x in re.findall(r'\\x([0-9a-fA-F]{2})',cipher))
assert len(published)==64

def block(state):
    x=list(state)
    def q(a,b,c,d):
        for u,v,w,n in [(a,b,d,16),(c,d,b,12),(a,b,d,8),(c,d,b,7)]:
            x[u]=(x[u]+x[v])&0xffffffff
            t=x[w]^x[u];x[w]=((t<<n)|(t>>(32-n)))&0xffffffff
    for _ in range(10):
        for ids in [(0,4,8,12),(1,5,9,13),(2,6,10,14),(3,7,11,15),(0,5,10,15),(1,6,11,12),(2,7,8,13),(3,4,9,14)]:q(*ids)
    return [(a+b)&0xffffffff for a,b in zip(x,state)]
constant=[0x61707865,0x3320646e,0x79622d32,0x6b206574]
states=[constant+[0]*12]
seed=0x521c0de
for n in range(31):
    words=[]
    for j in range(12):
        seed=(1664525*seed+1013904223)&0xffffffff;words.append(seed)
    states.append(constant+words)
expected=[block(s) for s in states]
assert struct.pack('<16I',*expected[0])==published,'Reference does not match upstream published vector'
with (out/'crypto_vectors.h').open('w') as f:
    f.write('// Generated independent reference data; no upstream algorithm code copied.\n')
    for name,data in [('inputs',states),('expected',expected)]:
        f.write('static const uint32_t '+name+'[32][16]={\n')
        for row in data:f.write('{'+','.join(f'0x{x:08x}u' for x in row)+'},\n')
        f.write('};\n')
lines=['CRYPTO_VECTOR0='+struct.pack('<16I',*expected[0]).hex(),'CRYPTO_VECTOR31='+struct.pack('<16I',*expected[-1]).hex(),'CRYPTO_PASS blocks=32 bytes_compared=2048']
(out/'expected_uart.txt').write_text('\n'.join(lines)+'\n')
(out/'reference_provenance.txt').write_text(f'RFC7539 A.2 vector #1 from {source}\nSource SHA256 {hashlib.sha256(source.read_bytes()).hexdigest()}\nIndependent Python reference matches all 64 published bytes.\n')
print('PASS Python reference: published RFC7539 vector matches all64 bytes; generated32 complete block answers')
