"""Native Python FFmpeg engine; no PowerShell dependency."""
import json, math, os, re, subprocess, tempfile, threading
from pathlib import Path
ROOT = Path(__file__).resolve().parent.parent
if getattr(__import__('sys'), 'frozen', False): ROOT = Path(__import__('sys')._MEIPASS)
FREQ = [80,250,800,2500,6000,12000]
DEFAULT = dict(Version=3,Genre='Suno Optimized',Loudness=-14,Ceiling=-1,Format=0,Repair=False,DeEss=15,Mud=1,Harsh=1,Glue=0,Excite=0,Bass=0,Air=0,Width=1,MonoBass=True,MidPresence=0,SideAir=0,Match=50,HP=25,NoiseNR=False,Leveler=False,FadeIn=False,FadeOut=False,EqEnabled=True,GlueEnabled=True,GlueThreshold=-20,GlueRatio=1.4,GlueMix=100,WidthEnabled=True,MSEnabled=True,SideCut=120,MidMud=0,SatEnabled=False,SatDrive=20,SatType=0,Dither=True,**{f'Eq{i}':0 for i in range(6)})
RANGES=dict(Loudness=(-20,-8),Ceiling=(-3,-.3),Format=(0,1),DeEss=(0,100),Mud=(0,6),Harsh=(0,6),Glue=(0,100),Excite=(0,100),Bass=(-6,6),Air=(-6,6),Width=(.5,1.5),MidPresence=(-4,4),SideAir=(-4,4),Match=(0,100),HP=(20,120),GlueThreshold=(-40,-6),GlueRatio=(1,4),GlueMix=(0,100),SideCut=(40,250),MidMud=(-4,4),SatDrive=(0,100),SatType=(0,2),**{f'Eq{i}':(-6,6) for i in range(6)})
CATALOG=json.loads((ROOT/'GenrePresets.json').read_text(encoding='utf-8-sig'))
def validate(candidate):
    s=DEFAULT.copy()
    for k,v in candidate.items():
        if k not in s: continue
        if k in RANGES:
            lo,hi=RANGES[k]
            if isinstance(v,bool) or not isinstance(v,(int,float)) or not math.isfinite(v) or not lo<=v<=hi: raise ValueError(f'Invalid setting: {k}')
            if k in ('Format','SatType') and int(v)!=v: raise ValueError(f'Invalid setting: {k}')
        elif isinstance(s[k],bool) and not isinstance(v,bool): raise ValueError(f'Invalid flag: {k}')
        s[k]=v
    return s
def genre(index):
    p=CATALOG[index]; s=DEFAULT.copy()
    bases={1:dict(DeEss=25,Mud=1.5,Harsh=1.5,MidPresence=.5,Glue=15),2:dict(Loudness=-12,Bass=1,Mud=1.5,DeEss=20,Glue=20),3:dict(Loudness=-10,Width=1.1,Glue=25,DeEss=10),4:dict(Loudness=-12,Harsh=2,Mud=1.5,Glue=20,Width=1.05),5:dict(Loudness=-16,DeEss=10,Mud=.5,Harsh=.5,MonoBass=False),6:dict(Loudness=-16,Width=1.1,DeEss=5,Harsh=.5,MonoBass=False),7:dict(DeEss=0,Mud=0,Harsh=0,MonoBass=False)}
    s.update(bases.get(p['Base'],{})); s.update(p['Set']); s['Genre']=p['Name']; return validate(s)
