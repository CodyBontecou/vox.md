from pathlib import Path
import datetime, hashlib, json, os, shutil, subprocess, sys
root=Path('/private/tmp/vox-apple-signal3-20261108')
base=Path('/private/tmp/vox-pr70-qualification-20261109')
evidence=Path('/Users/codybontecou/dev/vox.md/artifacts/validation/pr70-final-qualification-20261109')
expected='33ac5352465d409e0c25b2220228fac7977e8e40'
sdk=Path('/Users/codybontecou/Library/Android/sdk');adb=sdk/'platform-tools/adb';serial='emulator-5554'
def git(*args):return subprocess.check_output(['git',*args],cwd=root,text=True).strip()
def device(*args):return subprocess.check_output([str(adb),'-s',serial,*args],text=True).strip()
def digest(p):
 h=hashlib.sha256()
 with p.open('rb') as f:
  for chunk in iter(lambda:f.read(1024*1024),b''):h.update(chunk)
 return h.hexdigest()
assert git('rev-parse','HEAD')==expected and not git('status','--porcelain')
assert device('shell','getprop','ro.boot.qemu.avd_name')=='vox-pr70-final-api36-20261109'
assert device('shell','getprop','ro.kernel.qemu')=='1'
artifacts={name:{'path':str(p),'bytes':p.stat().st_size,'sha256':digest(p)} for name,p in {
 'app':root/'apps/android/app/build/outputs/apk/debug/app-debug.apk',
 'tests':root/'apps/android/app/build/outputs/apk/androidTest/debug/app-debug-androidTest.apk',
 'recoveryTests':root/'apps/android/data/build/outputs/apk/androidTest/debug/data-debug-androidTest.apk'}.items()}
preflight={'startedAtUTC':datetime.datetime.now(datetime.timezone.utc).isoformat(),'sourceRevision':expected,'sourceTreeClean':True,'device':{'serial':serial,'avd':device('shell','getprop','ro.boot.qemu.avd_name'),'api':device('shell','getprop','ro.build.version.sdk'),'abi':device('shell','getprop','ro.product.cpu.abi'),'memory':device('shell','cat','/proc/meminfo').splitlines()[0]},'apks':artifacts}
(evidence/'preflight.json').write_text(json.dumps(preflight,indent=2)+'\n')
output=evidence/'model-output';output.mkdir()
env=dict(os.environ,ANDROID_HOME=str(sdk),ANDROID_SERIAL=serial)
with (evidence/'device-test-runner.log').open('w') as log:
 subprocess.run([str(adb),'-s',serial,'logcat','-c'],check=True)
 monitor=subprocess.Popen([str(adb),'-s',serial,'logcat','-v','threadtime','TestRunner:I','*:S'],stdout=log,stderr=subprocess.STDOUT)
 try:
  with (evidence/'producer.log').open('w') as producer:
   result=subprocess.run([sys.executable,str(root/'apps/android/scripts/validate-local-intelligence.py'),'--fixtures',str(base/'fixtures'),'--output',str(output)],cwd=root,env=env,stdout=producer,stderr=subprocess.STDOUT)
 finally:
  monitor.terminate();monitor.wait(timeout=10)
completion={'completedAtUTC':datetime.datetime.now(datetime.timezone.utc).isoformat(),'producerExitCode':result.returncode,'sourceRevision':expected,'sourceTreeCleanAfterRun':not git('status','--porcelain'),'deviceDisposition':'task-owned device retained pending strict validation and evidence publication'}
(evidence/'completion.json').write_text(json.dumps(completion,indent=2)+'\n')
if result.returncode:raise SystemExit('Full producer failed; exact logs retained')
assert git('rev-parse','HEAD')==expected and not git('status','--porcelain')
bundle=evidence/'validation-bundle';bundle.mkdir()
for name in ['instruction-evaluation.json','speaker-evaluation.json','receipt.json']:shutil.copyfile(output/name,bundle/name)
for name in ['apple-instruction-evaluation.json','apple-speaker-evaluation.json']:shutil.copyfile(root/'artifacts/validation/local-intelligence-2026-11-01'/name,bundle/name)
with (evidence/'strict-validation.log').open('w') as log:
 strict=subprocess.run([sys.executable,str(root/'apps/android/scripts/validate-intelligence-evaluations.py'),'--reports',str(bundle)],cwd=root,stdout=log,stderr=subprocess.STDOUT)
completion['strictValidationExitCode']=strict.returncode
receipt=json.loads((output/'receipt.json').read_text())
completion['counts']=receipt['counts'];completion['totalInstrumentationTests']=sum(receipt['counts'].values())
completion['artifactSHA256']={str(p.relative_to(evidence)):digest(p) for p in sorted(evidence.rglob('*')) if p.is_file() and p.name not in {'completion.json','SHA256SUMS.json'}}
(evidence/'completion.json').write_text(json.dumps(completion,indent=2)+'\n')
strict.check_returncode()
print(json.dumps({'sourceRevision':expected,'producerExitCode':result.returncode,'strictValidationExitCode':strict.returncode,'counts':receipt['counts']},indent=2))
