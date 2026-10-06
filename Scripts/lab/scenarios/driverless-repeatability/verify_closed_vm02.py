import json,os,shlex,subprocess,time
from pathlib import Path
r=Path(os.environ['KEYPATH_TRIAL_DIR']).resolve()
owned=json.loads((r/'owned-lease.json').read_text())
body='''import json,subprocess
prl='/Applications/Parallels Desktop.app/Contents/MacOS/prlctl'
p=subprocess.run([prl,'list','--all','--json'],capture_output=True,text=True,check=True,timeout=30)
v=json.loads(p.stdout)
assert not any(x.get('uuid','').strip('{}').lower()==__PROVIDER__ for x in v)
t=json.loads(subprocess.run([prl,'list','-i','64a9db80-0716-4340-ba96-e87108068b58','--json'],capture_output=True,text=True,check=True,timeout=30).stdout);assert len(t)==1 and t[0]['ID']=='64a9db80-0716-4340-ba96-e87108068b58' and t[0]['State']=='stopped' and t[0]['Template']=='yes'
p=subprocess.run(['/Applications/Parallels Desktop.app/Contents/MacOS/prlsrvctl','usb','list','--json'],capture_output=True,text=True,check=True,timeout=30)
f=[x for x in json.loads(p.stdout) if x.get('System name')=='3110000|cafe|4010|full|--|2884855553BC'];assert len(f)==1 and f[0]['Connected-To-Vm']=='NO' and f[0]['Autoconnect-Action']=='ask' and not f[0]['Autoconnect-Vm-Uuid']
print(json.dumps(dict(passed=True,providerAbsent=True,templateStoppedRetained=True,fixture=f)))
'''.replace('__PROVIDER__',repr(owned['provider']))
p=subprocess.run(['ssh','malpern@mini','/opt/homebrew/bin/python3 -I -B -c '+shlex.quote(body)],capture_output=True,text=True,timeout=80)
fd=os.open(r/'independent-provider-cleanup02.json',os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
with os.fdopen(fd,'w')as f:json.dump(dict(actualStatus=p.returncode,stdout=p.stdout,stderr=p.stderr,at=time.time()),f)
print(p.stdout);assert p.returncode==0,p.stderr
