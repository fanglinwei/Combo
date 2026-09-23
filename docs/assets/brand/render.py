from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

OUT = Path(__file__).parent
IRIS, INK, LILAC = '#7561C9', '#24252A', '#B9A5F5'
S = 2
im = Image.new('RGB', (1600*S, 1120*S), '#F5F3F8')
d = ImageDraw.Draw(im)
def box(x,y,w,h,c,r=24):
    d.rounded_rectangle((x*S,y*S,(x+w)*S,(y+h)*S),r*S,fill=c)
def text(x,y,t,size=20,c=INK,bold=False):
    font=ImageFont.truetype('/System/Library/Fonts/Supplemental/Arial'+(' Bold' if bold else '')+'.ttf',size*S)
    d.text((x*S,y*S),t,font=font,fill=c)

# Original paths from the supplied SVG; only the four dot positions change.
DOTS = [(35,76),(45,80),(55,80),(65,76)]
def mark(draw,x,y,size,color,scale=1):
    from math import cos,sin,radians
    k=size/100*scale; x*=scale; y*=scale
    def stroke(points,width=7):
        pts=[(x+px*k,y+py*k) for px,py in points]
        for px,py in pts:
            r=width*k/2; draw.ellipse((px-r,py-r,px+r,py+r),fill=color)
    stroke([(50+34*cos(radians(a)),48-34*sin(radians(a))) for a in range(210,-31,-1)])
    def quad(p0,p1,p2):
        return [((1-t)**2*p0[0]+2*(1-t)*t*p1[0]+t*t*p2[0],
                 (1-t)**2*p0[1]+2*(1-t)*t*p1[1]+t*t*p2[1]) for t in [i/100 for i in range(101)]]
    stroke(quad((38,47),(50,36),(62,47)))
    stroke(quad((44,53),(50,48),(56,53)))
    for px,py in DOTS:
        r=3.5*k; px=x+px*k; py=y+py*k
        draw.ellipse((px-r,py-r,px+r,py+r),fill=color)

def svg(color,bg=None):
    background=f'<rect width="100" height="100" rx="22" fill="{bg}"/>' if bg else ''
    dots=''.join(f'<circle cx="{x}" cy="{y}" r="3.5"/>' for x,y in DOTS)
    return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" role="img" aria-label="Combo logo">{background}<g fill="none" stroke="{color}" stroke-width="7" stroke-linecap="round" stroke-linejoin="round"><path d="M20.6 65 A34 34 0 1 1 79.4 65"/><path d="M38 47 Q50 36 62 47"/><path d="M44 53 Q50 48 56 53"/></g><g fill="{color}">{dots}</g></svg>'

for name,color,bg in [('combo-logo',IRIS,None),('combo-monochrome',INK,None),('combo-reversed','#FFFFFF',None),('combo-app-icon','#FFFFFF',IRIS)]:
    (OUT/f'{name}.svg').write_text(svg(color,bg))
    icon=Image.new('RGBA',(2048,2048),(0,0,0,0)); idraw=ImageDraw.Draw(icon)
    if bg: idraw.rounded_rectangle((0,0,2047,2047),450,fill=bg)
    mark(idraw,0,0,2048,color)
    icon.resize((1024,1024),Image.Resampling.LANCZOS).save(OUT/f'{name}.png')

text(64,42,'COMBO / VISUAL IDENTITY',18,IRIS,True)
text(64,80,'One place. All in view.',46,INK,True)
text(64,143,'A compact identity for a quieter menu bar.',22,'#736B80')
box(64,205,715,435,'#FFFFFF')
box(115,278,256,256,IRIS,56); mark(d,115,278,256,'#FFFFFF',S)
text(411,322,'Combo',68,INK,True)
text(415,414,'Connect. Combine.',23,'#736B80')
text(110,587,'FOUR DOTS. ONE GENTLE ARC.',16,'#736B80',True)
box(805,205,731,435,'#FFFFFF')
text(845,240,'Iris',30,INK,True)
text(845,288,'A clear accent, with room to breathe.',20,'#736B80')
for x,c,label in [(845,IRIS,'#7561C9'),(1065,'#6650B4','#6650B4'),(1285,LILAC,'#B9A5F5')]:
    box(x,343,190,132,c,16); text(x,493,label,23,INK,True)
for x,t in [(845,'Brand / icon'),(1065,'Light UI / action'),(1285,'Dark UI / accent')]:text(x,531,t,17,'#736B80')
text(845,589,'NEUTRALS   #F5F3F8   /   #24252A',16,'#736B80',True)
for x,bg,fg,accent,muted in [(64,'#FFFFFF',INK,'#6650B4','#736B80'),(815,'#26222F','#F7F4FA',LILAC,'#BDB3CC')]:
    box(x,670,721,280,bg)
    mark(d,x+27,691,54,accent,S); text(x+89,699,'Combo',27,fg,True)
    text(x+39,763,'Everything, at a glance.',25,fg,True)
    text(x+39,808,'Battery 82%     Wi-Fi connected     Audio ready',18,muted)
    box(x+39,857,205,52,accent,12)
    text(x+64,872,'Open settings',18,'#FFFFFF' if x==64 else '#312345',True)
    text(x+533,885,'LIGHT' if x==64 else 'DARK',14,muted,True)
text(64,994,'SMALL-SIZE CHECK',15,'#736B80',True)
for x,size in [(265,16),(322,22),(389,32),(470,48)]:
    mark(d,x,984,size,INK,S); text(x,1047,str(size)+' px',13,'#736B80')
text(815,992,'The same silhouette, in one color.',22,INK,True)
text(815,1034,'Static brand mark. Live status icons keep their own behavior.',17,'#736B80')
im.resize((1600,1120),Image.Resampling.LANCZOS).save(OUT/'combo-brand-preview.png')

def luminance(h):
    v=[int(h[i:i+2],16)/255 for i in (1,3,5)]
    v=[n/12.92 if n<=.04045 else ((n+.055)/1.055)**2.4 for n in v]
    return sum(a*b for a,b in zip(v,[.2126,.7152,.0722]))
def contrast(a,b):
    l=sorted([luminance(a),luminance(b)])
    return (l[1]+.05)/(l[0]+.05)
for a,b in [('#6650B4','#FFFFFF'),(LILAC,'#26222F'),('#312345',LILAC)]:
    ratio=contrast(a,b); assert ratio>=4.5,(a,b,ratio)
    print(f'{a} on {b}: {ratio:.2f}:1')
