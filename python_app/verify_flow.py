import os,sys,time,tempfile
from pathlib import Path
sys.path.insert(0,'python_app')
from PySide6.QtWidgets import QApplication,QFileDialog
from PySide6.QtMultimedia import QMediaPlayer
from engine import Engine
from app import Studio
Path('verification').mkdir(exist_ok=True)
app=QApplication([]);w=Studio();w.show()
def wait_worker():
    deadline=time.monotonic()+80
    while w.worker and time.monotonic()<deadline:app.processEvents();time.sleep(.02)
    app.processEvents();assert not w.worker,w.status.text()
source=Path('verification/python-flow-source.wav').resolve()
Engine().run(['-y','-f','lavfi','-i','sine=frequency=440:duration=4:sample_rate=48000','-ac','2',source])
original=Engine.detect
Engine.detect=lambda *args:dict(genre='Dark Rap',genreUncertain=False,vocals='Likely vocals')
w.import_songs([str(source)]);wait_worker()
assert w.input_measure and w.wave.samples and max(w.wave.samples)>.01,w.status.text()
assert w.detection and w.apply_detection.isEnabled();w.accept_detection();assert w.settings['Genre']=='Dark Rap'
with tempfile.TemporaryDirectory(dir='verification',prefix='python-ui-export-') as tmp:
    QFileDialog.getExistingDirectory=lambda *args:tmp
    w.export_type.setCurrentIndex(2);w.export();wait_worker();assert w.report and len(w.report[0]['files'])==2,w.status.text()
    w.audio.setMuted(True);w.play('master');deadline=time.monotonic()+10
    while w.player.mediaStatus() not in (QMediaPlayer.LoadedMedia,QMediaPlayer.BufferedMedia,QMediaPlayer.EndOfMedia) and time.monotonic()<deadline:app.processEvents();time.sleep(.02)
    assert w.player.error()==QMediaPlayer.NoError,w.player.errorString();w.player.stop();w.player.setSource(__import__('PySide6.QtCore',fromlist=['QUrl']).QUrl());app.processEvents()
Engine.detect=original;w.close();app.processEvents()
print('PASS: threaded import, waveform signal data, automatic analysis, suggestion/apply, actual WAV+MP3 export, Qt media playback loading.')
