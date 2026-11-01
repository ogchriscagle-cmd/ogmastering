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
    [STAThread] static int Main(string[] args) {
        Form splash = null;
        try {
            Application.EnableVisualStyles();
            bool test = Array.IndexOf(args, "--self-test") >= 0;
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
                    splash=new Form {Text="OG Mastering",Width=440,Height=150,StartPosition=FormStartPosition.CenterScreen,FormBorderStyle=FormBorderStyle.FixedDialog,ControlBox=false};
                    var label=new Label {Text="Preparing OG Mastering for first use...",Left=20,Top=20,Width=390};
                    var bar=new ProgressBar {Left=20,Top=57,Width=390,Height=16}; splash.Controls.Add(label);splash.Controls.Add(bar);splash.Show();Application.DoEvents();
                    using(var segment=new SegmentStream(file,offset,file.Length-offset-48)) {
                        label.Text="Checking bundled application files...";Application.DoEvents();
                        using(var sha=SHA256.Create()) { string actual=BitConverter.ToString(sha.ComputeHash(segment)).Replace("-","").ToLowerInvariant(); if(actual!=hash)throw new InvalidDataException("Package checksum failed. Download the EXE again."); }
                        segment.Position=0;
                        using(var zip=new ZipArchive(segment,ZipArchiveMode.Read,true)) {
                            long total=0,done=0;foreach(var entry in zip.Entries) total+=entry.Length;
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
                    splash.Close();splash=null;
                }
                string script=Path.Combine(target,test?"Verify-Package.ps1":"Launch-App.ps1");
                var start=new ProcessStartInfo(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows),"System32","WindowsPowerShell","v1.0","powershell.exe"));
                start.Arguments="-NoProfile -STA -ExecutionPolicy Bypass -File \""+script+"\"";
                start.WorkingDirectory=target;start.UseShellExecute=false;start.CreateNoWindow=true;start.WindowStyle=ProcessWindowStyle.Hidden;
                // Test-only environment flags from a parent shell must not hide the real app.
                start.EnvironmentVariables.Remove("OG_MASTERING_TEST");
                using(var process=Process.Start(start)){if(test){process.WaitForExit();return process.ExitCode;}}
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
