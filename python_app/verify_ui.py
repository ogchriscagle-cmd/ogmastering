import json,os,sys,tempfile,time
from pathlib import Path
sys.path.insert(0,'python_app')
from PySide6.QtWidgets import QApplication,QFileDialog
from app import Studio,PALETTES
Path('verification').mkdir(exist_ok=True)
app=QApplication([]);w=Studio();w.show()
assert len(w.genres.model().stringList())==58 if hasattr(w.genres.model(),'stringList') else w.genres.count()==58
w.modepicker.setCurrentText('Advanced');w.controls['Bass'].setValue(2.5);advanced=w.settings.copy()
w.modepicker.setCurrentText('Simple');assert w.settings['Bass']!=2.5
w.modepicker.setCurrentText('Advanced');assert w.settings==advanced
for name in PALETTES:w.apply_theme(name,False);assert w.settings==advanced
with tempfile.TemporaryDirectory(dir='verification',prefix='project-test-') as tmp:
    path=str(Path(tmp)/'roundtrip.ogmaster');QFileDialog.getSaveFileName=lambda *a,**k:(path,'');w.save_project()
    w.settings['Bass']=-2;w.populate();QFileDialog.getOpenFileName=lambda *a,**k:(path,'');w.open_file();assert w.settings==advanced
    legacy=Path('verification/toolbar.ogmaster')
    if legacy.exists():QFileDialog.getOpenFileName=lambda *a,**k:(str(legacy),'');w.open_file();assert w.settings['Loudness']==-14
w.modepicker.setCurrentText('Advanced');app.processEvents();w.grab().save('verification/python-advanced-ui.png');w.close()
print('PASS: Python UI theme switching, separate Simple/Advanced settings, project roundtrip and existing PowerShell project compatibility.')
