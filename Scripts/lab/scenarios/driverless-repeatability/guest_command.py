"""Journal one explicit guest command for this restart trial; no mutation retry."""
import hashlib,json,os,shlex,subprocess,sys,time
from pathlib import Path
R=Path(os.environ['KEYPATH_TRIAL_DIR']).resolve()
CLI=Path('/private/tmp/vm-lab-sdk-guestroot-595-regular-candidate/bin/vm-lab')
def execute(label, command):
 assert label.replace('-','').isalnum()
 o=json.loads((R/'owned-lease.json').read_text())
 assert time.time()+120<o['hardCutoffEpoch']
 assert hashlib.sha256(CLI.read_bytes()).hexdigest()=='8c0f284643db41a40ed2c20af12a5fe576bb4da3e9b59604389657b732d78e11'
 assert hashlib.sha256((CLI.parents[1]/'lib/remote.sh').read_bytes()).hexdigest()=='1ccb6fd8a6b13d2f4a205d6059c0abc454999287acb2fdff7a42c4f01dc6e9fa'
 def write(name,v):
  fd=os.open(R/name,os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,0o600)
  with os.fdopen(fd,'w')as f:json.dump(v,f);f.write('\n');f.flush();os.fsync(f.fileno())
 write(label+'-intent.json',dict(lease=o['lease'],command=command,at=time.time(),noReplay=True))
 p=subprocess.run([str(CLI),'--host','malpern@mini','keypath','guest-root',o['lease'],'--','/bin/zsh','-c','true; '+command],env=dict(os.environ,VM_LAB_REGISTRY=str(R/'tenants.tsv')),capture_output=True,text=True,timeout=45)
 write(label+'-result.json',dict(actualStatus=p.returncode,stdout=p.stdout,stderr=p.stderr,at=time.time()))
 if p.returncode:raise RuntimeError('guest command failed: '+label+' status '+str(p.returncode))
 return p.stdout
if __name__=='__main__':
 print(execute(sys.argv[1],sys.argv[2]))
