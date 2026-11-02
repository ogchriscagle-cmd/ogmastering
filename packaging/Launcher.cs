using System;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Security.Cryptography;
using System.Text;
using System.Windows.Forms;

[assembly: AssemblyTitle("OG Mastering")]
[assembly: AssemblyProduct("OG Mastering")]
[assembly: AssemblyVersion("1.0.0.0")]
internal static class Launcher {
    static Form CreateSplash(out Label status,out ProgressBar progress) {
        var form=new Form {Text="OG Mastering",ClientSize=new System.Drawing.Size(540,300),StartPosition=FormStartPosition.CenterScreen,FormBorderStyle=FormBorderStyle.None,BackColor=System.Drawing.Color.FromArgb(9,14,24),ShowInTaskbar=true};
        form.Icon=System.Drawing.Icon.ExtractAssociatedIcon(Assembly.GetExecutingAssembly().Location);
        var logo=new PictureBox {Left=30,Top=35,Width=88,Height=88,SizeMode=PictureBoxSizeMode.Zoom,Image=form.Icon.ToBitmap()};form.Controls.Add(logo);
        form.Controls.Add(new Label {Text="OG MASTERING",Left=138,Top=42,Width=380,Height=42,ForeColor=System.Drawing.Color.FromArgb(73,169,255),Font=new System.Drawing.Font("Segoe UI",23,System.Drawing.FontStyle.Bold)});
        form.Controls.Add(new Label {Text="SUNO STUDIO  /  LOCAL AUDIO ENGINE",Left=141,Top=92,Width=360,Height=25,ForeColor=System.Drawing.Color.FromArgb(150,170,195),Font=new System.Drawing.Font("Segoe UI",9)});
        status=new Label {Text="Starting your mastering studio...",Left=32,Top=172,Width=480,Height=30,ForeColor=System.Drawing.Color.White,Font=new System.Drawing.Font("Segoe UI",11)};form.Controls.Add(status);
        progress=new ProgressBar {Left=32,Top=215,Width=476,Height=7,Style=ProgressBarStyle.Marquee};form.Controls.Add(progress);
        form.Controls.Add(new Label {Text="v1.0.0   |   OFFLINE. PRIVATE. YOURS.",Left=32,Top=247,Width=476,Height=20,ForeColor=System.Drawing.Color.FromArgb(115,140,170),Font=new System.Drawing.Font("Segoe UI",9)});
        return form;
    }
    [STAThread] static int Main(string[] args) {
        Form splash = null;
        try {
            Application.EnableVisualStyles();
            bool test = Array.IndexOf(args, "--self-test") >= 0;
            Label label;ProgressBar bar;splash=CreateSplash(out label,out bar);
            if(!test){splash.Show();Application.DoEvents();}
            string target = null;
            for (int i=0;i<args.Length-1;i++) if (args[i]=="--extract-to") target=Path.GetFullPath(args[i+1]);
            using (var file=File.OpenRead(Assembly.GetExecutingAssembly().Location)) {
                if (file.Length<48) throw new InvalidDataException("Incomplete application package.");
                file.Position=file.Length-48;
                var reader=new BinaryReader(file,Encoding.UTF8,true);
                long offset=reader.ReadInt64(); byte[] expected=reader.ReadBytes(32);
                if (Encoding.ASCII.GetString(reader.ReadBytes(8))!="OGPKG001" || offset<0 || offset>=file.Length-48) throw new InvalidDataException("Invalid application package.");
                string hash=BitConverter.ToString(expected).Replace("-","").ToLowerInvariant();
                if (target==null) target=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"OGMastering","1.0.0-"+hash.Substring(0,12));
                string marker=Path.Combine(target,".package-ready");
                bool ready=File.Exists(marker) && File.ReadAllText(marker)==hash && File.Exists(Path.Combine(target,"Launch-App.ps1"));
                if (!ready) {
                    if (Directory.Exists(target) && Directory.GetFileSystemEntries(target).Length>0) throw new IOException("The extraction folder is not empty. Choose a new folder or remove the incomplete OG Mastering cache folder: "+target);
                    Directory.CreateDirectory(target);
                    using(var segment=new SegmentStream(file,offset,file.Length-offset-48)) {
                        label.Text="Checking bundled application files...";Application.DoEvents();
                        using(var sha=SHA256.Create()) { string actual=BitConverter.ToString(sha.ComputeHash(segment)).Replace("-","").ToLowerInvariant(); if(actual!=hash)throw new InvalidDataException("Package checksum failed. Download the EXE again."); }
                        segment.Position=0;
                        using(var zip=new ZipArchive(segment,ZipArchiveMode.Read,true)) {
                            long total=0,done=0;foreach(var entry in zip.Entries) total+=entry.Length;
                            bar.Style=ProgressBarStyle.Continuous;
                            string prefix=Path.GetFullPath(target).TrimEnd(Path.DirectorySeparatorChar)+Path.DirectorySeparatorChar;
                            foreach(var entry in zip.Entries) {
                                string destination=Path.GetFullPath(Path.Combine(target,entry.FullName.Replace('/',Path.DirectorySeparatorChar)));
                                if(!destination.StartsWith(prefix,StringComparison.OrdinalIgnoreCase))throw new InvalidDataException("Unsafe archive path.");
                                if(entry.FullName.EndsWith("/")){Directory.CreateDirectory(destination);continue;}
                                Directory.CreateDirectory(Path.GetDirectoryName(destination));
                                using(var input=entry.Open())using(var output=new FileStream(destination,FileMode.CreateNew,FileAccess.Write))input.CopyTo(output);
                                done+=entry.Length;bar.Value=(int)Math.Min(100,done*100/Math.Max(1,total));label.Text="Preparing application... "+bar.Value+"%";Application.DoEvents();
                            }
                        }
                    }
                    File.WriteAllText(marker,hash);
                }
                string script=Path.Combine(target,test?"Verify-Package.ps1":"Launch-App.ps1");
                var start=new ProcessStartInfo(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows),"System32","WindowsPowerShell","v1.0","powershell.exe"));
                start.Arguments="-NoProfile -STA -ExecutionPolicy Bypass -File \""+script+"\"";
                start.WorkingDirectory=target;start.UseShellExecute=false;start.CreateNoWindow=true;start.WindowStyle=ProcessWindowStyle.Hidden;
                // Test-only environment flags from a parent shell must not hide the real app.
                start.EnvironmentVariables.Remove("OG_MASTERING_TEST");
                {
                    // A fresh per-launch event closes the splash only after WPF renders.
                    string eventName="Local\\OGMastering-"+Guid.NewGuid().ToString("N");
                    using(var rendered=new System.Threading.EventWaitHandle(false,System.Threading.EventResetMode.ManualReset,eventName)) {
                        start.EnvironmentVariables["OG_STARTUP_EVENT"]=eventName;
                        label.Text="Loading controls and audio tools...";bar.Style=ProgressBarStyle.Marquee;Application.DoEvents();
                        using(var process=Process.Start(start)) {
                            if(test){process.WaitForExit();splash.Dispose();return process.ExitCode;}
                            var deadline=DateTime.UtcNow.AddSeconds(90);
                            while(!rendered.WaitOne(30) && !process.HasExited && DateTime.UtcNow<deadline){Application.DoEvents();}
                        }
                    }
                }
                splash.Close();splash.Dispose();splash=null;
            }
            return 0;
        } catch(Exception error) {
            if(splash!=null)splash.Close();
            if(Array.IndexOf(args,"--self-test")>=0){try{File.WriteAllText(Path.Combine(Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location),"launcher-test-error.log"),error.ToString());}catch{}return 1;}
            MessageBox.Show(error.Message,"OG Mastering",MessageBoxButtons.OK,MessageBoxIcon.Error);return 1;
        }
    }
}
internal sealed class SegmentStream:Stream {
    readonly Stream source;readonly long origin,length;long position;
    internal SegmentStream(Stream source,long origin,long length){this.source=source;this.origin=origin;this.length=length;}
    public override bool CanRead{get{return true;}}public override bool CanSeek{get{return true;}}public override bool CanWrite{get{return false;}}
    public override long Length{get{return length;}}public override long Position{get{return position;}set{Seek(value,SeekOrigin.Begin);}}
    public override int Read(byte[] buffer,int offset,int count){source.Position=origin+position;int read=source.Read(buffer,offset,(int)Math.Min(count,length-position));position+=read;return read;}
    public override long Seek(long offset,SeekOrigin kind){long next=(kind==SeekOrigin.Begin?0:kind==SeekOrigin.Current?position:length)+offset;if(next<0||next>length)throw new IOException("Invalid package position.");position=next;return position;}
    public override void Flush(){}public override void SetLength(long value){throw new NotSupportedException();}public override void Write(byte[] buffer,int offset,int count){throw new NotSupportedException();}
}
