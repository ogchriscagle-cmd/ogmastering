# Reproducible Windows one-file build, including the existing offline model.
from pathlib import Path
import os,sys
root=Path(SPECPATH).parent
resources=[(str(root/'GenrePresets.json'),'.'),(str(root/'assets'),'assets'),(str(root/'bin/ffmpeg.exe'),'bin'),(str(root/'detection/detect.mjs'),'detection'),(str(root/'THIRD-PARTY-NOTICES.md'),'notices'),(str(root/'packaging/APACHE-2.0.txt'),'notices'),(str(root/'packaging/CLAP-MODEL-CARD.md'),'notices'),(str(root/'python_app/PYTHON-NOTICES.md'),'notices'),(str(root/'python_app/licenses'),'notices/licenses')]
runtime=root/'bin/detection'
for file in runtime.rglob('*'):
    if not file.is_file():continue
    rel=file.relative_to(runtime).as_posix()
    if rel=='node.zip':continue
    if rel.startswith('node-v24.13.0-win-x64/') and rel not in ('node-v24.13.0-win-x64/node.exe','node-v24.13.0-win-x64/LICENSE'):continue
    if '/darwin/' in rel or '/linux/' in rel or '/win32/arm64/' in rel:continue
    resources.append((str(file),'bin/detection/'+str(Path(rel).parent)))
distribution=root/'bin/distribution' if (root/'bin/distribution').exists() else root/'bin/download'
for file in distribution.rglob('*'):
    if file.is_file() and 'bin' not in file.relative_to(distribution).parts:resources.append((str(file),'notices/ffmpeg/'+str(file.relative_to(distribution).parent)))
for directory in (root/'.venv/Lib/site-packages').glob('*dist-info'):
    if directory.name.lower().startswith(('pyside6','shiboken6')):
        for file in directory.rglob('*'):
            if file.is_file() and ('license' in file.name.lower() or 'copying' in file.name.lower() or 'license' in str(file.parent).lower()):resources.append((str(file),'notices/python/'+directory.name+'/'+str(file.relative_to(directory).parent)))
a=Analysis([str(root/'python_app/app.py')],pathex=[str(root/'python_app')],binaries=[],datas=resources,hiddenimports=['pyi_splash'],hookspath=[],hooksconfig={},runtime_hooks=[],excludes=['PySide6.QtWebEngineCore','PySide6.QtWebEngineWidgets','PySide6.QtPdf','tkinter','unittest','pytest'])
# Never bundle similarly named ICU DLLs from unrelated tools on PATH.
# Qt uses Windows' ICU API; Poppler's ICU exports are incompatible.
a.binaries=[entry for entry in a.binaries if not ('native\\poppler' in entry[1].lower() and Path(entry[0]).name.lower().startswith('icu'))]
python_dlls=Path(sys.base_prefix)/'DLLs'
a.binaries=[(name,str(python_dlls/Path(name).name),kind) if Path(name).name.lower() in ('libcrypto-3-x64.dll','libssl-3-x64.dll') and (python_dlls/Path(name).name).exists() else (name,path,kind) for name,path,kind in a.binaries]
pyz=PYZ(a.pure)
splash=Splash(str(root/'assets/python-splash.png'),binaries=a.binaries,datas=a.datas,text_pos=(35,205),text_size=10,text_color='#e6edf8',text_default='Loading OG Studio Mastering...',always_on_top=False)
if os.environ.get('OG_BUILD_ONEDIR')=='1':
    exe=EXE(pyz,a.scripts,[],exclude_binaries=True,name='OG-Studio-Mastering-Python',debug=False,strip=False,upx=False,console=False,icon=str(root/'assets/og-blue.ico'),version=str(root/'python_app/windows-version.txt'))
    coll=COLLECT(exe,a.binaries,a.datas,strip=False,upx=False,name='OG-Studio-Mastering-Python')
else:
    exe=EXE(pyz,a.scripts,splash,splash.binaries,a.binaries,a.datas,[],name='OG-Studio-Mastering-2.0.0-win-x64',debug=False,bootloader_ignore_signals=False,strip=False,upx=False,console=False,icon=str(root/'assets/og-blue.ico'),version=str(root/'python_app/windows-version.txt'))
