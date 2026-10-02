"""Freki Hub / A day, in rhythm. Deterministic 48s motion film + original score.

Requires Python 3, Pillow, NumPy and ffmpeg. All records are fictional.
UI is an editorial reconstruction, not a recording of a running Android app.
"""
from pathlib import Path
from functools import lru_cache
import argparse
import math
import subprocess
import wave
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
W, H, FPS, DURATION = 1920, 1080, 30, 48
INK = '#161917'
PAPER = '#f1f2ee'
WHITE = '#f3f2ef'
SAGE = '#b8d3a6'
MUTED = '#a8b0a7'
BLUE = '#91b7cf'
LILAC = '#a8a0ba'
GOLD = '#c6ad8a'

def clamp(v): return max(0., min(1., v))
def ease(v): return 1 - (1 - clamp(v)) ** 4
def smooth(v):
    v = clamp(v)
    return v * v * (3 - 2 * v)
def pop(v):
    v = clamp(v) - 1
    return 1 + 2.4 * v**3 + 1.4 * v**2
def lerp(a, b, v): return a + (b - a) * v

@lru_cache(None)
def font(size, kind='regular'):
    names = {'regular':'Geist-Regular.ttf', 'bold':'Geist-SemiBold.ttf', 'mono':'GeistMono-Regular.ttf'}
    return ImageFont.truetype(str(ROOT / 'assets/fonts' / names[kind]), int(size))

@lru_cache(2048)
def lettering(text,size,fill,kind):
    f=font(size,kind)
    sprite=Image.new('RGBA',(int(math.ceil(f.getlength(text)))+8,int(size*1.5)+8))
    ImageDraw.Draw(sprite).text((0,0),text,font=f,fill=fill)
    return sprite

def txt(im, text, x, y, size=28, fill=WHITE, kind='regular', anchor=None):
    sprite=lettering(text,size,fill,kind)
    if anchor:
        length=font(size,kind).getlength(text)
        if anchor[0]=='m': x-=length/2
        elif anchor[0]=='r': x-=length
        if anchor[1]=='t': y-=font(size,kind).getbbox(text)[1]
    im.paste(sprite,(int(x),int(y)),sprite)

def rr(im, box, fill, radius=28, outline=None, width=1):
    ImageDraw.Draw(im).rounded_rectangle(tuple(int(v) for v in box),radius,fill,outline,width)

def line(im, pts, fill, width=2):
    ImageDraw.Draw(im).line(pts, fill, width, joint='curve')

def dot(im, x, y, r, fill, outline=None, width=1):
    ImageDraw.Draw(im).ellipse((x-r,y-r,x+r,y+r),fill,outline,width)

def label(im, text, x, y, color=MUTED): txt(im,text,x,y,20,color,'mono')

def reveal(im, text, x, y, size, u, delay=0, color=WHITE, kind='bold'):
    p = ease((u-delay)/.85)
    if p <= 0: return
    box = Image.new('RGBA', (int(font(size,kind).getlength(text))+20, int(size*1.45)), (0,0,0,0))
    txt(box,text,0,int((1-p)*size*1.3),size,color,kind)
    im.paste(box,(int(x),int(y)),box)

def placed(im, layer, cx, cy, scale=1., angle=0., opacity=1.):
    if scale < .01 or opacity <= 0: return
    if scale != 1: layer=layer.resize((max(1,int(layer.width*scale)),max(1,int(layer.height*scale))),Image.Resampling.BICUBIC)
    if angle: layer=layer.rotate(angle,Image.Resampling.BICUBIC,expand=True)
    if opacity < 1:
        layer=layer.copy(); layer.putalpha(layer.getchannel('A').point(lambda a:int(a*opacity)))
    im.paste(layer,(int(cx-layer.width/2),int(cy-layer.height/2)),layer)

def icon(im, name, x,y,s=22,color=WHITE):
    d=ImageDraw.Draw(im); w=max(2,int(s/12))
    if name=='clock':
        dot(im,x,y,s*.43,None,color,w); line(im,[(x,y-s*.25),(x,y),(x+s*.2,y+s*.1)],color,w)
    elif name=='calendar':
        rr(im,(x-s*.4,y-s*.32,x+s*.4,y+s*.4),None,4,color,w)
        line(im,[(x-s*.4,y-s*.08),(x+s*.4,y-s*.08)],color,w)
        for v in [-.2,.2]: line(im,[(x+s*v,y-s*.45),(x+s*v,y-s*.2)],color,w)
    elif name=='settings':
        dot(im,x,y,s*.36,None,color,w); dot(im,x,y,s*.12,None,color,w)
        for n in range(8):
            a=n*math.pi/4; line(im,[(x+math.cos(a)*s*.35,y+math.sin(a)*s*.35),(x+math.cos(a)*s*.49,y+math.sin(a)*s*.49)],color,w)
    elif name=='map':
        line(im,[(x-s*.45,y+s*.35),(x-s*.45,y-s*.3),(x-s*.15,y-s*.42),(x+s*.15,y-s*.3),(x+s*.45,y-s*.42),(x+s*.45,y+s*.25),(x+s*.15,y+s*.38),(x-s*.15,y+s*.25),(x-s*.45,y+s*.35)],color,w)
        for v in [-.15,.15]: line(im,[(x+s*v,y-s*.32),(x+s*v,y+s*.27)],color,w)
    elif name=='finance':
        rr(im,(x-s*.45,y-s*.32,x+s*.45,y+s*.32),None,4,color,w); dot(im,x+s*.2,y,2,color)
    elif name=='sessions':
        for j in range(3): line(im,[(x-s*.35,y+(j-1)*s*.25),(x+s*.35,y+(j-1)*s*.25)],color,w)
    elif name=='lock':
        rr(im,(x-s*.32,y-s*.02,x+s*.32,y+s*.4),None,4,color,w)
        d.arc((x-s*.22,y-s*.42,x+s*.22,y+s*.13),180,360,fill=color,width=w)
        dot(im,x,y+s*.17,2,color)

