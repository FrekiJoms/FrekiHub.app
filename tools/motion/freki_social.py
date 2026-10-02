"""9:16 Freki Hub social film with an original dance score and action-synced SFX.

Reuses the documented editorial phone artwork; does not crop the landscape film.
Run: python tools/motion/freki_social.py --output ABSOLUTE_EXTERNAL_DIRECTORY
"""
from pathlib import Path
from functools import lru_cache
import argparse
import json
import math
import subprocess
import wave
import numpy as np
from PIL import Image, ImageDraw
import freki_showreel as art

W,H,FPS,DURATION=1080,1920,30,48
INK,PAPER,WHITE,SAGE,MUTED,BLUE,GOLD,LILAC=art.INK,art.PAPER,art.WHITE,art.SAGE,art.MUTED,art.BLUE,art.GOLD,art.LILAC
cuts=[0,4,10,16,22,28,34,40,48]
CUES={}

def cue(key,at,kind='ping'):
    CUES[key]={'time':at,'kind':kind}

for scene,start in enumerate(cuts[:-1]):
    cue(f'{scene}.cut',start,'impact' if scene else 'rise')
    for j,delay in enumerate([.12,.3]): cue(f'{scene}.title{j}',start+delay,'type')
    if scene!=7:cue(f'{scene}.sub',start+.7)
    if 1<=scene<=6:
        cue(f'{scene}.hero',start+.45,'card')
        cue(f'{scene}.pill',start+1.5)
        cue(f'{scene}.macro',start+4,'whoosh')
        for j in range(3 if scene==6 else 2):cue(f'{scene}.macrotitle{j}',start+4.12+j*.12,'type')
        cue(f'{scene}.detail',start+4.4,'card')
cue('0.orbit',.8,'rise')
cue('0.brand0',1.8,'type');cue('0.brand1',2,'type')
cue('1.macroline0',8.5,'type');cue('1.macroline1',8.65,'type')
cue('2.secondphone',10.7,'card')
for j in range(5): cue(f'2.date{j}',14.5+j*.11)
cue('3.goal',16.45,'rise')
for j in range(5): cue(f'4.dot{j}',26.45+j*.23)
for j in range(10): cue(f'5.code{j}',28.9+j*.14,'key')
cue('5.notify',32.7,'notification')
for j in range(5): cue(f'7.phone{j}',40.6+j*.14,'card')
cue('7.brand',43.8,'whoosh')
for j in range(3): cue(f'7.brand{j}',44+j*.2,'type')
cue('7.tagline',44.4,'ping')
for sec in range(5,10): cue(f'1.tick{sec}',sec,'flip')
for sec in range(41,44): cue(f'7.tick{sec}',sec,'flip')

def progress(key,t,dur=.75):
    return art.ease((t-CUES[key]['time'])/dur)

def text(im,v,x,y,size,color=WHITE,kind='regular',anchor=None):
    art.txt(im,v,x,y,size,color,kind,anchor)

def headline(im,rows,t,scene,color=WHITE):
    for j,v in enumerate(rows):
        art.reveal(im,v,78,268+j*103,88,t-CUES[f'{scene}.title{j}']['time'],color=color)

def subtitle(im,v,t,scene,color=MUTED):
    art.reveal(im,v,82,268+3*103+18,26,t-CUES[f'{scene}.sub']['time'],color=color,kind='regular')

@lru_cache(None)
def background(light=False):
    yy,xx=np.mgrid[0:H,0:W]
    glow=np.exp(-((xx-580)**2/750**2+(yy-1040)**2/1250**2))
    rgb=(241,242,238) if light else (18,23,20)
    arr=np.zeros((H,W,3),np.uint8)
    for k,c in enumerate(rgb): arr[:,:,k]=np.clip(c+glow*(3 if light else [12,20,10][k]),0,255)
    return Image.fromarray(arr)

