"""End-to-end check usable from source and the frozen application."""
import json,tempfile
from pathlib import Path
from engine import Engine,CATALOG,genre,validate

def run_tests(output):
    output=Path(output);output.mkdir(parents=True,exist_ok=True)
    engine=Engine()
    assert len(CATALOG)==58
    for index in range(58):validate(genre(index))
    with tempfile.TemporaryDirectory(prefix='python-check-',dir=output) as tmp:
        tmp=Path(tmp);source=tmp/'source.wav';reference=tmp/'reference.wav'
        engine.run(['-y','-f','lavfi','-i','aevalsrc=0.15*sin(2*PI*100*t)+0.12*sin(2*PI*500*t)+0.08*sin(2*PI*3000*t):s=48000:d=5','-ac','2',source])
        engine.run(['-y','-i',source,'-af','treble=g=2',reference])
        analysis=engine.analyze(source);assert analysis['duration']>4
        settings=genre(0);settings.update(Repair=True,NoiseNR=True,Leveler=True,FadeIn=True,FadeOut=True,Glue=15,SatEnabled=True,Excite=10)
        result=engine.master(source,tmp,settings,'both',reference)
        assert len(result['files'])==2 and all(Path(p).stat().st_size>1000 for p in result['files'])
        assert abs(float(result['output']['input_i'])-settings['Loudness'])<1.5
        assert float(result['output']['input_tp'])<=settings['Ceiling']+.15
        assert result['mp3'] and len(result['referenceGains'])==6
        second=engine.master(source,tmp,genre(5),'wav');assert second['files'][0]!=result['files'][0]
        try:validate({'Loudness':float('nan')})
        except ValueError:pass
        else:raise AssertionError('Accepted NaN setting')
        detection=engine.detect(source,analysis['duration']);assert detection['genre'] and detection['vocals']
        (output/'engine-test-results.json').write_text(json.dumps(dict(master=result,detection=detection),indent=2),encoding='utf-8')
    (output/'engine-test.txt').write_text('PASS: 58 presets, bundled FFmpeg, advanced DSP, reference matching, verified WAV + MP3, filename collision protection, offline genre/vocal inference.',encoding='utf-8')

if __name__=="__main__":
    run_tests(Path(__file__).resolve().parents[1]/"verification/python-source-tests")