def clock(im,x,y,r,t,color=WHITE):
    d=ImageDraw.Draw(im)
    for n in range(60):
        a=n*math.pi/30-math.pi/2; inner=r*(.85 if n%5==0 else .94)
        line(im,[(x+math.cos(a)*inner,y+math.sin(a)*inner),(x+math.cos(a)*r,y+math.sin(a)*r)],color,3 if n%5==0 else 1)
    for a,length,width,col in [(t*.025-1.2,r*.47,7,color),(t*.17-.4,r*.7,4,color),(t*math.pi/30,r*.79,2,SAGE)]:
        line(im,[(x,y),(x+math.sin(a)*length,y-math.cos(a)*length)],col,width)
    dot(im,x,y,6,color)

def flaps(im,text,x,y,size=82,u=0,light=False):
    fg=INK if light else WHITE; bg='#e1e5db' if light else '#303831'
    step=size*.73
    for j,c in enumerate(text):
        xx=x+j*step
        if c==':': txt(im,c,xx+5,y+4,size,fg,'mono'); continue
        rr(im,(xx,y,xx+step-5,y+size*1.4),bg,12)
        phase=u%1
        previous=text[:-2]+f'{(int(text[-2:])-1)%60:02}'
        if j>=6 and phase<.3 and previous[j]!=c:
            ww,hh=int(step-5),int(size*1.4); half=hh//2
            old=Image.new('RGBA',(ww,hh)); new=old.copy()
            txt(old,previous[j],6,6,size,fg,'mono'); txt(new,c,6,6,size,fg,'mono')
            im.paste(new.crop((0,0,ww,half)),(int(xx),int(y)),new.crop((0,0,ww,half)))
            bottom=old.crop((0,half,ww,hh)); im.paste(bottom,(int(xx),int(y)+half),bottom)
            p=phase/.3
            if p<.5:
                h=max(1,int(half*math.cos(p*math.pi)))
                flap=old.crop((0,0,ww,half)).resize((ww,h),Image.Resampling.BICUBIC)
                im.paste(flap,(int(xx),int(y)+half-h),flap)
            else:
                h=max(1,int((hh-half)*math.sin((p-.5)*math.pi)))
                flap=new.crop((0,half,ww,hh)).resize((ww,h),Image.Resampling.BICUBIC)
                im.paste(flap,(int(xx),int(y)+half),flap)
        else: txt(im,c,xx+6,y+6,size,fg,'mono')
        line(im,[(xx,y+size*.7),(xx+step-5,y+size*.7)],INK if not light else '#bbc2b4',2)

def shell(page,dark=True):
    im=Image.new('RGBA',(440,850),(0,0,0,0))
    rr(im,(0,0,439,849),'#090c0a',55,'#697368',2)
    rr(im,(10,10,430,840),INK if dark else PAPER,46)
    fg=WHITE if dark else INK
    txt(im,'9:41',34,30,16,fg,'mono'); rr(im,(172,24,268,47),'#070907',12)
    for k in range(4): rr(im,(365+k*6,39-k*3,369+k*6,45),fg,1)
    icon(im,'calendar',43,88,23,fg); icon(im,'settings',398,88,23,fg)
    txt(im,page+'.',30,127,40,fg,'bold')
    rr(im,(22,755,418,815),'#323932' if dark else '#dce1d7',30,'#657060',1)
    tabs=['Today','Map','Sessions','Finance']
    for j,name in enumerate(tabs):
        xx=72+j*99
        if page==name: rr(im,(xx-42,763,xx+42,806),'#f1f2ee' if dark else INK,22)
        col=INK if page==name and dark else WHITE if page==name else fg
        icon(im,name.lower() if name!='Today' else 'clock',xx,782,20,col)
        txt(im,name,xx,818,10,fg,anchor='mt')
    rr(im,(159,830,281,834),fg,2)
    return im

