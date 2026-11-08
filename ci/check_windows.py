import os, pathlib, subprocess, zipfile, hashlib, json, re, shutil

repo=pathlib.Path(__file__).resolve().parents[1]
source=repo/'distributions/t1.2.1/Transcribator-SHCHSM'
out=repo/'windows-evidence';out.mkdir(exist_ok=True)
archive=out/'transcribator-shchsm.zip'
with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED) as z:
 for p in source.rglob('*'):
  if p.is_file():z.write(p,'Transcribator-SHCHSM/'+p.relative_to(source).as_posix())
digest=hashlib.sha256(archive.read_bytes()).hexdigest()
(out/'SHA256SUMS').write_text(digest+'  transcribator-shchsm.zip\n')
expanded=out/'Проверка установки с пробелами'
with zipfile.ZipFile(archive) as z:z.extractall(expanded)
win=expanded/'Transcribator-SHCHSM/windows'
env=os.environ.copy();env.pop('PSMODULEPATH',None);env['SHCHSM_AUTOMATED']='1'
# Exclude runner-preinstalled ffmpeg so the shipped installer downloads its own.
system=pathlib.Path(env['SYSTEMROOT']);env['PATH']=';'.join(str(x) for x in [system/'System32',system,system/'System32/WindowsPowerShell/v1.0'])
checks=[]
def run(bat,args=(),extra=None,tag='run',ok=True):
 e=env.copy();e.update(extra or {})
 command='call "'+str(bat)+'" '+ ' '.join('"'+str(x)+'"' for x in args)
 p=subprocess.run('cmd.exe /d /s /c "'+command+'"',env=e,capture_output=True,timeout=1200)
 (out/(tag+'.log')).write_bytes(p.stdout+b'\nSTDERR\n'+p.stderr)
 if ok and p.returncode!=0:raise AssertionError((tag,p.returncode,p.stdout[-3000:].decode('utf8',errors='replace')))
 if not ok and p.returncode==0:raise AssertionError(tag+' incorrectly succeeded')
 return p

# New runner profile: actual dependencies, model, native Desktop and launcher.
run(win/'1-Install.bat',tag='install')
root=pathlib.Path(env['USERPROFILE'])/'.transcriber-shchsm'
desktop=subprocess.check_output(['powershell.exe','-NoProfile','-Command',"[Console]::OutputEncoding=[Text.UTF8Encoding]::new(); [Environment]::GetFolderPath('Desktop')"]).decode('utf-8-sig').strip()
base=pathlib.Path(desktop)/'Транскрибатор ШЧСМ'
assert (base/'ТРАНСКРИБИРОВАТЬ.bat').exists()
run(base/'ТРАНСКРИБИРОВАТЬ.bat',[repo/'ci/install-check-ru.wav'],tag='transcribe-russian')
texts=list((base/'Готовые тексты').glob('install-check-ru*.txt'));assert texts
text=texts[0].read_text(encoding='utf-8-sig').lower()
for keyword in ['провер','запись','текст','учител','служени']:assert keyword in text,(keyword,text)
shutil.copy2(texts[0],out/'result-ru.txt')
checks+=['fresh-profile install', 'native Desktop launcher', 'actual large-v3-turbo Russian transcription']
before={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in (base/'Готовые тексты').iterdir()}
invalid=out/'invalid-audio.wav';invalid.write_text('This is not audio')
run(base/'ТРАНСКРИБИРОВАТЬ.bat',[invalid],tag='decode-failure',ok=False)
assert before=={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in (base/'Готовые тексты').iterdir()}
checks+=['decode failure returns nonzero; existing results preserved']
engine=root/'bin/whisper-cli.exe'; saved=engine.with_suffix('.saved'); engine.rename(saved)
try:
 engine.write_bytes(b'not an executable')
 run(base/'ТРАНСКРИБИРОВАТЬ.bat',[repo/'ci/install-check-ru.wav'],tag='engine-failure',ok=False)
 assert before=={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in (base/'Готовые тексты').iterdir()}
finally:
 engine.unlink(missing_ok=True); saved.rename(engine)
checks+=['engine failure returns nonzero; existing results preserved']
# Wrong expected hash must fail before engine extraction or model download.
bad=win/'wrong-hash.bat'
s=(win/'1-Install.bat').read_text('utf8')
s=s.replace('b1514ebc099765e39fa37eb780b92a140a94c86bb0b3b3d98226b38825979732','0'*64)
bad.write_bytes(s.replace('\n','\r\n').encode('utf8'))
negative=out/'negative-install';(negative/'bin').mkdir(parents=True)
shutil.copy2(root/'bin/ffmpeg.exe',negative/'bin/ffmpeg.exe')
run(bad,extra={'SHCHSM_TEST_ROOT':str(negative)},tag='bad-engine-hash',ok=False)
assert not (negative/'bin/whisper-cli.exe').exists()
checks+=['wrong engine checksum fails before installation']
(out/'RESULT.json').write_text(json.dumps({'status':'PASS','sha256':digest,'checks':checks,'platform':'GitHub Actions windows-2022 x64','limits':['not a physical user PC','Microsoft runtime preinstalled by runner; missing-runtime recovery not physically tested']},ensure_ascii=False,indent=2))
print(json.dumps({'status':'PASS','sha256':digest,'checks':checks}))