def atmosphere(im,t,light):
    color='#d5decc' if light else '#34482f'
    d=ImageDraw.Draw(im)
    # Slow orbital ribbons move throughout every shot; a soft pulse follows the beat.
    beat=(t*2)%1; r=380+16*math.exp(-beat*5)
    cx=540+45*math.sin(t*.21); cy=1140+100*math.cos(t*.17)
    for j in range(3):
        ry=r*(.8+j*.19)
        d.arc((cx-r-j*65,cy-ry,cx+r+j*65,cy+ry),25+t*9+j*65,180+t*9+j*65,fill=color,width=2)
    for j in range(18):
        x=80+(j*137)%860; y=220+((j*179+t*15)%1360)
        art.dot(im,x,y,1.5,color)

def footer(im,t,scene,light):
    fg=INK if light else WHITE; sub='#637b50' if light else MUTED
    text(im,'F / H',82,177,23,fg,'mono')
    text(im,['A DAY, IN RHYTHM','TODAY','SESSIONS + CALENDAR','FINANCE','MAP','AUTOMATION','SETTINGS','FREKI HUB'][scene],82,1558,18,sub,'mono')
    art.line(im,[(82,1610),(900,1610)],'#cbd4c4' if light else '#35432f',2)
    art.line(im,[(82,1610),(82+818*t/DURATION,1610)],'#637b50' if light else SAGE,4)
    text(im,'FREKI HUB APP',900,177,18,sub,'mono','rt')

def pill(im,v,t,scene,light=False):
    p=progress(f'{scene}.pill',t)
    if not p:return
    card=Image.new('RGBA',(690,74)); art.rr(card,(0,0,689,73),SAGE,32)
    text(card,v,345,24,22,INK,'mono','mt')
    art.placed(im,card,508,1508+60*(1-p),p,-1+math.sin(t*.6))

