"""Render the approved Combo design as a state sheet and fixed-loop media demo."""
from pathlib import Path
import math
from PIL import Image, ImageDraw, ImageFont

OUT = Path(__file__).parent
S = 3
BG, FG, TRACK, MUTED = '#17181b', '#f4f4f6', '#565961', '#b2b4bd'
FONT = '/System/Library/Fonts/STHeiti Light.ttc'
NUMBER_FONT = '/System/Library/Fonts/Supplemental/Arial.ttf'


def levels(phase):
    return [7 + 3.5*(1+math.sin(2*math.pi*(phase+offset)))
            for offset in (0, .35, .65, .15)]


def icon(center='wifi', bottom='volume', battery=82, volume=2,
         charging=False, phase=0, size=140, light=False, show_battery=True):
    k = size*S/100
    bg, fg, track = ('#eeeef1','#24252a','#a7aab3') if light else (BG,FG,TRACK)
    im = Image.new('RGB',(size*S,size*S),bg)
    d = ImageDraw.Draw(im)

    def line(points, color=fg, width=4):
        coords=[(x*k,y*k) for x,y in points]
        d.line(coords,fill=color,width=round(width*k),joint='curve')
        for x,y in coords:
            r=width*k/2
            d.ellipse((x-r,y-r,x+r,y+r),fill=color)

    def arc(cx,cy,r,start,end,color,width):
        outer=r+width/2
        d.arc(((cx-outer)*k,(cy-outer)*k,(cx+outer)*k,(cy+outer)*k),
              start,end,fill=color,width=round(width*k))
        for a in (start,end):
            x,y=cx+r*math.cos(math.radians(a)),cy+r*math.sin(math.radians(a))
            d.ellipse(((x-width/2)*k,(y-width/2)*k,
                       (x+width/2)*k,(y+width/2)*k),fill=color)

    if show_battery:
        arc(50,44,36,150,390,track,5.7)
        if battery > 0:
            arc(50,44,36,150,150+2.4*battery,'#f16c70' if battery <= 20 else fg,5.7)
    if charging and show_battery:
        d.rounded_rectangle((70*k,8*k,90*k,32*k),radius=4*k,fill=bg)
        d.polygon([(84*k,8*k),(74*k,22*k),(80*k,22*k),(77*k,32*k),
                   (88*k,17*k),(82*k,17*k)],fill=fg)
    if center == 'wifi':
        arc(50,56.624,20.624,227.19,312.81,fg,4.6)
        arc(50,57.072,12.434,229.9,310.1,fg,4.6)
        tip=[(46.082,52.318)]
        for end,control in [((53.918,52.318),(50,49.568)), ((54.241,54.705),(54.788,52.868)),
                            ((51.6,57.28),None), ((48.4,57.28),(50,58.555)),
                            ((45.759,54.705),None), ((46.082,52.318),(45.212,52.868))]:
            start=tip[-1]
            if control is None: tip.append(end)
            else:
                for i in range(1,21):
                    t=i/20
                    tip.append(tuple((1-t)**2*a+2*(1-t)*t*b+t*t*c for a,b,c in zip(start,control,end)))
        d.polygon([(px*k,py*k) for px,py in tip],fill=fg)
    elif center == 'headphones':
        arc(50,44,13,180,360,fg,4)
        for x in (35,59):
            d.rounded_rectangle((x*k,43*k,(x+6)*k,58*k),radius=3*k,fill=fg)
    elif center == 'error':
        line([(50,32),(50,47)],width=5)
        d.ellipse((47.2*k,54*k,52.8*k,59.6*k),fill=fg)
    else:
        value = str(battery) if center == 'percent' else '22'
        d.text((50*k,46*k),value,anchor='mm',fill=fg,
               font=ImageFont.truetype(NUMBER_FONT,round((26 if len(value)==3 else 31)*k)))
    if bottom == 'mute':
        d.polygon([(37*k,78*k),(42*k,78*k),(49*k,73*k),(49*k,86*k),
                   (42*k,82*k),(37*k,82*k)],fill=fg)
        line([(55,77),(62,84)],width=2.7)
        line([(62,77),(55,84)],width=2.7)
    else:
        for i,(x,y) in enumerate(((31,77),(43,82),(57,82),(69,77))):
            if bottom == 'bars':
                h=levels(phase)[i]
                d.rounded_rectangle(((x-3.4)*k,(y+3.4-h)*k,(x+3.4)*k,(y+3.4)*k),
                                    radius=3.4*k,fill=fg)
            else:
                d.ellipse(((x-3.4)*k,(y-3.4)*k,(x+3.4)*k,(y+3.4)*k),
                          fill=fg if i<volume else track)
    return im