def chain(s,gains=None,duration=0):
    gains=gains or [0]*6; f=['aformat=sample_fmts=fltp:channel_layouts=stereo']
    if s['Repair']: f+=['adeclip=w=55:o=75:a=8:t=10']
    f += [f"highpass=f={s['HP']}"]
    if s['NoiseNR']: f+=['afftdn=nr=6:nf=-50:tn=1']
    if s['Leveler']: f+=['dynaudnorm=f=500:g=15:p=0.8:m=2:s=5']
    for k,hz,w in [('Mud',280,.8),('Harsh',3500,1.1)]:
        if s[k]>0: f += [f'equalizer=f={hz}:t=q:w={w}:g={-s[k]}']
    if s['DeEss']>0: f += [f"deesser=i={s['DeEss']/100}:m=0.35:f=0.5"]
    if s['EqEnabled']:
        f += [f"equalizer=f={hz}:t=q:w=0.8:g={max(-9,min(9,s[f'Eq{i}']+gains[i]))}" for i,hz in enumerate(FREQ)]
        f += [f"bass=f=120:g={s['Bass']}", f"treble=f=6500:g={s['Air']}"]
    if s['GlueEnabled'] and s['Glue']>0: f += [f"acompressor=threshold={10**(s['GlueThreshold']/20)}:ratio={1+(s['GlueRatio']-1)*s['Glue']/100}:mix={s['GlueMix']/100}:attack=25:release=180:makeup=1:knee=2.8:link=maximum:detection=rms"]
    if s['SatEnabled'] and s['SatDrive']>0:
        d=1+s['SatDrive']/50; t=['tanh','atan','cubic'][int(s['SatType'])]; f += [f'volume={d}',f'asoftclip=type={t}:threshold=0.8:oversample=4:output={1/d}']
    if s['Excite']>0: f += [f"aexciter=amount={s['Excite']/100}:drive=2:blend=0:freq=6500:ceil=16000"]
    f+=['stereotools=mode=lr>ms']
    if s['MonoBass']: f += [f"highpass=f={s['SideCut']}:p=2:c=FR"]
    if s['MSEnabled']: f += [f"equalizer=f=2500:t=q:w=0.9:c=FL:g={s['MidPresence']}",f"treble=f=6500:c=FR:g={s['SideAir']}",f"equalizer=f=280:t=q:w=0.8:c=FL:g={s['MidMud']}"]
    f+=['stereotools=mode=ms>lr']
    if s['WidthEnabled']: f += [f"stereotools=slev={s['Width']}"]
    if s['FadeIn']: f+=['afade=t=in:d=0.8']
    if s['FadeOut']:
        if duration<=0: raise ValueError('Fade-out needs a readable duration')
        length=min(1.5,duration/2); f += [f'afade=t=out:st={duration-length}:d={length}']
    return ','.join(f)
def normalizer(s,m=None):
    f=f"loudnorm=I={s['Loudness']}:TP={s['Ceiling']-.2}:LRA=11:print_format=json"
    if m:
        for k in ['input_i','input_tp','input_lra','input_thresh','target_offset']:
            if not math.isfinite(float(m[k])): raise ValueError('Silent or unmeasurable audio')
        f+=f":measured_I={m['input_i']}:measured_TP={m['input_tp']}:measured_LRA={m['input_lra']}:measured_thresh={m['input_thresh']}:offset={m['target_offset']}:linear=true"
    return f
def finalizer(s):
    rate,bits,fmt=(48000,24,'s32') if s['Format']==0 else (44100,16,'s16')
    return f"aresample={rate*8},alimiter=limit={10**((s['Ceiling']-.1)/20)}:level=false:attack=5:release=80:latency=true,aresample=osr={rate}:osf={fmt}:dither_method={'triangular' if s['Dither'] else 'none'}:output_sample_bits={bits}"
def measurement(log):
    matches=re.findall(r'\{\s*"input_i".*?\}',log,re.S)
    if not matches: raise ValueError('No loudness measurement returned')
    m=json.loads(matches[-1]);
    if not math.isfinite(float(m['input_i'])): raise ValueError('Silent audio cannot be mastered')
    return m
def duration(log):
    m=re.search(r'Duration: (\d+):(\d+):([\d.]+)',log)
    return sum(float(v)*w for v,w in zip(m.groups(),[3600,60,1])) if m else 0
