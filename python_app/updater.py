"""GitHub release selection and verified, cancellable Windows EXE downloads."""
import hashlib,hmac,json,os,re,threading,urllib.request,uuid
from pathlib import Path
from urllib.parse import urlsplit
REPO='ogchriscagle-cmd/ogstudiomastering'
API=f'https://api.github.com/repos/{REPO}/releases/latest'

def version(value):
    match=re.fullmatch(r'v?(\d+)\.(\d+)\.(\d+)',str(value))
    if not match:raise ValueError('Unsupported release version')
    return tuple(map(int,match.groups()))

def fetch_latest(opener=urllib.request.urlopen):
    request=urllib.request.Request(API,headers={'User-Agent':'OG-Studio-Mastering','Accept':'application/vnd.github+json'})
    with opener(request,timeout=15) as response:return json.load(response)

def release_asset(release,current):
    if not isinstance(release,dict):raise ValueError('Could not read GitHub release information')
    if release.get('draft') or release.get('prerelease'):return None
    latest=version(release.get('tag_name'));local=version(current)
    if latest<=local:return None
    tag='v'+'.'.join(map(str,latest));name=f'OG-Studio-Mastering-{tag[1:]}-win-x64.exe'
    asset=next((a for a in release.get('assets',[]) if a.get('name')==name),None)
    if not asset:raise ValueError('The newer release does not have a Windows EXE yet. Try again later.')
    expected=f'https://github.com/{REPO}/releases/download/{tag}/{name}'
    if asset.get('browser_download_url')!=expected:raise ValueError('Unexpected release download address')
    digest=asset.get('digest') or ''
    if not re.fullmatch(r'sha256:[0-9a-fA-F]{64}',digest):raise ValueError('The update has no SHA-256 checksum. Open GitHub releases to review it.')
    size=asset.get('size')
    if not isinstance(size,int) or isinstance(size,bool) or not 0<size<=2_000_000_000:raise ValueError('Invalid update download size')
    return dict(version=tag,name=name,url=expected,sha256=digest.split(':',1)[1].lower(),size=size)

def file_hash(path,cancel):
    digest=hashlib.sha256()
    with open(path,'rb') as data:
        while chunk:=data.read(1024*1024):
            if cancel.is_set():raise InterruptedError('Update download cancelled')
            digest.update(chunk)
    return digest.hexdigest()

def download(asset,folder,progress=lambda text,pct:None,cancel=None,opener=urllib.request.urlopen):
    cancel=cancel or threading.Event()
    if cancel.is_set():raise InterruptedError('Update download cancelled')
    folder=Path(folder);folder.mkdir(parents=True,exist_ok=True)
    destination=folder/asset['name']
    if destination.exists():
        progress('Checking previously downloaded update...',0)
        if destination.is_file() and hmac.compare_digest(file_hash(destination,cancel),asset['sha256']):return str(destination)
    n=2
    while destination.exists():destination=folder/(Path(asset['name']).stem+f' ({n}).exe');n+=1
    partial=folder/('.'+asset['name']+'.'+uuid.uuid4().hex+'.part')
    try:
        request=urllib.request.Request(asset['url'],headers={'User-Agent':'OG-Studio-Mastering'})
        progress('Downloading '+asset['version']+'...',0)
        with opener(request,timeout=20) as response,open(partial,'xb') as target:
            final=urlsplit(response.geturl())
            if final.scheme!='https' or final.hostname not in ('github.com','release-assets.githubusercontent.com','objects.githubusercontent.com'):raise ValueError('Unexpected download redirect')
            digest=hashlib.sha256();received=0
            while True:
                if cancel.is_set():raise InterruptedError('Update download cancelled')
                chunk=response.read(1024*1024)
                if not chunk:break
                received+=len(chunk)
                if received>asset['size']:raise ValueError('Update is larger than its published size')
                target.write(chunk);digest.update(chunk)
                progress(f"Downloading {asset['version']} · {received/1048576:.1f} / {asset['size']/1048576:.1f} MB",min(99,received*100/asset['size']))
        if cancel.is_set():raise InterruptedError('Update download cancelled')
        progress('Verifying update checksum...',99)
        if received!=asset['size'] or not hmac.compare_digest(digest.hexdigest(),asset['sha256']):raise ValueError('Update verification failed. The incomplete download was removed; please try again.')
        # Windows rename fails instead of overwriting a file created by another process.
        os.rename(partial,destination)
        progress('Update downloaded and verified',100);return str(destination)
    finally:
        if partial.exists():partial.unlink()