def frame(t):
    scene=next((j for j in range(8) if cuts[j]<=t<cuts[j+1]),7)
    u=t-cuts[scene]; light=scene in [2,6]; fg=INK if light else WHITE; sub='#616861' if light else MUTED
    im=background(light).copy(); atmosphere(im,t,light)
    if scene==0:
        headline(im,['A day,','in rhythm.'],t,scene)
        subtitle(im,'Time. Money. Context.',t,scene)
        p=progress('0.orbit',t,1.2)
        art.orbit(im,525,1000,360*p,t,SAGE)
        for j,row in enumerate(['Freki','Hub App.']):art.reveal(im,row,78,1210+j*120,105,t-CUES[f'0.brand{j}']['time'],color=WHITE)
    elif 1<=scene<=6:
        rows={1:['Make every','hour count.'],2:['Your days.','Connected.'],3:['Clarity in','every peso.'],4:['A little more','context.'],5:['Your rules.','Your rhythm.'],6:['On your phone.','In your hands.']}[scene]
        headline(im,rows,t,scene,fg)
        subtitle(im,{1:'Clock in. Stay present. Clock out.',2:'Search sessions. See the bigger picture.',3:'Income. Expenses. Savings.',4:'Explore your recorded places.',5:'Local reminders. Typed conditions.',6:'Local records. No account needed.'}[scene],t,scene,sub)
        p=art.pop((t-CUES[f'{scene}.hero']['time'])/1.05)
        if scene==2:
            art.placed(im,art.phone('Sessions',u,False),328,1080+130*(1-p),.87*p,6+math.sin(u))
            q=art.pop((t-CUES['2.secondphone']['time'])/1.05)
            art.placed(im,art.phone('Calendar',u,False),690,1130+130*(1-q),.89*q,-5+math.sin(u*.7))
        elif scene==5 and p>0:
            art.rr(im,(80,717+130*(1-p),914,1365+130*(1-p)),'#252c25',32,'#59704a',2)
            text(im,'CONDITIONS & AUTOMATION',115,745,19,MUTED,'mono')
            source=[('target == notifications {',SAGE),('  schedule("morning") {',WHITE),('    at("08:00");',GOLD),('    repeat.daily();',WHITE),('    repeat.forever();',WHITE),('    notification.show(',BLUE),('      "Session reminder",',GOLD),('      "Time to clock in");',GOLD),('  }',WHITE),('}',SAGE)]
            for j,(v,col) in enumerate(source):
                if progress(f'5.code{j}',t):text(im,v,115,825+j*43,25,col,'mono')
            art.rr(im,(115,1280,302,1331),SAGE,25);text(im,'RUN',208,1295,22,INK,'mono','mt')
        elif scene!=5:
            page={1:'Today',3:'Finance',4:'Map',6:'Settings'}[scene]
            art.placed(im,art.phone(page,u,not light),515+17*math.sin(u),1045+130*(1-p),.96*p,-4+3*math.sin(u*.6))
        pill(im,{1:'SPLIT-FLAP TIME / SESSION NOTES',2:'YEAR / MONTH / WEEK / DAY',3:'PLAN AHEAD. SPEND WITH CLARITY.',4:'RECORDED SAMPLES / OPT-IN LOGGING',5:'VISUAL BUILDER / CODE COMPLETION',6:'APPEARANCE / SOUND / JSON BACKUP'}[scene],t,scene,light)
        if u>=4:
            macro=background(light).copy(); atmosphere(macro,t,light); v=u-4
            heading={1:['Stay in','the flow.'],2:['Days become','a story.'],3:['Know your room','to move.'],4:['Connect the','moments.'],5:['Right on','your rhythm.'],6:['Your hours.','Your money.','Your phone.']}[scene]
            for j,row in enumerate(heading):
                art.reveal(macro,row,78,280+j*104,85,t-CUES[f'{scene}.macrotitle{j}']['time'],color=fg)
            detail=progress(f'{scene}.detail',t)
            if scene==1:
                art.flaps(macro,'02:14:'+f'{int(u+23):02}',83,768,137,u)
                text(macro,'WORK',82,1110,33,SAGE,'mono')
                art.reveal(macro,'Every second,',78,1210,65,v,.5,color=WHITE)
                art.reveal(macro,'accounted for.',78,1290,65,v,.65,color=WHITE)
                art.clock(macro,765,1135,94,u)
            elif scene==2:
                for j,(day,name,col) in enumerate([('29','OJT',GOLD),('30','Personal',BLUE),('01','Study',LILAC),('02','Work',SAGE),('03','Your next day',PAPER)]):
                    q=progress(f'2.date{j}',t,.6); x=82+(j%2)*421; y=680+(j//2)*255+60*(1-q)
                    if q:
                        art.rr(macro,(x,y,x+390,y+230),'#fcfcfa',29,'#cfd6c9')
                        text(macro,day,x+25,y+20,96,INK,'bold');art.rr(macro,(x+22,y+148,x+367,y+209),col,19);text(macro,name,x+42,y+163,24,INK,'bold')
            elif scene==3:
                art.reveal(macro,'₱ 12,450',78,598,104,v,.4,color=SAGE)
                text(macro,'SAFE TO SPEND / PHP',82,745,24,MUTED,'mono')
                r=240;cx,cy=506,1110;d=ImageDraw.Draw(macro)
                d.arc((cx-r,cy-r,cx+r,cy+r),-90,270,fill='#35412e',width=42)
                d.arc((cx-r,cy-r,cx+r,cy+r),-90,-90+216*detail,fill=SAGE,width=42)
                text(macro,'60%',cx,cy-68,108,WHITE,'bold','mt');text(macro,'SAVINGS GOAL',cx,cy+65,21,MUTED,'mono','mt')
            elif scene==4:
                pts=[(160,735),(702,817),(319,997),(787,1150),(400,1350)]
                for j in range(4):
                    a,b=pts[j:j+2]
                    for k in range(26):
                        if (j+k/26)/4<detail:
                            z=k/26;art.line(macro,[(art.lerp(a[0],b[0],z),art.lerp(a[1],b[1],z)),(art.lerp(a[0],b[0],z+.021),art.lerp(a[1],b[1],z+.021))],BLUE,4)
                for j,(x,y) in enumerate(pts):
                    q=progress(f'4.dot{j}',t,.35)
                    if q:
                        col=[BLUE,SAGE,GOLD,LILAC,BLUE][j];art.dot(macro,x,y,17*q,col);art.dot(macro,x,y,30+16*((v+j*.15)%1),None,'#4f6546',2)
                        text(macro,['Session','Finance','Location','Other','Session'][j],x,y+48,24,col,'regular','mt')
                text(macro,'Illustrative recorded samples',82,1475,21,MUTED)
            elif scene==5:
                art.flaps(macro,'08:00:00',83,718,137,.5)
                q=progress('5.notify',t,.7); card=Image.new('RGBA',(822,193));art.rr(card,(0,0,821,192),PAPER,35)
                art.icon(card,'clock',62,89,48,INK);text(card,'Session reminder',115,48,34,INK,'bold');text(card,'Time to clock in',115,109,28,'#616861')
                art.placed(macro,card,493,1110+90*(1-q),q,-2+math.sin(v))
                text(macro,'DAILY / WEEKDAYS / ONE-TIME',82,1390,24,SAGE,'mono')
            else:
                art.reveal(macro,'LOCAL.',60,905,232,v,.4,color=INK)
                art.icon(macro,'lock',796,1295,94,INK)
                text(macro,'Records live with you.',82,1390,34,'#616861')
            im=Image.blend(im,macro,progress(f'{scene}.macro',t,.3))
    else:
        if u<3.8:
            headline(im,['One hub.','Your whole day.'],t,scene)
            pages=['Map','Sessions','Today','Finance','Calendar']
            for j,page in enumerate(pages):
                q=art.pop((t-CUES[f'7.phone{j}']['time'])/.85)
                x=280+(j%3)*250;y=850+(j//3)*415
                if j>=3:x=325+(j-3)*300
                art.placed(im,art.phone(page,u,page!='Calendar'),x,y+100*(1-q),.47*q,(2-j)*3)
        else:
            v=t-43.8
            for j,row in enumerate(['Freki','Hub App.']): art.reveal(im,row,78,390+j*135,114,t-CUES[f'7.brand{j}']['time'],color=WHITE)
            art.reveal(im,'A day, in rhythm.',82,739,48,v,.6,color=MUTED,kind='regular')
            art.orbit(im,523,1100,350,v,SAGE)
            text(im,'TIME  /  MONEY  /  CONTEXT',82,1430,24,SAGE,'mono')
    footer(im,t,scene,light)
    if scene and u<.3:
        p=art.ease(u/.3);edge=int(H*p);d=ImageDraw.Draw(im);d.rectangle((0,edge,W,H),fill=PAPER if light else INK);d.rectangle((0,max(0,edge-18),W,edge),fill=SAGE)
    if t>47.5: im=Image.blend(im,Image.new('RGB',(W,H),INK),art.smooth((t-47.5)/.5)*.75)
    return im

def soundtrack(output):
    """Original dance score; separate music/SFX stems and a phone-friendly mix."""
    sr=48000;total=DURATION*sr;music=np.zeros((total,2));sfx=np.zeros((total,2));rng=np.random.default_rng(20261002)
    def add(track,start,sig,vol=1,pan=0):
        ix=int(start*sr);end=min(total,ix+len(sig))
        if ix<0 or end<=ix:return
        track[ix:end,0]+=sig[:end-ix]*vol*math.sqrt((1-pan)/2);track[ix:end,1]+=sig[:end-ix]*vol*math.sqrt((1+pan)/2)
    def q(d):return np.arange(int(d*sr))/sr
    def pluck(note,d=.5):
        t=q(d);f=440*2**((note-69)/12);env=np.minimum(t/.004,1)*np.exp(-t*8)
        return (np.sin(2*np.pi*f*t)+.28*np.sin(4*np.pi*f*t)+.1*np.sin(6*np.pi*f*t))*env
    chords=[[50,57,60,65,69],[46,53,57,62,65],[53,57,60,65,67],[48,55,60,64,67]]
    for bar in range(24):
        start=bar*2;chord=chords[(bar//2)%4];tt=q(2)
        pump=.25+.75*(1-np.exp(-((tt% .5)*13)))
        env=np.minimum(tt/.06,1)*np.minimum((2-tt)/.2,1)
        for side in [-1,1]:
            pad=sum(np.sin(2*np.pi*440*2**((n-69)/12)*tt*(1+side*.0015))+.16*np.sin(2*np.pi*440*2**((n-57)/12)*tt) for n in chord)/5
            add(music,start,pad*env*pump,.19,side*.8)
        for b in range(16):
            moment=start+b*.125
            if 34<=moment<35 or moment>=47.5:continue
            note=chord[[0,2,4,2,1,3,4,3][b%8]]+12
            add(music,moment,pluck(note),.12 if b%2==0 else .055,math.sin(b*1.8)*.55)
            # Stereo delay on the melodic stabs.
            add(music,moment+.1875,pluck(note),.025,-math.sin(b*1.8)*.55)
        for b in range(4):
            moment=start+b*.5
            if 34<=moment<35 or moment>=47.5:continue
            tt=q(.38);kick=np.sin(2*np.pi*(49*tt+95*.027*(1-np.exp(-tt/.027))))*np.exp(-tt*15)
            click=rng.normal(0,.12,len(tt))*np.exp(-tt*170)
            add(music,moment,kick+click,.78)
            tt=q(.38);f=440*2**((chord[0]-12-69)/12)
            bass=(np.sin(2*np.pi*f*tt)+.3*np.sin(4*np.pi*f*tt))*np.minimum(tt/.006,1)*np.exp(-tt*6)
            add(music,moment+.12,bass,.43)
            if b%2:
                tt=q(.2);noise=rng.normal(0,.4,len(tt));high=np.diff(noise,prepend=0)
                clap=(high*np.exp(-tt*26)+.24*np.sin(2*np.pi*190*tt)*np.exp(-tt*20))
                add(music,moment,clap,.25)
            tt=q(.09);hat=np.diff(rng.normal(0,.35,len(tt)),prepend=0)*np.exp(-tt*64)
            add(music,moment+.25,hat,.105,(-1 if b%2 else 1)*.4)
            add(music,moment+.375,hat,.035,.4)
        # Rhythmic chord stabs add weight to the groove.
        for offset in [.75,1.75]:
            sig=sum(pluck(n+12,.35) for n in chord)/5
            add(music,start+offset,sig,.19)
    # One transient per scheduled entrance/change, with pitch variation and stereo placement.
    for index,(name,event) in enumerate(sorted(CUES.items(),key=lambda kv:kv[1]['time'])):
        when=event['time'];kind=event['kind'];pan=math.sin(index*1.7)*.25
        if kind in ['ping','card','notification','type']:
            tt=q(.42 if kind!='notification' else .65)
            f={'ping':1320,'card':990,'notification':880,'type':1568}[kind]*2**((index%5)/12)
            sig=(np.sin(2*np.pi*f*tt)+.25*np.sin(2*np.pi*f*2.01*tt))*np.minimum(tt/.002,1)*np.exp(-tt*(15 if kind!='notification' else 7))
            add(sfx,when,sig,.16 if kind=='type' else .26,pan)
            if kind=='notification':add(sfx,when+.09,sig,.2,-pan)
        if kind in ['card','whoosh','rise','impact']:
            tt=q(.25 if kind=='card' else .38);noise=rng.normal(0,.18,len(tt));env=np.sin(np.pi*tt/(tt[-1]+1/sr))**2
            add(sfx,when,noise*env*np.exp(-tt*4),.34 if kind=='whoosh' else .15,pan)
        if kind=='impact':
            tt=q(.24);add(sfx,when,np.sin(2*np.pi*(62*tt+25*.025*(1-np.exp(-tt/.025))))*np.exp(-tt*22),.4)
        if kind in ['flip','key']:
            tt=q(.055);noise=rng.normal(0,.24,len(tt));sig=(noise+.25*np.sin(2*np.pi*650*tt))*np.exp(-tt*95)
            add(sfx,when,sig,.33 if kind=='flip' else .22,pan)
    time=np.arange(total)/sr;fade=np.minimum(time/.12,1)*np.clip((48-time)/.5,0,1)
    # Briefly duck the music at UI events to keep the accents distinct on phone speakers.
    duck=np.ones(total)
    for event in CUES.values():
        ix=int(event['time']*sr);n=min(int(.16*sr),total-ix)
        if n>0:duck[ix:ix+n]=np.minimum(duck[ix:ix+n],1-.2*np.exp(-np.arange(n)/(sr*.05)))
    music*=duck[:,None]*fade[:,None];sfx*=fade[:,None]
    mix=np.tanh((music+sfx)*1.1);gain=.86/max(.86,np.max(np.abs(mix)));mix*=gain
    for name,track in [('upbeat-music.wav',music),('action-sfx.wav',sfx),('social-final-mix.wav',mix)]:
        if name!='social-final-mix.wav':track=np.clip(track,-.98,.98)
        with wave.open(str(output/name),'wb') as f:
            f.setnchannels(2);f.setsampwidth(2);f.setframerate(sr);f.writeframes((track*32767).astype('<i2').tobytes())
    (output/'sound-cues.json').write_text(json.dumps(CUES,indent=2),encoding='utf-8')

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--output',type=Path,required=True);ap.add_argument('--preview',action='store_true');args=ap.parse_args();args.output.mkdir(parents=True,exist_ok=True)
    times=[2.5,7.2,9.3,13.2,15.3,19.2,21.3,25.2,27.3,31.2,33.3,37.2,39.3,42.5,45.6]
    sheet=Image.new('RGB',(1080,1920),INK)
    for j,t in enumerate(times):
        im=frame(t);im.save(args.output/f'shot-{j+1:02}.jpg',quality=94)
        sheet.paste(im.resize((216,384),Image.Resampling.LANCZOS),((j%5)*216,(j//5)*384))
    # Contact sheet is exactly 5 columns × 3 rows, without unused rows.
    sheet.crop((0,0,1080,1152)).save(args.output/'vertical-storyboard.jpg',quality=95)
    frame(45.6).save(args.output/'vertical-poster.jpg',quality=96)
    if args.preview:return
    soundtrack(args.output)
    master=args.output/'social-mastered-mix.wav'
    subprocess.run(['ffmpeg','-y','-hide_banner','-loglevel','error','-i',str(args.output/'social-final-mix.wav'),'-af','loudnorm=I=-14:TP=-1.5:LRA=7','-ar','48000',str(master)],check=True)
    target=args.output/'Freki-Hub-Social-9x16.mp4'
    cmd=['ffmpeg','-y','-hide_banner','-loglevel','error','-f','rawvideo','-pix_fmt','rgb24','-s',f'{W}x{H}','-r',str(FPS),'-i','pipe:0','-i',str(master),'-c:v','libx264','-preset','fast','-crf','18','-pix_fmt','yuv420p','-c:a','aac','-b:a','256k','-movflags','+faststart','-shortest',str(target)]
    process=subprocess.Popen(cmd,stdin=subprocess.PIPE)
    try:
        for j in range(FPS*DURATION):
            process.stdin.write(frame(j/FPS).tobytes())
            if j%(FPS*2)==0:print(f'Vertical render {j/FPS:.0f}s / 48s',flush=True)
    finally:process.stdin.close()
    if process.wait()!=0:raise RuntimeError('ffmpeg social render failed')
    print(f'Exported {target}',flush=True)

if __name__=='__main__':main()