STATES = [
    ('无线正常',{},'中央显示 Wi-Fi','底部显示音量 50%'),
    ('有线 · 默认',{'center':'percent'},'中央显示电量百分比','正常有线不显示网口'),
    ('有线 · 日期',{'center':'date'},'中央显示当天日期','设置可选，无日历边框'),
    ('有线 · 输出设备',{'center':'headphones'},'中央显示耳机或扬声器','底部仍然表示系统音量'),
    ('媒体播放',{'center':'percent','bottom':'bars'},'四点变为固定循环音柱','不跟随真实声音或节奏'),
    ('播放中调音量',{'center':'percent','volume':3},'临时显示音量 75%','约 2 秒后重判播放状态'),
    ('暂停 / 未播放',{'center':'percent'},'音柱收回音量圆点','保持当前音量档位'),
    ('系统静音',{'center':'percent','bottom':'mute'},'静音符号优先','覆盖圆点与播放动效'),
    ('低电量',{'center':'percent','battery':12},'短红弧 + 完整淡色轨道','以长度和颜色共同提示'),
    ('充电 + 播放',{'center':'percent','bottom':'bars','charging':True},'闪电移到外圈右上方','为底部音柱留出空间'),
    ('网络异常',{'center':'error'},'感叹号覆盖中央内容','电量与音量仍独立显示'),
    ('减少动态效果',{'center':'percent','bottom':'bars','phase':.3},'播放时为静态高低音柱','关闭播放动效则保留圆点'),
]


def text(draw,x,y,value,size=18,color=FG,anchor=None):
    draw.text((x*S,y*S),value,font=ImageFont.truetype(FONT,size*S),fill=color,anchor=anchor)


def sheet():
    im=Image.new('RGB',(1100*S,1260*S),BG)
    d=ImageDraw.Draw(im)
    text(d,40,28,'COMBO / 状态设计总览',29)
    text(d,1060,39,'MacBook · v0.1',16,MUTED,'ra')
    text(d,40,77,'外圈电量 · 中央网络 / 自定义 · 底部音量 / 固定播放动效',18,MUTED)
    for row in range(3):
        y=126+row*273
        d.line((40*S,y*S,1060*S,y*S),fill='#383a42',width=S)
        for col in range(4):
            title,args,l1,l2=STATES[row*4+col]
            cx=167+255*col
            text(d,cx,y+21,title,21,anchor='ma')
            im.paste(icon(**args),((cx-70)*S,(y+62)*S))
            text(d,cx,y+209,l1,15,MUTED,'ma')
            text(d,cx,y+237,l2,15,MUTED,'ma')
    d.line((40*S,953*S,1060*S,953*S),fill='#383a42',width=S)
    text(d,40,975,'菜单栏尺寸对照',19)
    text(d,1060,979,'22 pt 画布 · 图片显示时会缩放',14,MUTED,'ra')
    d.rounded_rectangle((40*S,1084*S,1060*S,1128*S),radius=8*S,fill='#eeeef1')
    for i,(_,args,_,_) in enumerate(STATES):
        x=82+i*85
        im.paste(icon(**args,size=22),((x-11)*S,1040*S))
        im.paste(icon(**args,size=22,light=True),((x-11)*S,1095*S))
    text(d,40,1160,'底部优先级：静音 → 音量调整 → 播放动效 → 音量圆点',18)
    text(d,40,1200,'动效周期约 1.2 秒；音量显示延迟约 2 秒。示意数值，不代表实时系统状态。',16,MUTED)
    return im.resize((2200,2520),Image.Resampling.LANCZOS)


def animation():
    frames=[]
    for i in range(30):
        im=Image.new('RGB',(680*S,240*S),BG)
        d=ImageDraw.Draw(im)
        text(d,28,20,'固定播放动效',23)
        text(d,28,58,'预设节奏 · 不读取音频',17,MUTED)
        for x,title,args in [(88,'未播放',{'center':'percent'}),
                             (262,'播放中',{'center':'percent','bottom':'bars','phase':i/30}),
                             (436,'系统静音',{'center':'percent','bottom':'mute'}),
                             (590,'菜单栏',{'center':'percent','bottom':'bars','phase':i/30,'size':22})]:
            size=args.get('size',100)
            if 'size' not in args: args['size']=size
            im.paste(icon(**args),((x-size//2)*S,(140-size//2)*S))
            text(d,x,207,title,16,MUTED,'ma')
        frames.append(im.resize((1020,360),Image.Resampling.LANCZOS))
    palette=frames[0].quantize(colors=128)
    frames=[f.quantize(palette=palette,dither=Image.Dither.NONE) for f in frames]
    frames[0].save(OUT/'combo-playback-demo.gif',save_all=True,append_images=frames[1:],
                   duration=40,loop=0,disposal=2,optimize=False)


if __name__ == '__main__':
    for a,b in zip(levels(0),levels(1)):
        assert abs(a-b)<1e-9, 'Animation loop must close'
    for phase in (0,.25,.5,.75):
        assert all(7<=h<=14 for h in levels(phase))
    still=icon(center='percent')
    moving=icon(center='percent',bottom='bars')
    assert still.crop((0,0,420,270)).tobytes()==moving.crop((0,0,420,270)).tobytes(), 'Audio cannot change upper regions'
    assert icon(center='percent',battery=100).size==(420,420)
    sheet().save(OUT/'combo-state-overview.png')
    animation()
    with Image.open(OUT/'combo-playback-demo.gif') as gif:
        assert gif.n_frames==30 and gif.info['loop']==0
        assert sum(gif.seek(i) or gif.info['duration'] for i in range(gif.n_frames))==1200
    print('Rendered state sheet and 1.2-second loop; drawing checks passed.')
