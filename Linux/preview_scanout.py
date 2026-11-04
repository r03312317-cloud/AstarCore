"""Lossless preview of captured RTL pixels; never edits raw evidence."""
from pathlib import Path
from array import array
import hashlib,io,json,sys,time
from PIL import Image
R=Path(__file__).resolve().parent
def main():
    src=R/'reports/compact_boot/run_01/captures';out=src.parent/'previews';out.mkdir(exist_ok=True)
    converted=[]
    for p in sorted(src.glob('*.json')):
        if time.time()-p.stat().st_mtime<1:continue
        m=json.loads(p.read_text());raw=p.with_suffix('.rgb565').read_bytes();w,h=m['width'],m['height']
        assert len(raw)==w*h*2,(p,len(raw),w,h)
        pixels=array('H');pixels.frombytes(raw)
        if sys.byteorder!='little':pixels.byteswap()
        fnv=0x811c9dc5;rgb=bytearray()
        for v in pixels:
            fnv=((fnv^v)*16777619)&0xffffffff
            r=(v>>11)&31;g=(v>>5)&63;b=v&31
            rgb.extend(((r<<3)|(r>>2),(g<<2)|(g>>4),(b<<3)|(b>>2)))
        assert fnv==int(m['fnv1a_pixel16'],16),(p,hex(fnv))
        header,bits=p.with_suffix('.ppm').read_bytes().rsplit(b'\n255\n',1)
        assert bits==rgb,'PPM payload differs from raw RGB565: '+str(p)
        target=out/(p.stem+'.png')
        if not target.exists():Image.frombytes('RGB',(w,h),bytes(rgb)).save(target)
        im=Image.open(target);assert im.size==(w,h) and im.tobytes()==rgb
        converted.append({'source':str(p.relative_to(R)),'preview':str(target.relative_to(R)),
                          'raw_sha256':hashlib.sha256(raw).hexdigest(),'png_sha256':hashlib.sha256(target.read_bytes()).hexdigest(),
                          'fnv1a_pixel16_verified':True,'rgb565_and_ppm_payload_match':True,
                          'original_ppm_header':header.decode('ascii'),'width':w,'height':h,
                          'board_capture':False})
    (out/'conversion.json').write_text(json.dumps({'files':converted},indent=2)+'\n',encoding='utf-8')
    print('Verified and previewed',len(converted),'actual RTL frames.')
if __name__=='__main__':main()
