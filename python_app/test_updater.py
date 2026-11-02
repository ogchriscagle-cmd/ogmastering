import hashlib,io,tempfile,threading,unittest
from pathlib import Path
from updater import release_asset,download,REPO
class Response(io.BytesIO):
    def geturl(self):return 'https://release-assets.githubusercontent.com/release.exe'
class UpdateTests(unittest.TestCase):
    def setUp(self):
        self.payload=b'MZ'+b'test-update-data'*150000
        self.sha=hashlib.sha256(self.payload).hexdigest();name='OG-Studio-Mastering-9.0.0-win-x64.exe'
        self.release=dict(tag_name='v9.0.0',assets=[dict(name=name,browser_download_url=f'https://github.com/{REPO}/releases/download/v9.0.0/{name}',digest='sha256:'+self.sha,size=len(self.payload))]);self.asset=release_asset(self.release,'2.0.2')
        self.tmp=tempfile.TemporaryDirectory(dir=Path(__file__).resolve().parents[1]/'verification');self.folder=Path(self.tmp.name)
    def tearDown(self):self.tmp.cleanup()
    def opener(self,*args,**kw):return Response(self.payload)
    def test_newer_only(self):
        self.assertIsNone(release_asset(self.release,'9.0.0'));self.assertIsNone(release_asset(self.release,'10.0.0'))
        self.release['prerelease']=True;self.assertIsNone(release_asset(self.release,'2.0.2'))
    def test_verified_download_and_cache(self):
        progress=[];path=Path(download(self.asset,self.folder,lambda t,p:progress.append(p),opener=self.opener));self.assertEqual(path.read_bytes(),self.payload);self.assertEqual(progress[-1],100)
        def offline(*args,**kwargs):raise AssertionError('Redownloaded cached update')
        self.assertEqual(download(self.asset,self.folder,opener=offline),str(path))
    def test_checksum_failure_removes_partial(self):
        asset=dict(self.asset,sha256='0'*64)
        with self.assertRaisesRegex(ValueError,'verification failed'):download(asset,self.folder,opener=self.opener)
        self.assertEqual(list(self.folder.iterdir()),[])
    def test_cancellation_removes_partial(self):
        cancel=threading.Event()
        def progress(t,p):
            if p>0:cancel.set()
        with self.assertRaises(InterruptedError):download(self.asset,self.folder,progress,cancel,self.opener)
        self.assertEqual(list(self.folder.iterdir()),[])
    def test_existing_file_preserved(self):
        old=self.folder/self.asset['name'];old.write_bytes(b'existing user file');new=Path(download(self.asset,self.folder,opener=self.opener));self.assertNotEqual(new,old);self.assertEqual(old.read_bytes(),b'existing user file')
    def test_missing_checksum_and_wrong_repo_rejected(self):
        self.release['assets'][0]['digest']=None
        with self.assertRaises(ValueError):release_asset(self.release,'2.0.2')
        self.release['assets'][0]['digest']='sha256:'+self.sha;self.release['assets'][0]['browser_download_url']='https://example.com/update.exe'
        with self.assertRaises(ValueError):release_asset(self.release,'2.0.2')
    def test_incomplete_download(self):
        with self.assertRaises(ValueError):download(self.asset,self.folder,opener=lambda *a,**kw:Response(self.payload[:100]))
        self.assertEqual(list(self.folder.iterdir()),[])
if __name__=='__main__':unittest.main()
