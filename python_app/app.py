"""OG Studio Mastering: PySide6 desktop application."""
import json, os, sys, time, traceback, urllib.request, webbrowser, ssl
from pathlib import Path
from PySide6.QtCore import Qt, QThread, Signal, QTimer, QUrl, QSignalBlocker, QStandardPaths
from PySide6.QtGui import QColor, QIcon, QPainter, QPen, QPixmap
from PySide6.QtWidgets import (QApplication,QMainWindow,QWidget,QVBoxLayout,QHBoxLayout,QGridLayout,QLabel,QPushButton,QComboBox,QDoubleSpinBox,QCheckBox,QScrollArea,QGroupBox,QFileDialog,QMessageBox,QProgressBar,QPlainTextEdit,QSlider,QSplashScreen,QDial)
from PySide6.QtMultimedia import QMediaPlayer,QAudioOutput
from updater import fetch_latest,release_asset,download as download_update
from engine import ROOT,DEFAULT,RANGES,CATALOG,genre,validate,Engine
VERSION='2.0.3'
RELEASES='https://github.com/ogchriscagle-cmd/ogstudiomastering/releases'
PREFERENCES=Path(os.environ.get('LOCALAPPDATA',str(Path.home())))/'OGMastering/preferences.json'
PALETTES={'Midnight Cyan':('#080d16','#13cee7'),'Violet Night':('#120d20','#b78aff'),'Emerald':('#08170f','#36dba0'),'Crimson':('#1b0c14','#ff6b87'),'Amber':('#191307','#f6bf43'),'Ocean Blue':('#091321','#69adff')}
LABELS={'Loudness':'Loudness target (LUFS)','Ceiling':'True peak ceiling (dBTP)','HP':'High-pass (Hz)','DeEss':'De-esser (%)','Mud':'Mud reduction (dB)','Harsh':'Harshness reduction (dB)','Glue':'Glue (%)','Excite':'Exciter (%)','Bass':'Bass (dB)','Air':'Air (dB)','Width':'Stereo width','MidPresence':'Mid presence (dB)','SideAir':'Side air (dB)','Match':'Reference match (%)','GlueThreshold':'Glue threshold (dB)','GlueRatio':'Glue ratio','GlueMix':'Glue wet mix (%)','SideCut':'Side low cut (Hz)','MidMud':'Mid mud (dB)','SatDrive':'Saturation drive (%)'}
class Worker(QThread):
    progress=Signal(str,float); result=Signal(object); failed=Signal(str)
    def __init__(self,operation): super().__init__(); self.operation=operation; self.engine=Engine(lambda t,p:self.progress.emit(t,p))
    def run(self):
        try:
            result=self.operation(self.engine)
            if self.engine.cancel.is_set():raise InterruptedError('Operation cancelled')
            self.result.emit(result)
        except Exception as e:
            try:
                path=Path(os.environ.get('OG_ERROR_LOG_PATH',str(PREFERENCES.parent/'last-operation-error.log')));path.parent.mkdir(parents=True,exist_ok=True);path.write_text(traceback.format_exc(),encoding='utf-8')
            except OSError:pass
            self.failed.emit(str(e))
class Knob(QDial):
    def __init__(self,color):super().__init__();self.color=QColor(color)
    def paintEvent(self,event):
        from PySide6.QtCore import QRectF,QPointF
        import math
        p=QPainter(self);p.setRenderHint(QPainter.Antialiasing);rect=QRectF(9,9,self.width()-18,self.height()-18);p.setPen(QPen(QColor('#293448'),4));p.setBrush(QColor('#111925'));p.drawEllipse(rect)
        ratio=(self.value()-self.minimum())/max(1,self.maximum()-self.minimum());p.setPen(QPen(self.color,4));p.drawArc(rect,225*16,-int(270*ratio*16));center=rect.center();angle=math.radians(135+270*ratio);radius=rect.width()*.32;p.setPen(QPen(self.color,3));p.drawLine(center,QPointF(center.x()+math.cos(angle)*radius,center.y()+math.sin(angle)*radius));p.setBrush(self.color);p.drawEllipse(center,3,3)
class Waveform(QWidget):
    seek=Signal(float)
    def __init__(self): super().__init__(); self.samples=[]; self.position=0; self.setMinimumHeight(150)
    def paintEvent(self,event):
        p=QPainter(self); p.fillRect(self.rect(),QColor('#0b101b')); p.setPen(QPen(QColor('#5b7499'),1)); mid=self.height()/2
        if self.samples:
            for x in range(self.width()):
                i=min(len(self.samples)-1,int(x*len(self.samples)/max(1,self.width()))); v=self.samples[i]*mid*.92; p.drawLine(x,int(mid-v),x,int(mid+v))
        else: p.drawText(self.rect(),Qt.AlignCenter,'Import a song to see its waveform')
        p.setPen(QPen(QColor('#69adff'),2)); x=int(self.position*self.width()); p.drawLine(x,0,x,self.height())
    def mousePressEvent(self,event): self.seek.emit(event.position().x()/max(1,self.width()))