class Engine:
    def __init__(self,progress=lambda text,pct:None): self.progress=progress; self.cancel=threading.Event(); self.process=None; self.ffmpeg=ROOT/'bin/ffmpeg.exe'
    def run(self,args,title='Processing',seconds=0,start=0,span=100,exe=None):
        self.progress(title,start)
        with tempfile.TemporaryFile(mode='w+',encoding='utf-8') as log:
            cmd=([str(self.ffmpeg),'-hide_banner','-nostdin','-nostats','-stats_period','0.3','-progress','pipe:1']+list(map(str,args))) if exe is None else [str(exe)]+list(map(str,args))
            self.process=subprocess.Popen(cmd,stdout=subprocess.PIPE,stderr=log,text=True,encoding='utf-8',errors='replace',creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
            try:
                for line in self.process.stdout:
                    if self.cancel.is_set(): self.process.kill(); raise InterruptedError('Cancelled; completed exports are preserved')
                    if seconds and line.startswith('out_time_us='):
                        try: self.progress(title,start+span*min(1,float(line.split('=')[1])/1e6/seconds))
                        except ValueError: pass
                self.process.wait(); log.seek(0); text=log.read()
                if self.cancel.is_set(): raise InterruptedError('Cancelled')
                if self.process.returncode: raise RuntimeError(text[-1600:] or 'Audio engine failed')
                return text
            finally:
                if self.process.poll() is None: self.process.kill(); self.process.wait()
                self.process.stdout.close(); self.process=None
    def stop(self):
        self.cancel.set()
        process=self.process
        if process and process.poll() is None:
            try: process.kill()
            except OSError: pass
    def analyze(self,path):
        text=self.run(['-i',path,'-af',normalizer(DEFAULT),'-f','null','-'],'Analyzing loudness, peaks and dynamics')
        return dict(measurement=measurement(text),duration=duration(text))
    def bands(self,path):
        g='[0:a:0]aformat=channel_layouts=stereo,atrim=duration=60,asplit=7[main]'+''.join(f'[b{i}]' for i in range(6))+';'+ ';'.join(f'[b{i}]bandpass=f={hz}:width_type=o:w=2,volumedetect@band{i},anullsink' for i,hz in enumerate(FREQ))
        log=self.run(['-i',path,'-filter_complex',g,'-map','[main]','-f','null','-'],'Analyzing spectral balance')
        return [float(re.search(r'\[volumedetect@band'+str(i)+r'\s+@[^\]]+\]\s+mean_volume:\s*(-?[\d.]+)',log)[1]) for i in range(6)]
    def detect(self,path,seconds):
        runtime=ROOT/'bin/detection'; node=runtime/'node-v24.13.0-win-x64/node.exe'
        if not node.exists(): raise RuntimeError('Local detection runtime not installed')
        with tempfile.TemporaryDirectory(prefix='OGDetect-') as d:
            d=Path(d); out=d/'result.json'; request=dict(source=str(path),duration=seconds,ffmpeg=str(self.ffmpeg),runtime=str(runtime),catalog=str(ROOT/'GenrePresets.json'),status=str(d/'status.json'),output=str(out))
            (d/'request.json').write_text(json.dumps(request),encoding='utf-8')
            self.run([ROOT/'detection/detect.mjs',d/'request.json'],'Detecting genre and vocals (local model)',exe=node)
            return json.loads(out.read_text())
    def master(self,source,folder,settings,kind='wav',reference=None):
        s=validate(settings); folder=Path(folder); folder.mkdir(parents=True,exist_ok=True)
        original=self.analyze(source); gains=[0]*6
        if reference:
            a,b=self.bands(source),self.bands(reference); am,bm=sum(a)/6,sum(b)/6
            gains=[round(max(-3,min(3,(y-bm)-(x-am)))*s['Match']/100,2) if min(x,y)>=-65 else 0 for x,y in zip(a,b)]
        processing=chain(s,gains,original['duration']); seconds=original['duration']
        paths=[]; stem=Path(source).stem+' - mastered'; n=1
        extensions=['wav','mp3'] if kind=='both' else [kind]
        while any((folder/(stem+('.'+e))).exists() for e in extensions): n+=1; stem=Path(source).stem+f' - mastered ({n})'
        with tempfile.TemporaryDirectory(prefix='OGMaster-') as d:
            pcm=Path(d)/'master.wav'; mp3=Path(d)/'master.mp3'
            log=self.run(['-i',source,'-af',processing+','+normalizer(s),'-f','null','-'],'Measuring processed audio',seconds,10,25)
            m=measurement(log)
            self.run(['-y','-i',source,'-map','0:a:0','-vn','-af',processing+','+normalizer(s,m)+','+finalizer(s),'-c:a','pcm_s24le' if s['Format']==0 else 'pcm_s16le',pcm],'Rendering master',seconds,35,35)
            measured=self.analyze(pcm)['measurement']; mp3_measure=None
            if kind in ('mp3','both'):
                self.run(['-y','-i',pcm,'-map','0:a:0','-vn','-c:a','libmp3lame','-b:a','320k',mp3],'Encoding MP3',seconds,75,10); mp3_measure=self.analyze(mp3)['measurement']
            import shutil
            for ext in extensions:
                dest=folder/(stem+'.'+ext)
                # Exclusive creation prevents accidental overwrites, including another app's exports.
                with open(dest,'xb') as target,open(pcm if ext=='wav' else mp3,'rb') as data: shutil.copyfileobj(data,target)
                paths.append(str(dest))
        result=dict(source=str(source),files=paths,settings=s,input=original['measurement'],output=measured,mp3=mp3_measure,referenceGains=gains)
        (folder/(stem+'.report.json')).write_text(json.dumps(result,indent=2),encoding='utf-8')
        self.progress('Export complete',100); return result
