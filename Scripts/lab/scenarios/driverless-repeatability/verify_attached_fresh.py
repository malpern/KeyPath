import hashlib,json,os,plistlib,re,shlex,subprocess,time,sys
from pathlib import Path
assert len(sys.argv)==2 and sys.argv[1].replace('-','').isalnum()
R=Path(os.environ['KEYPATH_TRIAL_DIR']).resolve();o=json.loads((R/'owned-lease.json').read_text());i=json.loads((R/'guest-identity.json').read_text());assert time.time()+120<o['hardCutoffEpoch']
cli=Path('/private/tmp/vm-lab-sdk-guestroot-595-regular-candidate/bin/vm-lab');assert hashlib.sha256(cli.read_bytes()).hexdigest()=='8c0f284643db41a40ed2c20af12a5fe576bb4da3e9b59604389657b732d78e11';assert hashlib.sha256((cli.parents[1]/'lib/remote.sh').read_bytes()).hexdigest()=='1ccb6fd8a6b13d2f4a205d6059c0abc454999287acb2fdff7a42c4f01dc6e9fa'
h=subprocess.run(['ssh','malpern@mini',"'/Applications/Parallels Desktop.app/Contents/MacOS/prlsrvctl' usb list --json"],capture_output=True,text=True,timeout=25);assert h.returncode==0
f=[v for v in json.loads(h.stdout) if v.get('System name')=='3110000|cafe|4010|full|--|2884855553BC'];assert len(f)==1 and f[0]['Connected-To-Vm']=='YES' and f[0]['Used-By-Vm-Uuid'].strip('{}').lower()==o['provider'] and f[0]['Autoconnect-Action']=='ask' and f[0]['Autoconnect-Vm-Uuid']==''
body="""import json,os,plistlib,re,subprocess,time
assert os.getuid()==0 and os.stat('/dev/console').st_uid==502
b=subprocess.run(['/usr/sbin/sysctl','-n','kern.boottime'],capture_output=True,text=True,check=True,timeout=5).stdout
assert int(re.search(r'sec = ([0-9]+),',b)[1])==BOOT and time.time()<CUTOFF
v=plistlib.loads(subprocess.run(['/usr/sbin/ioreg','-a','-r','-c','IOHIDDevice'],capture_output=True,check=True,timeout=10).stdout)
def walk(v):
 if isinstance(v,dict):
  if v.get('VendorID')==0xCAFE and v.get('ProductID')==0x4010:yield {k:v.get(k) for k in ('Product','SerialNumber','Transport','PrimaryUsage')}
  for c in v.values():yield from walk(c)
 elif isinstance(v,list):
  for c in v:yield from walk(c)
f=list(walk(v));assert len(f)==1 and f[0]['SerialNumber']=='2884855553BC' and f[0]['Transport']=='USB' and f[0]['PrimaryUsage']==6
print(json.dumps(dict(passed=True,guestDevice=f[0])))
""".replace('BOOT',str(i['bootEpoch'])).replace('CUTOFF',str(o['hardCutoffEpoch']))
payload='true; exec /Library/Frameworks/Python.framework/Versions/3.13/bin/python3.13 -I -B -c '+shlex.quote(body)
g=subprocess.run([str(cli),'--host','malpern@mini','keypath','guest-root',o['lease'],'--','/bin/zsh','-c',payload],env=dict(os.environ,VM_LAB_REGISTRY=str(R/'tenants.tsv')),capture_output=True,text=True,timeout=40);assert g.returncode==0
v=json.loads(g.stdout);assert v['passed'] is True
v.update(lease=o['lease'],providerUUID=o['provider'],fixture=f[0],readOnly=True,actualStatus=g.returncode,observedAtEpoch=time.time())
fd=os.open(R/('attached-'+sys.argv[1]+'.json'),os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
with os.fdopen(fd,'w') as w:json.dump(v,w);w.write('\n');w.flush();os.fsync(w.fileno())
print(json.dumps(v))
