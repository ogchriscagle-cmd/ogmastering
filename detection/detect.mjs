import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { spawnSync } from 'node:child_process';
import { pathToFileURL } from 'node:url';

const setup=process.argv[2]==='--setup';
const request=setup ? null : JSON.parse(fs.readFileSync(process.argv[2],'utf8').replace(/^\uFEFF/,''));
const runtime=setup ? process.argv[3] : request.runtime;
const require=createRequire(path.join(runtime,'package.json'));
const loaded=await import(pathToFileURL(require.resolve('@huggingface/transformers')).href);
const {pipeline,env}=loaded.pipeline ? loaded : loaded.default;
env.cacheDir=path.join(runtime,'models');
env.allowRemoteModels=setup;
env.backends.onnx.wasm.numThreads=2;
const status=message=> { if(request) fs.writeFileSync(request.status,JSON.stringify({message})); else process.stdout.write(message+'\n'); };
try {
  status(setup?'Downloading CLAP model':'Loading local genre and vocal model');
  const classifier=await pipeline('zero-shot-audio-classification','Xenova/clap-htsat-unfused',{dtype:'q8',device:'cpu',session_options:{intraOpNumThreads:2},progress_callback:p=>{if(p.status==='initiate')status('Loading '+p.file);}});
  if(setup){fs.writeFileSync(path.join(runtime,'ready.json'),JSON.stringify({model:'Xenova/clap-htsat-unfused',dtype:'q8'}));await classifier.dispose();process.exit(0);}
  const catalog=JSON.parse(fs.readFileSync(request.catalog,'utf8').replace(/^\uFEFF/,''));
  const genres=catalog.filter(x=>!['Suno Optimized','Manual / neutral'].includes(x.Name)).map(x=>x.Name);
  const vocalLabels=['music with singing vocals','music with rapping or spoken vocals','instrumental music without any human voice'];
  const genrePrompts=genres.map(g=>`This audio is a ${g} song.`);
  const texts=[...genrePrompts,...vocalLabels.map(x=>`This audio is ${x}.`)];
  const sums=new Float64Array(texts.length);let used=0;
  const positions=[0.15,0.45,0.75].map(p=>Math.max(0,Math.min(request.duration-10,request.duration*p)));
  const unique=[...new Set(positions.map(p=>Math.round(p)))];
  for(let i=0;i<unique.length;i++){
    status(`Listening to excerpt ${i+1}/${unique.length}: genre and vocals`);
    const decoded=spawnSync(request.ffmpeg,['-hide_banner','-loglevel','error','-nostdin','-ss',String(unique[i]),'-i',request.source,'-t','10','-map','0:a:0','-ac','1','-ar','48000','-f','f32le','pipe:1'],{maxBuffer:8*1024*1024,windowsHide:true});
    if(decoded.status!==0)throw new Error('Audio excerpt decoding failed: '+decoded.stderr.toString().slice(-300));
    const data=decoded.stdout;if(data.length<4800*4)continue;
    const audio=new Float32Array(data.buffer.slice(data.byteOffset,data.byteOffset+data.length));
    let energy=0;for(const v of audio)energy+=v*v;if(energy/audio.length<1e-8)continue;
    // Separate candidate sets prevent genre labels from competing with vocal labels.
    const gs=await classifier(audio,genrePrompts,{hypothesis_template:'{}'});
    const vs=await classifier(audio,texts.slice(genres.length),{hypothesis_template:'{}'});
    for(const item of gs)sums[genrePrompts.indexOf(item.label)]+=item.score;
    for(const item of vs)sums[texts.indexOf(item.label)]+=item.score;
    used++;
  }
  if(!used)throw new Error('No audible excerpts could be classified.');
  const ranked=genres.map((name,i)=>({name,score:sums[i]/used})).sort((a,b)=>b.score-a.score);
  const singing=sums[genres.length]/used,rap=sums[genres.length+1]/used,instrumental=sums[genres.length+2]/used;
  const vocals=singing+rap;
  const voice= vocals>=0.7?'Likely vocals':instrumental>=0.7?'Likely instrumental':'Uncertain';
  const uncertain=ranked[0].score<0.12 || ranked[0].score-ranked[1].score<0.025;
  const result={model:'Xenova/clap-htsat-unfused',excerpts:used,genre:ranked[0].name,genreUncertain:uncertain,topGenres:ranked.slice(0,3),vocals:voice,vocalScore:vocals,instrumentalScore:instrumental,note:'Relative model scores, not calibrated probabilities. Short excerpts may miss vocals or mix genres.'};
  fs.writeFileSync(request.output,JSON.stringify(result));status('Detection complete');await classifier.dispose();
}catch(error){status('Detection failed: '+error.message);process.stderr.write(error.stack+'\n');process.exitCode=1;}