def wave_data(engine,path):
    import array,tempfile
    with tempfile.TemporaryDirectory(prefix='OGWave-') as tmp:
        dest=Path(tmp)/'wave.raw'
        engine.run(['-y','-i',path,'-t','1800','-ac','1','-ar','8000','-f','f32le',dest],'Drawing waveform')
        values=array.array('f');values.frombytes(dest.read_bytes());step=max(1,len(values)//1800)
        return [max(abs(x) for x in values[i:i+step]) for i in range(0,len(values),step)]
class Studio(QMainWindow):
    def __init__(self):
        super().__init__(); self.setWindowTitle('OG Studio Mastering'); self.resize(1450,960); self.setMinimumSize(1050,720); self.setWindowIcon(QIcon(str(ROOT/'assets/og-blue.ico'))); self.setAcceptDrops(True)
        self.settings=genre(0); self.sources=[]; self.reference=None; self.output=None; self.report=None; self.input_measure=None; self.output_measure=None; self.detection=None; self.worker=None; self.mode='simple'; self.sessions={}; self.controls={}; self.dials={}; self.reading=False; self.advanced=[]
        self.player=QMediaPlayer(self); self.audio=QAudioOutput(self); self.player.setAudioOutput(self.audio); self.playing=''; self.last_position=0
        self.player.mediaStatusChanged.connect(self.media_ready);self.pending_seek=0;self.player.positionChanged.connect(self.play_position); self.player.durationChanged.connect(lambda ms:self.seek.setRange(0,max(1,ms)))
        container=QWidget(); self.setCentralWidget(container); outer=QVBoxLayout(container); outer.setContentsMargins(18,12,18,12); outer.setSpacing(12)
        header=QHBoxLayout(); title=QLabel('OG STUDIO / MASTERING'); title.setObjectName('brand'); header.addWidget(title); header.addStretch(); self.modepicker=QComboBox(); self.modepicker.addItems(['Simple','Advanced']); self.modepicker.currentTextChanged.connect(self.switch_mode); header.addWidget(self.modepicker); header.addWidget(QLabel('LOCAL AUDIO ENGINE')); outer.addLayout(header)
        toolbar=QHBoxLayout(); toolbar.addWidget(QLabel('v'+VERSION+' · Python'))
        for text,callback in [('Sign in on GitHub ↗',lambda:webbrowser.open('https://github.com/login')),('Check updates',self.updates),('GitHub releases ↗',lambda:webbrowser.open(RELEASES)),('Open / import',self.open_file),('Save project',self.save_project),('Master / export',self.export)]:
            button=QPushButton(text); button.clicked.connect(callback); toolbar.addWidget(button)
            if text=='Check updates': self.update_button=button
            if text=='Master / export': self.toolbar_export=button
        toolbar.addStretch(); outer.addLayout(toolbar)
        body=QHBoxLayout(); outer.addLayout(body,1)
        sidebar=QWidget(); side=QVBoxLayout(sidebar); sidebar.setFixedWidth(300); scroll=QScrollArea(); scroll.setWidgetResizable(True); scroll.setWidget(sidebar); scroll.setFixedWidth(325); body.addWidget(scroll)
        side.addWidget(QLabel('MASTERING CONTROLS')); side.addWidget(QLabel('COLOR THEME')); self.theme=QComboBox(); self.theme.addItems(PALETTES); self.theme.currentTextChanged.connect(self.apply_theme); side.addWidget(self.theme)
        self.genres=QComboBox(); self.genres.addItems([p['Name'] for p in CATALOG]); self.genres.currentIndexChanged.connect(self.select_genre); self.genre_label=QLabel('GENRE');side.addWidget(self.genre_label); side.addWidget(self.genres); self.advanced.extend([self.genres,self.genre_label])
        styles=QGroupBox('STYLE'); sl=QGridLayout(styles)
        for i,name in enumerate(['Warm','Bright','Punchy','Transparent','Vintage','Modern']):
            b=QPushButton(name); b.clicked.connect(lambda checked=False,n=name:self.style(n)); sl.addWidget(b,i//3,i%3)
        side.addWidget(styles); self.advanced.append(styles)
        side.addWidget(self.make_group('LOUDNESS / OUTPUT',['Loudness','Ceiling']))
        self.export_type=QComboBox(); self.export_type.addItems(['WAV · lossless','MP3 · 320 kbps','Both WAV + MP3']); side.addWidget(self.export_type)
        self.pcm=QComboBox(); self.pcm.addItems(['48 kHz / 24-bit','44.1 kHz / 16-bit']); self.pcm.currentIndexChanged.connect(lambda n:self.settings.update(Format=n)); side.addWidget(self.pcm)
        ref=QPushButton('Upload reference track'); ref.clicked.connect(self.choose_reference); side.addWidget(ref); self.reference_label=QLabel('Optional · local tone matching'); self.reference_label.setWordWrap(True); side.addWidget(self.reference_label); clear=QPushButton('Clear reference'); clear.clicked.connect(self.clear_reference); side.addWidget(clear)
        presets=QHBoxLayout(); save=QPushButton('Save preset'); save.clicked.connect(self.save_preset); load=QPushButton('Load preset'); load.clicked.connect(self.load_preset); presets.addWidget(save);presets.addWidget(load);side.addLayout(presets)
        for name,keys in [('PROCESSING',['Repair','NoiseNR','MonoBass','Leveler','FadeIn','FadeOut','HP','Match']),('EQUALIZER',['EqEnabled']+[f'Eq{i}' for i in range(6)]),('DYNAMICS',['GlueEnabled','GlueThreshold','GlueRatio','GlueMix']),('STEREO / M/S',['WidthEnabled','MSEnabled','SideCut','MidPresence','SideAir','MidMud']),('COLOR / OUTPUT',['SatEnabled','SatDrive','SatType','Dither'])]:
            group=self.make_group(name,keys); side.addWidget(group); self.advanced.append(group)
        side.addStretch()
        main_widget=QWidget(); main=QVBoxLayout(main_widget); main.setContentsMargins(8,0,0,0); main_scroll=QScrollArea(); main_scroll.setWidgetResizable(True); main_scroll.setWidget(main_widget); body.addWidget(main_scroll,1)
        top=QHBoxLayout(); self.track=QLabel('Your next release starts here.'); self.track.setObjectName('track'); top.addWidget(self.track,1); choose=QPushButton('+ Choose songs'); choose.clicked.connect(self.choose_songs); top.addWidget(choose);main.addLayout(top)
        self.instructions=QLabel('SIMPLE MASTERING\n\n1. Choose your Suno song\n2. Add a reference (optional)\n3. Choose loudness and master / export\n\nSwitch to Advanced for individual processing controls.'); self.instructions.setObjectName('instructions'); main.addWidget(self.instructions)
        types=QHBoxLayout()
        for text,callback in [('Has vocals',lambda:self.set_value('DeEss',20)),('Instrumental',lambda:self.set_value('DeEss',0)),('Auto Detect',self.detect)]:
            b=QPushButton(text); b.clicked.connect(callback);types.addWidget(b)
        main.addLayout(types); self.detect_label=QLabel('Genre and vocals are detected locally. Suggestions require your approval.');self.detect_label.setWordWrap(True);main.addWidget(self.detect_label); self.apply_detection=QPushButton('Apply detected genre and vocal settings');self.apply_detection.setEnabled(False); self.apply_detection.clicked.connect(self.accept_detection);main.addWidget(self.apply_detection)
        quick=self.make_quick();main.addWidget(quick);self.advanced.append(quick)
        self.wave=Waveform(); main.addWidget(self.wave); self.wave.seek.connect(lambda fraction:self.player.setPosition(int(fraction*self.player.duration())))
        play=QHBoxLayout()
        for name,callback in [('▶ Original',lambda:self.play('original')),('▶ Mastered',lambda:self.play('master')),('■ Stop',self.player.stop)]:
            b=QPushButton(name);b.clicked.connect(callback);play.addWidget(b)
        self.levelmatch=QCheckBox('Level-match A/B');self.levelmatch.setChecked(True);self.levelmatch.toggled.connect(self.play_gain);play.addWidget(self.levelmatch);main.addLayout(play)
        self.seek=QSlider(Qt.Horizontal);self.seek.sliderMoved.connect(self.player.setPosition);main.addWidget(self.seek)
        self.meters=QLabel('SOURCE  — LUFS      MASTER  — LUFS      TRUE PEAK  — dBTP      RANGE  — LU');self.meters.setObjectName('meters');main.addWidget(self.meters)
        actions=QHBoxLayout(); self.render=QPushButton('MASTER & EXPORT ↓');self.render.clicked.connect(self.export); self.cancel_button=QPushButton('Cancel'); self.cancel_button.clicked.connect(self.cancel);actions.addWidget(self.render);actions.addWidget(self.cancel_button);main.addLayout(actions)
        self.advice=QPlainTextEdit();self.advice.setReadOnly(True);self.advice.setPlaceholderText('Mastering analysis and export reports appear here.');self.advice.setMinimumHeight(120);main.addWidget(self.advice)
        tools=QHBoxLayout()
        for text,callback in [('Save report',self.save_report),('Open export folder',self.open_export)]:
            b=QPushButton(text);b.clicked.connect(callback);tools.addWidget(b)
        main.addLayout(tools);main.addStretch()
        self.status=QLabel('Ready · import a song to begin');self.status.setWordWrap(True);outer.addWidget(self.status);self.progress=QProgressBar();self.progress.setRange(0,100);self.progress.setValue(0);self.progress.setTextVisible(False);outer.addWidget(self.progress);self.log=QPlainTextEdit();self.log.setReadOnly(True);self.log.setMaximumHeight(85);outer.addWidget(self.log)
        prefs={}
        try: prefs=json.loads(PREFERENCES.read_text(encoding='utf-8-sig'))
        except (OSError,ValueError): pass
        self.theme.setCurrentText(prefs.get('Theme','Midnight Cyan'));self.apply_theme(self.theme.currentText(),False);self.populate();self.switch_mode('Simple');self.busy(False)
    def make_group(self,title,keys):
        box=QGroupBox(title); layout=QGridLayout(box)
        for i,key in enumerate(keys):
            value=self.settings[key]; label=LABELS.get(key,('EQ '+str([80,250,800,2500,6000,12000][int(key[-1])])+' Hz') if key.startswith('Eq') and key[-1].isdigit() else key)
            if isinstance(value,bool):
                control=QCheckBox(label);control.setChecked(value);control.toggled.connect(lambda v,k=key:self.changed(k,v));layout.addWidget(control,i,0,1,2)
            elif key=='SatType':
                control=QComboBox();control.addItems(['Clean / tanh','Warm / atan','Vintage / cubic']);control.currentIndexChanged.connect(lambda v:self.changed('SatType',v));layout.addWidget(QLabel('Saturation type'),i,0);layout.addWidget(control,i,1)
            else:
                control=QDoubleSpinBox();control.setRange(*RANGES[key]);control.setDecimals(2);control.setSingleStep(.1 if key in ('Width','Ceiling','GlueRatio') else .5);control.setValue(value);control.valueChanged.connect(lambda v,k=key:self.changed(k,v));layout.addWidget(QLabel(label),i,0);layout.addWidget(control,i,1)
            self.controls[key]=control
        return box
    def make_quick(self):
        box=QGroupBox('QUICK ADJUST');layout=QGridLayout(box)
        colors=['#ffac06','#ff4e58','#ff963b','#0dd3ef','#20d5a3','#c37dff','#a58aff','#629dff']
        for i,key in enumerate(['Bass','Excite','Harsh','Air','Mud','Glue','Width','DeEss']):
            col=QVBoxLayout();dial=Knob(colors[i]);lo,hi=RANGES[key];dial.setRange(int(lo*100),int(hi*100));dial.setValue(int(self.settings[key]*100));dial.setNotchesVisible(True);dial.setFixedSize(68,68);dial.setStyleSheet('QDial {background:'+colors[i]+';}');value=QDoubleSpinBox();value.setRange(lo,hi);value.setDecimals(2);value.setSingleStep(.05 if key=='Width' else .5);value.setValue(self.settings[key]);value.valueChanged.connect(lambda v,k=key:self.changed(k,v));value.valueChanged.connect(lambda v,d=dial:d.setValue(round(v*100)));dial.valueChanged.connect(lambda v,c=value:c.setValue(v/100));label=QLabel(key.upper());label.setAlignment(Qt.AlignCenter);col.addWidget(dial,0,Qt.AlignHCenter);col.addWidget(value);col.addWidget(label);layout.addLayout(col,i//4,i%4);self.controls[key]=value;self.dials[key]=dial
        return box
    def changed(self,key,value):
        if not self.reading:self.settings[key]=value
    def set_value(self,key,value):self.settings[key]=value;self.populate()
    def populate(self):
        self.reading=True
        for key,c in self.controls.items():
            blocker=QSignalBlocker(c)
            if isinstance(c,QCheckBox):c.setChecked(self.settings[key])
            elif isinstance(c,QComboBox):c.setCurrentIndex(int(self.settings[key]))
            else:c.setValue(self.settings[key])
            if key in self.dials:
                dial=self.dials[key];dial_blocker=QSignalBlocker(dial);dial.setValue(round(self.settings[key]*100))
        genre_blocker=QSignalBlocker(self.genres);self.genres.setCurrentIndex(next((i for i,p in enumerate(CATALOG) if p['Name']==self.settings['Genre']),0))
        blocker=QSignalBlocker(self.pcm);self.pcm.setCurrentIndex(int(self.settings['Format']));self.reading=False
    def select_genre(self,index):
        if index>=0:self.settings=genre(index);self.populate()
    def switch_mode(self,name):
        mode=name.lower()
        if mode!=self.mode:self.sessions[self.mode]=self.settings.copy();self.settings=self.sessions.get(mode,genre(0)).copy();self.mode=mode;self.populate()
        for w in self.advanced:w.setVisible(mode=='advanced')
        self.instructions.setVisible(mode=='simple')
    def style(self,name):
        options={'Warm':dict(Bass=1.5,Air=-1,Excite=0,Harsh=1.5),'Bright':dict(Air=1.5,Bass=0,Excite=10,Harsh=1),'Punchy':dict(Glue=20,Bass=1,Mud=1.5,Excite=0),'Transparent':dict(Bass=0,Air=0,Glue=0,Excite=0,Width=1),'Vintage':dict(Bass=1,Air=-1.5,Glue=15,Excite=10),'Modern':dict(Air=1,Mud=1.5,Glue=15,Width=1.1)};self.settings.update(options[name]);self.populate()
    def apply_theme(self,name,save=True):
        bg,accent=PALETTES.get(name,PALETTES['Midnight Cyan'])
        self.setStyleSheet(f'''QWidget {{background:{bg};color:#e6edf8;font:12px 'Segoe UI';}} QGroupBox {{border:1px solid #303848;border-radius:10px;margin-top:14px;padding:14px 8px 8px;}} QGroupBox::title {{color:{accent};subcontrol-origin:margin;left:10px;}} QPushButton,QComboBox,QDoubleSpinBox {{background:#182131;border:1px solid #344256;border-radius:7px;padding:8px;}} QPushButton:hover {{border-color:{accent};}} QPushButton:disabled {{color:#58647a;}} QPlainTextEdit {{background:#0b101b;border:1px solid #303848;border-radius:8px;}} QProgressBar {{max-height:8px;border:0;background:#222e40;}} QProgressBar::chunk {{background:{accent};}} QLabel#brand {{font-size:23px;font-weight:bold;color:{accent};}} QLabel#track {{font-size:19px;font-weight:bold;}} QLabel#meters,QLabel#instructions {{background:#121d2c;border:1px solid #303848;border-radius:10px;padding:16px;}} QScrollArea {{border:0;}}''')
        if save:
            try:PREFERENCES.parent.mkdir(parents=True,exist_ok=True);PREFERENCES.write_text(json.dumps({'Theme':name}))
            except OSError as e:self.message('Theme applied; preference could not be saved: '+str(e))
    def message(self,text,pct=None):
        if self.status.text()!=text:self.log.appendPlainText(time.strftime('%H:%M:%S')+'  '+text)
        self.status.setText(text)
        if pct is not None:self.progress.setValue(int(pct))
    def busy(self,value):
        self.render.setEnabled(not value and bool(self.sources));self.toolbar_export.setEnabled(not value and bool(self.sources));self.cancel_button.setEnabled(value);self.modepicker.setEnabled(not value)
        for c in self.controls.values():c.setEnabled(not value)
        self.genres.setEnabled(not value);self.update_button.setEnabled(not value)
        for dial in self.dials.values():dial.setEnabled(not value)
    def start(self,operation,callback):
        if self.worker:return False
        self.busy(True);w=Worker(operation);self.worker=w;w.progress.connect(self.message);w.result.connect(callback);w.failed.connect(self.error);w.finished.connect(lambda:self.finished(w));w.start();return True
    def finished(self,w):
        self.worker=None;self.busy(False);w.deleteLater()
        if getattr(self,'closing',False):self.close()
        elif getattr(self,'pending_update',None):
            asset=self.pending_update;self.pending_update=None;QTimer.singleShot(0,lambda:self.begin_update_download(asset))
        elif getattr(self,'pending_import',None):
            paths=self.pending_import;self.pending_import=None;QTimer.singleShot(0,lambda:self.import_songs(paths))
    def error(self,text):self.message(text);self.advice.appendPlainText(text)
    def cancel(self):
        self.pending_update=None
        if self.worker:self.worker.engine.stop();self.message('Cancelling current operation...')
    def choose_songs(self):
        paths,_=QFileDialog.getOpenFileNames(self,'Choose songs','','Audio (*.wav *.mp3 *.flac *.m4a *.aif *.aiff *.ogg)')
        if paths:self.import_songs(paths)
    def import_songs(self,paths):
        if self.worker:self.message('Wait for the current operation to finish.');return
        paths=[str(Path(p).resolve()) for p in paths]
        if not paths or any(not Path(p).is_file() for p in paths):raise ValueError('Song file is missing')
        self.sources=paths;self.output=None;self.output_measure=None;self.report=None;self.detection=None;self.apply_detection.setEnabled(False);self.track.setText(Path(paths[0]).name+(f'  + {len(paths)-1} songs' if len(paths)>1 else ''));self.player.stop();self.wave.samples=[];self.wave.update()
        def work(e):
            analysis=e.analyze(paths[0]);samples=wave_data(e,paths[0]);detection=None;error=None
            try:detection=e.detect(paths[0],analysis['duration'])
            except InterruptedError:raise
            except Exception as ex:error=str(ex)
            return dict(analysis=analysis,samples=samples,detection=detection,error=error)
        self.start(work,self.imported)
    def imported(self,result):
        self.analysis=result['analysis'];self.input_measure=self.analysis['measurement'];self.wave.samples=result['samples'];self.wave.update();self.update_meters();self.detection=result['detection'];self.show_detection();self.message('Analysis complete. '+('Detection unavailable: '+result['error'] if result['error'] else 'Ready to master.'))
    def show_detection(self):
        if self.detection:
            d=self.detection;self.detect_label.setText(f"Suggested genre: {d['genre']} {'(uncertain)' if d['genreUncertain'] else ''} · {d['vocals']}\nRelative model scores, not accuracy probabilities.");self.apply_detection.setEnabled(True)
    def detect(self):
        if not self.sources:return
        self.start(lambda e:e.detect(self.sources[0],getattr(self,'analysis',{}).get('duration',180)),self.detected)
    def detected(self,d):self.detection=d;self.show_detection();self.message('Detection complete. Review the suggestion before applying.')
    def accept_detection(self):
        if self.worker or not self.detection:return
        d=self.detection;index=next((i for i,g in enumerate(CATALOG) if g['Name']==d['genre']),0);self.genres.setCurrentIndex(index);self.settings=genre(index)
        if d['vocals']=='Likely vocals':self.settings['DeEss']=20
        elif d['vocals']=='Likely instrumental':self.settings['DeEss']=0
        self.populate();self.message('Detected settings applied. Listen and adjust as needed.')
    def choose_reference(self):
        if self.worker:return
        path,_=QFileDialog.getOpenFileName(self,'Reference audio','','Audio (*.wav *.mp3 *.flac *.m4a *.aif *.aiff *.ogg)')
        if path:self.reference=path;self.reference_label.setText(Path(path).name)
    def clear_reference(self):
        if not self.worker:self.reference=None;self.reference_label.setText('Reference matching off')
    def update_meters(self):
        a=self.input_measure or {};b=self.output_measure or {};self.meters.setText(f"SOURCE  {a.get('input_i','—')} LUFS      MASTER  {b.get('input_i','—')} LUFS\nTRUE PEAK  {b.get('input_tp','—')} dBTP      RANGE  {b.get('input_lra','—')} LU")
    def export(self):
        if self.worker or not self.sources:return
        folder=QFileDialog.getExistingDirectory(self,'Export mastered songs')
        if not folder:return
        settings=validate(self.settings.copy());kind=['wav','mp3','both'][self.export_type.currentIndex()];sources=self.sources.copy();reference=self.reference
        def work(e):
            results=[]
            for i,p in enumerate(sources):
                if e.cancel.is_set():raise InterruptedError('Batch cancelled; completed exports were preserved')
                e.progress(f'Mastering {i+1}/{len(sources)}: {Path(p).name}',0);r=e.master(p,folder,settings,kind,reference);results.append(r)
            return results
        self.start(work,self.exported)
    def exported(self,results):
        self.report=results;last=results[-1];self.output=last['files'][0];self.output_measure=last['mp3'] if self.output.endswith('.mp3') else last['output'];self.update_meters();self.advice.setPlainText(self.advisor(last)+'\n\n'+json.dumps(results,indent=2));self.message(f'Export complete · {len(results)} song(s). WAV/MP3 reports saved beside your masters.',100)
    def advisor(self,r):
        m=r['output'];s=r['settings'];notes=[]
        notes.append('PASS: true peak within ceiling.' if float(m['input_tp'])<=s['Ceiling']+.1 else 'Peak exceeds ceiling; lower the ceiling and remaster.')
        notes.append('PASS: loudness within 1 LU of target.' if abs(float(m['input_i'])-s['Loudness'])<=1 else 'Loudness differs by more than 1 LU; try less compression or a quieter target.')
        if float(m['input_lra'])<3:notes.append('Low loudness range. Mastering cannot restore lost dynamics.')
        if r.get('mp3'):notes.append('MP3 decoded loudness and peaks were measured separately; lossy encoding can raise peaks.')
        notes.append('Measurement suggestions do not guarantee streaming compliance.')
        return '\n\n'.join(notes)
    def play(self,version):
        path=self.output if version=='master' else (self.sources[0] if self.sources else None)
        if not path:return
        position=self.player.position();self.pending_seek=position;self.playing=version;self.player.setSource(QUrl.fromLocalFile(path));self.play_gain();self.player.setPosition(position);self.player.play()
    def media_ready(self,status):
        if status==QMediaPlayer.LoadedMedia and self.pending_seek:
            self.player.setPosition(self.pending_seek);self.pending_seek=0
    def play_gain(self):
        gain=1.
        if self.levelmatch.isChecked() and self.input_measure and self.output_measure:
            a=float(self.input_measure['input_i']);b=float(self.output_measure['input_i']);level=a if self.playing=='original' else b;gain=10**((min(a,b)-level)/20)
        self.audio.setVolume(gain)
    def play_position(self,ms):
        if not self.seek.isSliderDown():self.seek.setValue(ms)
        self.wave.position=ms/max(1,self.player.duration());self.wave.update()
    def save_project(self):
        if self.worker:return
        path,_=QFileDialog.getSaveFileName(self,'Save project','My mastering project.ogmaster','OG project (*.ogmaster)')
        if path:
            p=dict(Kind='OGMasteringProject',Version=1,Sources=self.sources,Reference=self.reference,Settings=self.settings,Mode=self.mode,ExportType=self.export_type.currentIndex(),LevelMatch=self.levelmatch.isChecked());Path(path).write_text(json.dumps(p,indent=2),encoding='utf-8');self.message('Project saved. Audio stays in its original location.')
    def open_file(self):
        if self.worker:return
        path,_=QFileDialog.getOpenFileName(self,'Open project or audio','','Projects / audio (*.ogmaster *.wav *.mp3 *.flac *.m4a *.aif *.aiff *.ogg)')
        if not path:return
        try:
            if Path(path).suffix.lower()!='.ogmaster':self.import_songs([path]);return
            p=json.loads(Path(path).read_text(encoding='utf-8-sig'))
            if p.get('Kind')!='OGMasteringProject' or p.get('Version')!=1 or p.get('Mode') not in ('simple','advanced') or p.get('ExportType') not in (0,1,2):raise ValueError('Unsupported project')
            settings=validate(p['Settings']);paths=p['Sources']
            for f in paths+([p['Reference']] if p.get('Reference') else []):
                if not Path(f).is_file():raise ValueError('Missing project audio: '+f)
            self.modepicker.setCurrentText(p['Mode'].title());self.settings=settings;self.populate();self.reference=p.get('Reference');self.reference_label.setText(Path(self.reference).name if self.reference else 'Reference matching off');self.export_type.setCurrentIndex(p['ExportType']);self.levelmatch.setChecked(p.get('LevelMatch',True))
            if paths:self.import_songs(paths)
        except Exception as e:self.error(str(e))
    def save_preset(self):
        path,_=QFileDialog.getSaveFileName(self,'Save preset','My preset.json','Preset (*.json)')
        if path:Path(path).write_text(json.dumps(self.settings,indent=2))
    def load_preset(self):
        if self.worker:return
        path,_=QFileDialog.getOpenFileName(self,'Load preset','','Preset (*.json)')
        if path:
            try:self.settings=validate(json.loads(Path(path).read_text(encoding='utf-8-sig')));self.populate()
            except Exception as e:self.error(str(e))
    def save_report(self):
        if not self.report:return
        path,_=QFileDialog.getSaveFileName(self,'Save report','OG Studio Mastering report.json','Report (*.json)')
        if path:Path(path).write_text(json.dumps(self.report,indent=2))
    def open_export(self):
        if self.output:os.startfile(str(Path(self.output).parent))
    def updates(self):
        if self.worker:return
        self.message('Checking GitHub for updates...',0)
        self.start(lambda e:fetch_latest(),self.updated)
    def updated(self,release):
        if self.worker and self.worker.engine.cancel.is_set():self.message('Update check cancelled');return
        try:
            asset=release_asset(release,VERSION)
            if not asset:self.message('You are up to date: v'+VERSION,100);return
            self.message('New update found: '+asset['version']+'. Preparing download...',0)
            self.pending_update=asset
        except (ValueError,TypeError,KeyError) as error:self.error(str(error))
    def begin_update_download(self,asset):
        folder=QStandardPaths.writableLocation(QStandardPaths.DownloadLocation) or str(Path.home()/'Downloads')
        self.start(lambda e:dict(path=download_update(asset,folder,e.progress,e.cancel),version=asset['version']),self.update_downloaded)
    def update_downloaded(self,result):
        self.message('Downloaded '+result['version']+' to '+result['path'],100)
        dialog=QMessageBox(self);dialog.setWindowTitle('Update downloaded');dialog.setText(result['version']+' is ready.');dialog.setInformativeText('Saved to '+result['path']+'\n\nSave your project before opening the new version. Your current app will stay open.');open_button=dialog.addButton('Open update',QMessageBox.AcceptRole);dialog.addButton('Later',QMessageBox.RejectRole);dialog.exec()
        if dialog.clickedButton()==open_button:os.startfile(result['path'])
    def dragEnterEvent(self,event):
        if event.mimeData().hasUrls() and not self.worker:event.acceptProposedAction()
    def dropEvent(self,event):
        paths=[u.toLocalFile() for u in event.mimeData().urls() if u.isLocalFile() and Path(u.toLocalFile()).suffix.lower() in ('.wav','.mp3','.flac','.m4a','.aif','.aiff','.ogg')]
        if paths:self.import_songs(paths)
    def closeEvent(self,event):
        if self.worker:self.closing=True;self.cancel();event.ignore();return
        self.player.stop();event.accept()
def main():
    def show_error(kind,error,tb):
        text=''.join(traceback.format_exception(kind,error,tb))
        try:
            directory=PREFERENCES.parent;directory.mkdir(parents=True,exist_ok=True);(directory/'python-error.log').write_text(text,encoding='utf-8')
        except OSError:pass
        QMessageBox.critical(None,'OG Studio Mastering',str(error))
    sys.excepthook=show_error
    app=QApplication(sys.argv);app.setApplicationName('OG Studio Mastering');app.setApplicationVersion(VERSION)
    splash_image=QPixmap(580,300);splash_image.fill(QColor('#091321'));p=QPainter(splash_image);p.drawPixmap(35,45,QPixmap(str(ROOT/'assets/og-blue.png')).scaled(90,90,Qt.KeepAspectRatio,Qt.SmoothTransformation));p.setPen(QColor('#69adff'));font=p.font();font.setPointSize(24);font.setBold(True);p.setFont(font);p.drawText(145,78,'OG STUDIO');font.setPointSize(20);p.setFont(font);p.drawText(145,114,'MASTERING');font.setPointSize(9);font.setBold(False);p.setFont(font);p.drawText(148,144,'YOUR SOUND. RELEASE READY.');p.drawText(35,260,'v'+VERSION+'   ·   OFFLINE. PRIVATE. YOURS.');p.end();splash=QSplashScreen(splash_image);splash.show();splash.showMessage('Loading mastering controls...',Qt.AlignBottom|Qt.AlignHCenter,QColor('#eeeeff'));app.processEvents()
    studio=Studio();studio.show();splash.finish(studio)
    try:
        import pyi_splash
        pyi_splash.close()
    except ImportError:pass
    if '--write-splash' in sys.argv:
        splash_image.save(str(ROOT/'assets/python-splash.png'));app.quit();return
    if '--smoke-test' in sys.argv:
        def smoke():
            ssl.create_default_context()
            (Path(os.environ.get('OG_SMOKE_OUTPUT',str(ROOT/'verification')))).mkdir(parents=True,exist_ok=True);studio.grab().save(str(Path(os.environ.get('OG_SMOKE_OUTPUT',str(ROOT/'verification')))/'python-ui.png'));(Path(os.environ.get('OG_SMOKE_OUTPUT',str(ROOT/'verification')))/'python-smoke.txt').write_text('PASS: Python standalone startup');print('PASS: PySide6 interface, theme picker, modes, controls, toolbar and splash');app.quit()
        QTimer.singleShot(800,smoke)
    sys.exit(app.exec())
if __name__=='__main__':
    if '--update-check-test' in sys.argv:
        test_app=QApplication(sys.argv);test_window=Studio();folder=Path(os.environ.get('OG_TEST_OUTPUT',str(PREFERENCES.parent)));folder.mkdir(parents=True,exist_ok=True)
        def checked(release):
            (folder/'update-check.json').write_text(json.dumps(dict(ok=True,tag=release.get('tag_name'))),encoding='utf-8');test_app.exit(0)
        def check_failed(text):
            (folder/'update-check.json').write_text(json.dumps(dict(ok=False,error=text)),encoding='utf-8');test_app.exit(1)
        test_window.start(lambda e:fetch_latest(),checked);test_window.worker.failed.connect(check_failed);QTimer.singleShot(30000,lambda:test_app.exit(2));sys.exit(test_app.exec())
    elif '--self-test' in sys.argv:
        folder=Path(os.environ.get('OG_TEST_OUTPUT',str(Path.home()/'OGMastering-test')))
        try:
            from verify import run_tests
            run_tests(folder)
        except Exception:
            folder.mkdir(parents=True,exist_ok=True);(folder/'engine-test-error.txt').write_text(traceback.format_exc(),encoding='utf-8');sys.exit(1)
        finally:
            try:
                import pyi_splash
                pyi_splash.close()
            except ImportError:pass
    else:main()
