"""Desktop design preview: preserve the existing center and bottom positions."""
from PIL import Image, ImageDraw
from render_design import icon, text, OUT, S, BG, FG, MUTED


def desktop_icon(center='airpods', bottom='volume', size=150, light=False, notebook=False):
    special = center in ('airpods','speaker')
    im=icon(center='headphones' if special else center, bottom=bottom,
            size=size,light=light,show_battery=notebook)
    if special:
        k=size*S/100
        d=ImageDraw.Draw(im)
        bg,fg=('#eeeef1','#24252a') if light else (BG,FG)
        d.rectangle((29*k,27*k,71*k,63*k),fill=bg)
        if center == 'airpods':
            source=Image.open(OUT/'airpods-pro-symbol.png').convert('RGBA')
            source=source.resize((round(38*k),round(38*k)),Image.Resampling.LANCZOS)
            tinted=Image.new('RGBA',source.size,fg)
            tinted.putalpha(source.getchannel('A'))
            im.paste(tinted,(round(31*k),round(26*k)),tinted)
        else:
            d.polygon([(35*k,40*k),(43*k,40*k),(59*k,30*k),
                       (59*k,59*k),(43*k,49*k),(35*k,49*k)],fill=fg)
    return im


def render():
    im=Image.new('RGB',(1000*S,1000*S),BG)
    d=ImageDraw.Draw(im)
    text(d,40,28,'COMBO / 台式 Mac',29)
    text(d,960,39,'无电池形态 · 预览',16,MUTED,'ra')
    text(d,40,77,'去掉电量外圈，保留中央内容与底部声音状态。',18,MUTED)
    d.line((40*S,121*S,960*S,121*S),fill='#383a42',width=S)
    for cx,title,notebook in [(280,'MacBook',True),(720,'台式 Mac',False)]:
        text(d,cx,148,title,22,anchor='ma')
        im.paste(desktop_icon(size=190,notebook=notebook),((cx-95)*S,190*S))
        text(d,cx,390,'电量外圈 + AirPods Pro + 音量' if notebook else 'AirPods Pro + 音量',18,MUTED,'ma')
    text(d,500,256,'→',30,MUTED,'ma')
    text(d,500,430,'相同图标尺寸、相同内容位置，仅移除无含义的外圈',16,MUTED,'ma')
    d.line((40*S,471*S,960*S,471*S),fill='#383a42',width=S)
    states=[('无线网络','wifi','volume','中央显示 Wi-Fi'),
            ('有线 · 扬声器','speaker','volume','默认显示输出设备'),
            ('有线 · 耳机','airpods','volume','识别后用 Apple 图标'),
            ('媒体播放','airpods','bars','底部固定循环音柱'),
            ('网络异常','error','volume','中央显示感叹号')]
    for i,(title,center,bottom,note) in enumerate(states):
        cx=132+184*i
        text(d,cx,501,title,19,anchor='ma')
        im.paste(desktop_icon(center,bottom),((cx-75)*S,539*S))
        text(d,cx,712,note,15,MUTED,'ma')
    d.line((40*S,759*S,960*S,759*S),fill='#383a42',width=S)
    text(d,40,783,'菜单栏尺寸对照',19)
    text(d,960,787,'22 pt 画布 · 图片随查看比例缩放',14,MUTED,'ra')
    d.rounded_rectangle((40*S,883*S,960*S,925*S),radius=8*S,fill='#eeeef1')
    for i,(_,center,bottom,_) in enumerate(states):
        cx=132+184*i
        im.paste(desktop_icon(center,bottom,size=22),((cx-11)*S,838*S))
        im.paste(desktop_icon(center,bottom,size=22,light=True),((cx-11)*S,893*S))
    text(d,40,954,'无电池时中央默认显示输出设备，也可在设置中改为日期。',17,MUTED)
    return im.resize((2000,2000),Image.Resampling.LANCZOS)


if __name__ == '__main__':
    notebook=desktop_icon(notebook=True)
    desktop=desktop_icon()
    assert notebook.tobytes()!=desktop.tobytes()
    for box in [(135,122,315,288),(110,306,340,410)]:
        assert notebook.crop(box).tobytes()==desktop.crop(box).tobytes(), 'Keep center and audio unchanged'
    for light in (False,True):
        for center in ('airpods','speaker','wifi','error'):
            assert desktop_icon(center,light=light,size=22).size==(66,66)
    render().save(OUT/'combo-desktop-preview.png')
    print('Desktop preview rendered; shared-layout checks passed.')