def phone(page,u=0,dark=True):
    im=shell(page,dark); fg=WHITE if dark else INK; sub=MUTED if dark else '#616861'; card='#252b26' if dark else '#fcfcfa'
    if page=='Today':
        txt(im,'Friday, 2 October',30,181,17,sub)
        rr(im,(24,217,416,617),card,28)
        clock(im,220,325,78,u)
        txt(im,'YOUR SESSION IS RUNNING',220,422,12,sub,'mono','mt')
        flaps(im,f'02:14:{int(u)%60:02}',67,452,48,u,not dark)
        rr(im,(44,546,396,592),fg,23); txt(im,'Clock out',220,555,19,INK if dark else WHITE,'bold','mt')
        txt(im,'Recent sessions',28,641,20,fg,'bold')
        rr(im,(24,678,416,732),card,19); txt(im,'Work  ·  Product design',42,693,15,fg); txt(im,'4h 20m',391,694,15,sub,'mono','rt')
    elif page=='Sessions':
        txt(im,'Your time, remembered.',30,181,17,sub)
        rr(im,(24,218,416,267),card,15); txt(im,'Search sessions',45,231,17,sub)
        for j,(name,time,duration) in enumerate([('Work','02 OCT · 09:00','4h 20m'),('Study','01 OCT · 18:30','1h 45m'),('Personal','30 SEP · 10:15','0h 50m'),('OJT','29 SEP · 08:00','6h 00m')]):
            yy=292+j*106; rr(im,(24,yy,416,yy+90),card,22)
            txt(im,name,44,yy+15,21,fg,'bold'); txt(im,time,44,yy+49,13,sub,'mono'); txt(im,duration,391,yy+31,18,fg,'mono','rt')
    elif page=='Calendar':
        txt(im,'October 2026',30,182,20,sub)
        rr(im,(24,226,416,278),card,22)
        for j,v in enumerate(['Year','Month','Week','Day']):
            if j==1: rr(im,(120,233,215,270),fg,17)
            txt(im,v,73+j*98,242,15,INK if j==1 and dark else fg,anchor='mt')
        days=['S','M','T','W','T','F','S']
        for j,v in enumerate(days): txt(im,v,51+j*56,307,14,sub,anchor='mt')
        for n in range(31):
            k=n+4; xx=51+(k%7)*56; yy=356+(k//7)*53
            if n==1: dot(im,xx,yy+10,22,SAGE)
            txt(im,str(n+1),xx,yy,17,INK if n==1 else fg,anchor='mt')
            if n in [1,4,8,12,15,20,26]: dot(im,xx,yy+32,3,BLUE)
        rr(im,(24,651,416,732),card,22); txt(im,'Friday, 2 October',42,665,19,fg,'bold'); txt(im,'Work session  ·  09:00',42,700,15,sub)
    elif page=='Finance':
        txt(im,'October 2026  ·  PHP',30,181,17,sub)
        rr(im,(24,219,416,402),card,28); txt(im,'SAFE TO SPEND',44,244,13,sub,'mono')
        txt(im,'₱ 12,450',44,277,47,fg,'bold'); txt(im,'After planned commitments',44,356,16,sub)
        for j,(a,b,c) in enumerate([('Income','24,000',SAGE),('Expenses','6,550',GOLD),('Savings','3,000',LILAC)]):
            xx=24+j*132; rr(im,(xx,423,xx+126,514),card,19); txt(im,a,xx+12,439,12,sub); txt(im,b,xx+12,468,18,c,'mono')
        rr(im,(24,534,416,732),card,24); txt(im,'Savings goal',44,552,20,fg,'bold')
        ImageDraw.Draw(im).arc((48,591,166,709),-90,270,fill='#414941',width=13)
        ImageDraw.Draw(im).arc((48,591,166,709),-90,-90+216*ease(u/2),fill=SAGE,width=13)
        txt(im,'60%',108,635,25,fg,'bold','mt'); txt(im,'Recurring plans',191,601,17,fg,'bold'); txt(im,'Monthly · Weekly',191,636,14,sub); txt(im,'Expected + actual',191,674,14,sub)
    elif page=='Map':
        txt(im,'Recorded places. Real context.',30,181,16,sub)
        rr(im,(24,219,416,681),card,28)
        for k in range(9):
            xx=40+k*48; line(im,[(xx,233),(xx+50,670)],'#3a443b',1)
            yy=240+k*50; line(im,[(32,yy),(408,yy-45)],'#3a443b',1)
        points=[(81,571),(157,477),(267,507),(337,351),(245,289)]
        for j in range(4):
            a,b=points[j:j+2]
            for k in range(12):
                if (j+k/12)/4<=ease(u/3): line(im,[(lerp(a[0],b[0],k/12),lerp(a[1],b[1],k/12)),(lerp(a[0],b[0],(k+.5)/12),lerp(a[1],b[1],(k+.5)/12))],BLUE,3)
        for j,(xx,yy) in enumerate(points): dot(im,xx,yy,8,[BLUE,SAGE,GOLD,BLUE,LILAC][j],INK,3)
        rr(im,(43,239,398,280),'#56604d',20); txt(im,'Day   Week   Month   Year',220,250,14,fg,anchor='mt')
        txt(im,'Illustrative recorded samples',220,651,12,sub,'regular','mt')
        txt(im,'Sessions · Finance · Locations',30,703,14,sub)
    elif page=='Settings':
        txt(im,'Make it yours.',30,181,17,sub)
        for j,(name,value) in enumerate([('Appearance','Dark'),('Currency','PHP'),('Activity logs','Off'),('Location collection','Off'),('Conditions & automation','Open'),('Backup & restore','JSON')]):
            yy=228+j*78; rr(im,(24,yy,416,yy+65),card,20); txt(im,name,43,yy+22,16,fg); txt(im,value,393,yy+22,16,sub,'regular','rt')
    return im

@lru_cache(None)
def background(light=False):
    base=np.zeros((H,W,3),dtype=np.uint8)
    yy,xx=np.mgrid[0:H,0:W]
    glow=np.exp(-((xx-1400)**2/(1000**2)+(yy-410)**2/(800**2)))
    rgb=(241,242,238) if light else (22,25,23)
    for k,c in enumerate(rgb): base[:,:,k]=np.clip(c+glow*(3 if light else [10,15,7][k]),0,255)
    im=Image.fromarray(base)
    # Fine editorial grid, visible only in negative space.
    d=ImageDraw.Draw(im); col='#e4e7de' if light else '#252c25'
    for x in range(80,W,160):
        for y in range(90,H,160):
            d.line((x-3,y,x+3,y),fill=col); d.line((x,y-3,x,y+3),fill=col)
    return im

def chrome(im,t,section,light=False):
    fg=INK if light else WHITE; sub='#65705f' if light else MUTED
    label(im,'F / H',76,49,fg); label(im,'FREKI HUB     /     PRODUCT FILM',170,49,sub)
    txt(im,section.upper(),1842,49,18,sub,'mono','rt')
    line(im,[(76,1001),(1844,1001)],'#cfd5ca' if light else '#3a4437',1)
    line(im,[(76,1001),(76+1768*t/DURATION,1001)],'#637b50' if light else SAGE,3)
    label(im,'A DAY, IN RHYTHM.',76,1026,sub)
    txt(im,f'{int(t):02} / 48',1844,1026,18,sub,'mono','rt')

def orbit(im,cx,cy,r,u,color=SAGE):
    d=ImageDraw.Draw(im)
    for j in range(3):
        ry=r*(.25+j*.12)
        d.ellipse((cx-r,cy-ry,cx+r,cy+ry),outline='#414f3b',width=2)
        a=u*.55+j*2.1; dot(im,cx+math.cos(a)*r,cy+math.sin(a)*ry,7,color)

def frame(t):
    cuts=[0,4,10,16,22,28,34,40,48]
    scene=next((i for i in range(8) if cuts[i]<=t<cuts[i+1]),7)
    u=t-cuts[scene]; light=scene in [2,6]
    im=background(light).copy(); fg=INK if light else WHITE; sub='#616861' if light else MUTED
    if scene==0:
        # Orbital mark becomes a massive typographic opening.
        p=ease(u/1.4); orbit(im,1420,540,lerp(40,300,p),u)
        label(im,'TIME. MONEY. CONTEXT.',80,260,SAGE)
        reveal(im,'A day,',74,325,154,u,.15)
        reveal(im,'in rhythm.',74,493,154,u,.48)
        reveal(im,'Freki Hub App',80,725,39,u,1.05,color=MUTED,kind='regular')
        for j,word in enumerate(['TRACK','PLAN','CONNECT']):
            reveal(im,word,1280,740+j*42,23,u,1.5+j*.15,color=SAGE,kind='mono')
        # Flash of the six surfaces on the final beats.
        if u>3:
            names=['TODAY','SESSIONS','FINANCE','CALENDAR']
            v=(u-3)*4; rr(im,(1075,445,1825,602),SAGE,15)
            txt(im,names[min(3,int(v))],1450,453,83,INK,'bold','mt')
    elif scene==1:
        label(im,'01  /  TODAY',82,214,SAGE)
        reveal(im,'Make every',76,277,108,u,.12)
        reveal(im,'hour count.',76,397,108,u,.28)
        reveal(im,'Clock in. Stay present. Clock out.',82,572,30,u,.55,color=MUTED,kind='regular')
        p=pop(u/1.4); placed(im,phone('Today',u),1390+25*math.sin(u*.7),540+35*(1-p),.93*p,-5+2*math.sin(u*.4))
        flaps(im,f'02:14:{int(u+23):02}',83,705,71,u)
        label(im,'SPLIT-FLAP TIME  /  SESSION NOTES',83,850)
        # Clock arc and precision tick accents around the device.
        ImageDraw.Draw(im).arc((1090,201,1700,827),205,205+210*ease(u/3),fill='#516346',width=2)
    elif scene==2:
        label(im,'02  /  SESSIONS + CALENDAR',82,208,'#637b50')
        reveal(im,'Your days.',76,275,115,u,.1,color=INK)
        reveal(im,'Connected.',76,402,115,u,.3,color=INK)
        reveal(im,'Search your sessions.',82,594,29,u,.6,color=sub,kind='regular')
        reveal(im,'See the bigger picture.',82,640,29,u,.8,color=sub,kind='regular')
        placed(im,phone('Sessions',u,False),1180-20*math.sin(u),550,.86*ease(u/1.1),8)
        placed(im,phone('Calendar',u,False),1550+18*math.sin(u*.5),565,.91*ease((u-.35)/1.15),-6)
        for j,v in enumerate(['YEAR','MONTH','WEEK','DAY']):
            p=ease((u-1.2-j*.12)/.65); x=82+j*154
            rr(im,(x,780+(1-p)*40,x+140,836+(1-p)*40),INK if j==1 else '#dfe5d7',22)
            txt(im,v,x+70,795+(1-p)*40,18,WHITE if j==1 else INK,'mono','mt')
    elif scene==3:
        label(im,'03  /  FINANCE',82,204,SAGE)
        reveal(im,'Clarity in',76,263,111,u,.1)
        reveal(im,'every peso.',76,386,111,u,.3)
        reveal(im,'Income. Expenses. Savings.',82,564,29,u,.6,color=MUTED,kind='regular')
        placed(im,phone('Finance',u),1460,540,.94*pop(u/1.4),-4+math.sin(u))
        # Bars emerge in rhythm, with animated counts and accurate demo math.
        for j,(name,value,color) in enumerate([('INCOME',24000,SAGE),('EXPENSES',6550,GOLD),('SAVINGS',3000,LILAC)]):
            p=ease((u-.8-j*.2)/1.7); yy=674+j*79
            label(im,name,84,yy,color); txt(im,f'₱ {int(value*p):,}',892,yy-7,29,WHITE,'mono','rt')
            rr(im,(84,yy+34,900,yy+43),'#343b31',4)
            if p>0: rr(im,(84,yy+34,84+816*(value/24000)*p,yy+43),color,4)
        # A separate floating editorial card brings the crucial metric forward.
        if u>2:
            card=Image.new('RGBA',(340,118)); rr(card,(0,0,339,117),SAGE,25)
            label(card,'SAFE TO SPEND',24,20,INK); txt(card,'₱ 12,450',24,46,39,INK,'bold')
            placed(im,card,1155,733+10*math.sin(u),ease((u-2)/.7),3)
    elif scene==4:
        label(im,'04  /  MAP',82,207,BLUE)
        reveal(im,'A little',76,270,119,u,.1)
        reveal(im,'more context.',76,401,119,u,.28)
        reveal(im,'Explore your recorded places.',82,580,29,u,.6,color=MUTED,kind='regular')
        label(im,'RECORDED SAMPLES  /  OPT-IN LOGGING',82,855)
        placed(im,phone('Map',u),1470,540,.94*ease(u/1.2),4-2*math.sin(u*.5))
        points=[(100,762),(281,704),(457,775),(658,660),(887,710)]
        p=ease((u-.8)/3)
        for j in range(4):
            a,b=points[j:j+2]
            for k in range(20):
                if (j+k/20)/4<p: line(im,[(lerp(a[0],b[0],k/20),lerp(a[1],b[1],k/20)),(lerp(a[0],b[0],(k+.55)/20),lerp(a[1],b[1],(k+.55)/20))],BLUE,3)
        for j,(x,y) in enumerate(points):
            if p>j/5:
                r=14+8*math.sin(u*2-j)**2; dot(im,x,y,r,None,'#3c5341',2); dot(im,x,y,6,[BLUE,SAGE,GOLD,LILAC,BLUE][j])
        # The abstract trace deliberately has no geography, roads or invented GPS labels.
        txt(im,'Chronological traces of saved coordinates',82,900,21,MUTED)
    elif scene==5:
        label(im,'05  /  CONDITIONS + AUTOMATION',82,204,SAGE)
        reveal(im,'Your rules.',76,264,111,u,.1)
        reveal(im,'Your rhythm.',76,388,111,u,.3)
        reveal(im,'Local reminders. Typed conditions.',82,569,29,u,.6,color=MUTED,kind='regular')
        # Exact valid example from RULE_SYNTAX.md; reveal each line as compiled source.
        p=ease(u/1.1); x=1050+150*(1-p)
        rr(im,(x,210,x+780,817),'#252c25',30,'#596450',2)
        label(im,'CONDITIONS & AUTOMATION',x+34,243)
        dot(im,x+711,254,7,SAGE)
        source=[('target == notifications {',SAGE),('  schedule("morning") {',WHITE),('    at("08:00");',GOLD),('    repeat.daily();',WHITE),('    repeat.forever();',WHITE),('    notification.show(',BLUE),('      "Session reminder",',GOLD),('      "Time to clock in");',GOLD),('  }',WHITE),('}',SAGE)]
        for j,(v,c) in enumerate(source):
            if u>.6+j*.17: txt(im,v,x+35,306+j*37,23,c,'mono')
        rr(im,(x+34,721,x+230,772),SAGE,22); txt(im,'RUN',x+132,733,22,INK,'mono','mt')
        txt(im,'Validated locally',x+277,734,21,MUTED)
        for j,v in enumerate(['VISUAL BUILDER','CODE COMPLETION','RUN / STOP']): reveal(im,v,84,713+j*52,22,u,1+j*.2,color=SAGE,kind='mono')
    elif scene==6:
        label(im,'06  /  SETTINGS + LOCAL STORAGE',82,204,'#637b50')
        reveal(im,'On your phone.',76,267,112,u,.1,color=INK)
        reveal(im,'In your hands.',76,391,112,u,.3,color=INK)
        reveal(im,'No account needed.',82,575,31,u,.65,color=sub,kind='regular')
        reveal(im,'Local records. JSON backup.',82,624,31,u,.85,color=sub,kind='regular')
        placed(im,phone('Settings',u,False),1450,540,.93*ease(u/1.25),-5)
        # Enclosing rings emphasise device-owned records, with no cloud icon.
        for j in range(3):
            r=70+j*28+6*math.sin(u+j); ImageDraw.Draw(im).ellipse((224-r,806-r*.38,224+r,806+r*.38),outline='#bdcbb3',width=2)
        icon(im,'lock',224,795,61,INK)
        for j,v in enumerate(['APPEARANCE','SOUND','EXPORT / RESTORE']): reveal(im,v,376,742+j*43,20,u,1.2+j*.15,color='#637b50',kind='mono')
    else:
        # Device fan assembles, then compresses into the brand lock-up.
        if u<3.8:
            reveal(im,'One hub.',77,207,120,u,.1)
            reveal(im,'Your whole day.',77,337,120,u,.25)
            pages=['Map','Sessions','Today','Finance','Calendar']
            for j,page in enumerate(pages):
                p=pop((u-j*.12)/1.25)
                cx=980+(j-2)*305; cy=710+abs(j-2)*20
                placed(im,phone(page,40+u,page!='Calendar'),cx,cy+200*(1-p),.54*p,(2-j)*6)
        else:
            v=u-3.8
            orbit(im,1440,538,260,v,SAGE)
            label(im,'ANDROID  /  LOCAL FIRST',82,244,SAGE)
            reveal(im,'Freki',76,305,165,v,.05)
            reveal(im,'Hub App.',76,484,165,v,.2)
            reveal(im,'A day, in rhythm.',82,735,41,v,.5,color=MUTED,kind='regular')
            for j,word in enumerate(['TIME','MONEY','CONTEXT']): reveal(im,word,1290,755+j*39,22,v,.65+j*.15,color=SAGE,kind='mono')
        if u>7.3:
            overlay=Image.new('RGB',(W,H),INK); im=Image.blend(im,overlay,smooth((u-7.3)/.7)*.8)
    # Second camera setups: match cuts into the feature's visual mechanism.
    # Every six-second chapter gets an intimate two-second macro shot.
    if scene in range(1,7) and u>=4:
        v=u-4; macro=background(light).copy()
        if scene==1:
            label(macro,'TODAY  /  THE SPLIT-FLAP DETAIL',82,204,SAGE)
            reveal(macro,'Stay in the flow.',76,260,107,v,0)
            flaps(macro,f'02:14:{int(u+23):02}',82,468,285,v)
            label(macro,'WORK  /  PRODUCT DESIGN',82,918)
            txt(macro,'Every second, accounted for.',1840,918,25,MUTED,'regular','rt')
        elif scene==2:
            reveal(macro,'Days become a story.',76,207,100,v,0,color=INK)
            label(macro,'CALENDAR  /  YOUR SAVED RECORDS',82,355,'#637b50')
            for j,(day,name,dur,col) in enumerate([('29','OJT','6h 00m',GOLD),('30','Personal','0h 50m',BLUE),('01','Study','1h 45m',LILAC),('02','Work','4h 20m',SAGE),('03','Your next day','',PAPER)]):
                p=pop((v-j*.07)/.7); x=82+j*350-40*v; yy=466+(1-p)*200
                rr(macro,(x,yy,x+322,yy+360),'#fcfcfa',30,'#cfd6c9',1)
                txt(macro,'OCT' if j>1 else 'SEP',x+28,yy+26,19,'#65705f','mono')
                txt(macro,day,x+22,yy+66,139,INK,'bold')
                rr(macro,(x+24,yy+240,x+298,yy+316),col,19)
                txt(macro,name,x+41,yy+253,25,INK,'bold'); txt(macro,dur,x+41,yy+288,16,INK,'mono')
        elif scene==3:
            label(macro,'FINANCE  /  AFTER PLANNED COMMITMENTS',82,218,SAGE)
            reveal(macro,'Know your room',76,287,96,v,0)
            reveal(macro,'to move.',76,394,96,v,.12)
            reveal(macro,'₱ 12,450',76,593,127,v,.2,color=SAGE)
            label(macro,'SAFE TO SPEND  /  PHP',82,782)
            d=ImageDraw.Draw(macro); cx,cy=1450,535; r=273
            d.arc((cx-r,cy-r,cx+r,cy+r),-90,270,fill='#35412e',width=52)
            d.arc((cx-r,cy-r,cx+r,cy+r),-90,-90+216*ease(v/1.4),fill=SAGE,width=52)
            txt(macro,'60%',cx,cy-67,100,WHITE,'bold','mt'); txt(macro,'SAVINGS GOAL',cx,cy+59,21,MUTED,'mono','mt')
        elif scene==4:
            label(macro,'MAP  /  A TRACE OF RECORDED SAMPLES',82,213,BLUE)
            reveal(macro,'Connect the moments.',76,277,102,v,0)
            pts=[(125,756),(485,614),(839,775),(1220,551),(1760,651)]
            for j in range(4):
                a,b=pts[j:j+2]
                for k in range(40):
                    z=k/40
                    if (j+z)/4<ease(v/1.4): line(macro,[(lerp(a[0],b[0],z),lerp(a[1],b[1],z)),(lerp(a[0],b[0],z+.013),lerp(a[1],b[1],z+.013))],BLUE,4)
            for j,(x,y) in enumerate(pts):
                col=[BLUE,SAGE,GOLD,LILAC,BLUE][j]
                r=28+24*((v+j*.17)%1)
                dot(macro,x,y,r,None,'#40553c',2); dot(macro,x,y,13,col)
                txt(macro,['Session','Finance','Location','Other','Session'][j],x,y+70,23,col,'regular','mt')
            label(macro,'ILLUSTRATIVE TRACE  /  NOT A ROAD ROUTE',82,922)
        elif scene==5:
            label(macro,'AUTOMATION  /  LOCAL REMINDERS',82,213,SAGE)
            reveal(macro,'Right on your rhythm.',76,271,102,v,0)
            reveal(macro,'08:00',76,428,244,v,.1,color=SAGE,kind='mono')
            notification=Image.new('RGBA',(850,165)); rr(notification,(0,0,849,164),'#e9eee3',35)
            icon(notification,'clock',62,79,45,INK)
            txt(notification,'Session reminder',113,35,33,INK,'bold')
            txt(notification,'Time to clock in',113,92,27,'#616861')
            placed(macro,notification,1380,682+80*(1-pop((v-.2)/.8)),.94,-3+math.sin(v))
            label(macro,'DAILY  /  SELECTED WEEKDAYS  /  ONE-TIME',82,860)
        elif scene==6:
            label(macro,'FREKI HUB  /  RECORDS LIVE WITH YOU',82,222,'#637b50')
            reveal(macro,'LOCAL.',51,313,375,v,0,color=INK)
            reveal(macro,'Your hours. Your money. Your phone.',82,797,44,v,.2,color='#616861',kind='regular')
            icon(macro,'lock',1640,825,98,INK)
        im=Image.blend(im,macro,ease(v/.32))
    names=['Overture','Today','Sessions / Calendar','Finance','Map','Automation','Settings','Freki Hub']
    chrome(im,t,names[scene],light)
    # Graphic shutter: two offset sheets sweep across each chapter boundary.
    if scene and u<.38:
        p=ease(u/.38); edge=int(W*p)
        ImageDraw.Draw(im).rectangle((edge,0,W,H),fill=PAPER if scene%2==0 else INK)
        ImageDraw.Draw(im).rectangle((max(0,edge-26),0,edge,H),fill=SAGE)
    return im

def soundtrack(path):
    sr=48000; total=int(DURATION*sr); track=np.zeros((total,2),dtype=np.float64)
    rng=np.random.default_rng(143)
    def add(start,signal,volume=1,pan=0):
        ix=int(start*sr); count=min(len(signal),total-ix)
        if ix<0 or count<=0:return
        track[ix:ix+count,0]+=signal[:count]*volume*math.sqrt((1-pan)/2)
        track[ix:ix+count,1]+=signal[:count]*volume*math.sqrt((1+pan)/2)
    def tone(f,dur):
        q=np.arange(int(dur*sr))/sr
        env=np.minimum(q/.015,1)*np.exp(-q*2.5)
        return (np.sin(2*np.pi*f*q)+.22*np.sin(2*np.pi*f*2*q)+.08*np.sin(2*np.pi*f*3*q))*env
    # Original 120 BPM score: D minor 9 / Bb major 7 / F major 9 / C add 9.
    chords=[[50,57,60,64,69],[46,53,57,62,65],[41,53,57,60,67],[48,55,60,62,67]]
    for bar in range(24):
        start=bar*2; chord=chords[(bar//2)%4]
        q=np.arange(2*sr)/sr
        env=np.minimum(q/.25,1)*np.minimum((2-q)/.35,1)
        pad=sum(np.sin(2*np.pi*440*2**((n-69)/12)*q+.05*np.sin(q*2)) for n in chord)/len(chord)
        add(start,pad*env,.16,math.sin(bar)*.25)
        for b in range(8):
            moment=start+b*.25
            if 34<=moment<36: continue
            note=chord[[0,2,4,1,3,4,2,3][b]]+12
            add(moment,tone(440*2**((note-69)/12),.8),.13 if moment>=4 else .07,(-1 if b%2 else 1)*.55)
        for b in range(4):
            moment=start+b*.5
            if moment<4 or 34<=moment<36 or moment>46: continue
            q=np.arange(int(.3*sr))/sr
            kick=np.sin(2*np.pi*(46*q+105*.025*(1-np.exp(-q/.025))))*np.exp(-q*17)
            add(moment,kick,.55)
            bass=440*2**((chord[0]-12-69)/12)
            add(moment,tone(bass,.44),.22)
            if b%2:
                q=np.arange(int(.16*sr))/sr; noise=rng.normal(0,.5,len(q))
                add(moment,noise*np.exp(-q*35)+np.sin(2*np.pi*185*q)*np.exp(-q*25),.16)
        if start>=8 and start<46:
            for b in range(8):
                q=np.arange(int(.06*sr))/sr; noise=rng.normal(0,.4,len(q)); noise=np.diff(noise,prepend=0)
                add(start+b*.25,noise*np.exp(-q*85),.06,(-1 if b%2 else 1)*.4)
    # Designed transition swells and soft split-flap transients.
    for cut in [4,10,16,22,28,34,40,43.8]:
        q=np.arange(int(.6*sr))/sr; noise=rng.normal(0,.1,len(q))
        env=np.sin(np.pi*q/.6)**2
        add(cut-.45,(noise+np.sin(2*np.pi*(270*q+1300*q*q))*.08)*env,.45)
        add(cut,tone(880,.35),.1,.3)
    q=np.arange(total)/sr
    track*=np.minimum(q/1.5,1)[:,None]*np.clip((DURATION-q)/1.3,0,1)[:,None]
    track=np.tanh(track*1.25); track*=.89/max(.89,np.max(np.abs(track)))
    with wave.open(str(path),'wb') as f:
        f.setnchannels(2); f.setsampwidth(2); f.setframerate(sr); f.writeframes((track*32767).astype('<i2').tobytes())

def main():
    ap=argparse.ArgumentParser(); ap.add_argument('--output',type=Path,required=True); ap.add_argument('--preview',action='store_true')
    args=ap.parse_args(); args.output.mkdir(parents=True,exist_ok=True)
    times=[2.3,7.3,13.3,19.3,25.3,31.3,37.3,45.6]
    thumbs=[]
    for j,t in enumerate(times):
        img=frame(t); img.save(args.output/f'scene-{j+1:02}.jpg',quality=92)
        thumb=img.resize((640,360),Image.Resampling.LANCZOS); thumbs.append(thumb)
    contact=Image.new('RGB',(1280,1440),INK)
    for j,img in enumerate(thumbs): contact.paste(img,((j%2)*640,(j//2)*360))
    contact.save(args.output/'storyboard.jpg',quality=95)
    frame(45.6).save(args.output/'poster.jpg',quality=96)
    if args.preview:return
    soundtrack(args.output/'original-score.wav')
    target=args.output/'Freki-Hub-A-Day-in-Rhythm.mp4'
    cmd=['ffmpeg','-y','-hide_banner','-loglevel','error','-f','rawvideo','-pix_fmt','rgb24','-s',f'{W}x{H}','-r',str(FPS),'-i','pipe:0','-i',str(args.output/'original-score.wav'),'-c:v','libx264','-preset','fast','-crf','18','-pix_fmt','yuv420p','-c:a','aac','-b:a','256k','-movflags','+faststart','-shortest',str(target)]
    process=subprocess.Popen(cmd,stdin=subprocess.PIPE)
    try:
        for i in range(DURATION*FPS):
            process.stdin.write(frame(i/FPS).tobytes())
            if i%(FPS*2)==0: print(f'Rendered {i/FPS:.0f}s / {DURATION}s',flush=True)
    finally:process.stdin.close()
    if process.wait()!=0:raise RuntimeError('ffmpeg render failed')
    print(f'Exported {target}',flush=True)

if __name__=='__main__':main()
