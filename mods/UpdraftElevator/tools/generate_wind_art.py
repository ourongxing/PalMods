"""Deterministic source artwork for the wind deck and native construction icons."""
from pathlib import Path
import json, math
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[3] / 'tools'))
import palmods  # Adds the shared optional Python dependency directory.
import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'assets'
OUT.mkdir(exist_ok=True)
variants = json.loads((ROOT / 'data/variants.json').read_text(encoding='utf-8'))
FONT = 'C:/Windows/Fonts/bahnschrift.ttf'

def font(size):
    return ImageFont.truetype(FONT, size)

def deck(v):
    n = 1024
    y, x = np.mgrid[:n, :n]
    u, w = (x - n/2) / (n/2), (y - n/2) / (n/2)
    r = np.sqrt(u*u + w*w)
    # Brushed metal, etched concentric machining, no random noise or baked light.
    grain = 1.6*np.sin(y*1.3) + 0.7*np.cos(x*.31)
    metal = 29 + 8*np.clip(1-r, 0, 1) + grain + 1.4*np.sin(r*340)
    rgba = np.zeros((n,n,4), dtype=np.uint8)
    for i, gain in enumerate([.76, .92, 1.1]):
        rgba[:,:,i] = np.clip(metal*gain, 0, 255)
    art = Image.fromarray(rgba)
    d = ImageDraw.Draw(art)
    c = tuple(v['Accent'])
    dark = (9, 17, 24, 0)
    def ring(radius, width, color):
        rr = radius*n/2
        d.ellipse((n/2-rr,n/2-rr,n/2+rr,n/2+rr),outline=color,width=width)
    ring(.975, 14, (65, 79, 88, 0))
    ring(.935, 9, (*c, 220))
    ring(.882, 4, (79, 103, 117, 0))
    ring(.53, 3, (74, 96, 111, 0))
    # Twelve structural fasteners, radial seams, and three curved airflow guides.
    for k in range(12):
        a = math.radians(k*30)
        px, py = n/2+.83*n/2*math.cos(a), n/2+.83*n/2*math.sin(a)
        d.ellipse((px-7,py-7,px+7,py+7),fill=dark,outline=(93,113,123,0),width=2)
        if k % 3 == 0:
            p1 = (n/2+.58*n/2*math.cos(a),n/2+.58*n/2*math.sin(a))
            p2 = (n/2+.78*n/2*math.cos(a),n/2+.78*n/2*math.sin(a))
            d.line((p1,p2), fill=(12,23,31,0), width=5)
    for k in range(3):
        rr = (0.32 + .075*k)*n/2
        box = (n/2-rr,n/2-rr,n/2+rr,n/2+rr)
        d.arc(box, start=30+k*120, end=125+k*120, fill=(*c,190),width=10)
    d.text((n/2,n*.72), 'WIND  /  %02d M' % (v['RadiusCm']*2/100),
           font=font(28), fill=(146,168,180,0),anchor='mm')
    for k in range(variants.index(v)+1):
        px = n/2 + (k-variants.index(v)/2)*22
        d.rounded_rectangle((px-5,n*.23,px+5,n*.255),radius=3,fill=(*c,210))
    art.save(OUT / ('T_WindDeck'+v['Suffix']+'.png'))

def icon(v):
    # Render at 4x then downsample for clean edges at native 64 px wheel sizes.
    s=4
    im=Image.new('RGBA',(256*s,256*s))
    d=ImageDraw.Draw(im)
    c=tuple(v['Accent'])
    def box(b): return tuple(int(a*s) for a in b)
    radius=[65,78,91][variants.index(v)]
    cx, cy, ry=128,176,radius*.35
    d.ellipse(box((cx-radius,cy-ry+12,cx+radius,cy+ry+12)),fill=(8,16,24,255))
    d.rectangle(box((cx-radius,cy,cx+radius,cy+12)),fill=(15,27,38,255))
    d.ellipse(box((cx-radius,cy-ry,cx+radius,cy+ry)),fill=(31,48,62,255),outline=(*c,255),width=3*s)
    d.ellipse(box((cx-radius*.78,cy-ry*.78,cx+radius*.78,cy+ry*.78)),outline=(76,110,130,255),width=s)
    for k in range(3):
        xx = 88+k*40
        top = 66+(k%2)*-18
        d.line([(xx*s,151*s),(xx*s,top*s)],fill=(*c,255),width=7*s)
        d.line([((xx-14)*s,(top+14)*s),(xx*s,top*s),((xx+14)*s,(top+14)*s)],fill=(*c,255),width=7*s)
    d.rounded_rectangle(box((185,20,233,64)),radius=12*s,fill=(15,29,41,255),outline=(*c,255),width=2*s)
    d.text((209*s,42*s),v['Badge'],font=font(26*s),anchor='mm',fill=(227,244,251,255))
    im.resize((256,256),Image.Resampling.LANCZOS).save(OUT/('T_WindIcon'+v['Suffix']+'.png'))

for v in variants:
    deck(v); icon(v)
sheet=Image.new('RGB',(1200,690),(12,21,31))
d=ImageDraw.Draw(sheet)
d.text((50,28),'WIND LIFT  /  3 SIZES',font=font(30),fill=(218,236,245))
d.text((50,70),'Construction icons + emissive deck artwork',font=font(17),fill=(130,153,170))
for i,v in enumerate(variants):
    x=50+i*390
    ico=Image.open(OUT/('T_WindIcon'+v['Suffix']+'.png'))
    sheet.paste(ico,(x+40,106),ico)
    deck_im=Image.open(OUT/('T_WindDeck'+v['Suffix']+'.png')).convert('RGB').resize((260,260),Image.Resampling.LANCZOS)
    sheet.paste(deck_im,(x+40,355))
    d.text((x+40,631),f"{v['Badge']}  /  {v['RadiusCm']*2//100} m",font=font(22),fill=tuple(v['Accent']))
sheet.save(OUT/'wind-art-review.png')
print('Generated 3 deck textures, 3 transparent UI icons and review sheet:',OUT)
