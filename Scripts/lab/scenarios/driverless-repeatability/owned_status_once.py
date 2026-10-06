import hashlib,json,os,re,subprocess,sys,time,datetime
from pathlib import Path
ROOT=Path(os.environ['KEYPATH_TRIAL_DIR']).resolve();c=json.loads((ROOT/'create-result.json').read_bytes());assert c['actualStatus']==0
lease=re.findall(r'^lease_id\t(cbx_[0-9a-f]{12})$',c['stdout'],re.M);assert len(lease)==1;lease=lease[0]
cli=Path('/private/tmp/vm-lab-reusable-setup/bin/vm-lab');assert hashlib.sha256(cli.read_bytes()).hexdigest()=='f8470518428f75590e7ea6f481a6a544f40745f4a881039b9d4ed884231cdc03'
r=subprocess.run([str(cli),'--host','malpern@mini','keypath','status',lease],env=dict(os.environ,VM_LAB_REGISTRY=str(ROOT/'tenants.tsv')),capture_output=True,text=True,timeout=45)
def write(name,v):
 fd=os.open(ROOT/name,os.O_CREAT|os.O_EXCL|os.O_WRONLY|os.O_NOFOLLOW,0o600)
 with os.fdopen(fd,'w') as f:json.dump(v,f);f.write('\n');f.flush();os.fsync(f.fileno())
 fd=os.open(ROOT,os.O_RDONLY);os.fsync(fd);os.close(fd)
write('status-result.json',dict(actualStatus=r.returncode,stdout=r.stdout,stderr=r.stderr,readOnly=True,finishedAtEpoch=time.time()));assert r.returncode==0
assert r.stdout.count('provider_inventory_begin\n')==1 and r.stdout.endswith('provider_inventory_end\n')
pre,inv=r.stdout.split('provider_inventory_begin\n');fields=dict(line.split('\t',1)for line in pre.splitlines());assert fields['lease_id']==lease and fields['owner']=='keypath-installer-lab-v1' and fields['status']=='ready' and fields['provider']=='parallels' and fields.get('tenant_commit',fields.get('keypath_commit'))=='40809975962922f852c4729f2dced76eb7e47dd8' and fields['installer_sha256']=='7ad23b3666b1907eab43f53253758f0b339401c213a53a53649e8def695d0d28'
rows=[line.split()for line in inv.splitlines()if line.split() and line.split()[0]==fields['provider_resource']];assert len(rows)==1
row=rows[0];assert row[1]=='crabbox-'+lease.replace('_','-')+'-'+fields['slug'] and row[2:4]==['running','template'] and row[5:]==['lease='+lease,'slug='+fields['slug'],'keep=true','target=macos']
created=int(fields['created_epoch']);expiry=int(fields['expires_epoch']);assert expiry-created==3600 and time.time()+180<expiry-360
v=dict(lease=lease,provider=fields['provider_resource'],ip=row[4],slug=fields['slug'],createdEpoch=created,manifestExpiresEpoch=expiry,hardCutoffEpoch=expiry-360,cutoffUTC=datetime.datetime.fromtimestamp(expiry-360,datetime.timezone.utc).isoformat(),observedAtEpoch=time.time(),statusActual=0,physicalReleased=False,stageReleased=False)
write('owned-lease.json',v);print(json.dumps(v))
