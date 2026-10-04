"""Explicit prepared baseline adapter; frozen legacy identity rules stay unchanged."""
import os,stat
import hashlib,importlib.util,json,pathlib,re,sys,uuid
SOURCE=pathlib.Path('/private/tmp/keypath-guest-identity/Scripts/experiments/session-runtime/guest-identity.py')
SOURCE_SHA='dcafa2ad7ce7e94d779a4a332bf9a2231ed13f171cc5671ca132b8539fcb8637'
BASELINE_SHA='7285826ed9f6f845599fdce653c0adf47d6fac7bfc5551234d44a45144bd07a6'
PROFILE={'account':'keypathqa_438d6abc','uid':502,'home':'/Users/keypathqa_438d6abc'}
def require(v,m):
 if not v:raise RuntimeError(m)
require(hashlib.sha256(SOURCE.read_bytes()).hexdigest()==SOURCE_SHA,'shared identity source changed')
spec=importlib.util.spec_from_file_location('timeout_prepared_shared_identity',SOURCE)
shared=importlib.util.module_from_spec(spec);sys.modules[spec.name]=shared;spec.loader.exec_module(shared)
def valid_uuid(value):
 try:return type(value)is str and str(uuid.UUID(value))==value
 except (ValueError,AttributeError):return False
def private(path,limit=4096):
 path=pathlib.Path(path)
 require(path.is_absolute() and path==path.resolve(),'prepared binding canonical path required')
 anchor=pathlib.Path('/private/tmp');parent=path.parent
 while parent!=anchor:
  require(anchor in parent.parents,'prepared binding private namespace required')
  st=parent.lstat();require(stat.S_ISDIR(st.st_mode) and st.st_uid==os.getuid() and stat.S_IMODE(st.st_mode)==0o700,'prepared binding private ancestor required');parent=parent.parent
 fd=os.open(path,os.O_RDONLY|os.O_NOFOLLOW|os.O_NONBLOCK)
 try:
  before=os.fstat(fd);require(stat.S_ISREG(before.st_mode) and before.st_uid==os.getuid() and before.st_nlink==1 and stat.S_IMODE(before.st_mode)==0o600 and 0<before.st_size<=limit,'prepared binding private metadata required')
  raw=os.read(fd,limit+1)
  meta=lambda v:(v.st_dev,v.st_ino,v.st_mode,v.st_uid,v.st_gid,v.st_size,v.st_nlink,v.st_mtime_ns,v.st_ctime_ns)
  require(len(raw)==before.st_size and meta(before)==meta(os.fstat(fd))==meta(path.lstat()),'prepared binding changed')
  return raw
 finally:os.close(fd)
def baseline(path,sha):
 require(sha==BASELINE_SHA,'reviewed prepared baseline pin required')
 raw=private(path,1048576);require(hashlib.sha256(raw).hexdigest()==sha,'prepared baseline changed')
 value=json.loads(raw,object_pairs_hook=shared.unique_keys)
 require(type(value)is dict and set(value)=={'version','profile','pythonSHA256','trees','requireProductFree'} and type(value['version'])is int and value['version']==1 and value['profile']==PROFILE and type(value['profile']['uid'])is int and value['requireProductFree']is True and value['pythonSHA256']=='64b562069c287361189cf3a821e552a3b043af178c8e988804b45dc3ecf846e5' and type(value['trees'])is dict and set(value['trees'])=={'cli','app'},'prepared baseline schema changed')
 return value
class PreparedIdentity(shared.GuestIdentity):
 def __post_init__(self):
  require(self.account==PROFILE['account'] and type(self.uid)is int and self.uid==502 and type(self.lease)is str and re.fullmatch('cbx_[0-9a-f]{12}',self.lease) and type(self.provider_uuid)is str and valid_uuid(self.provider_uuid) and type(self.boot_epoch)is int and self.boot_epoch>0 and type(self.receipt_path)is str and type(self.receipt_sha256)is str and re.fullmatch('[0-9a-f]{64}',self.receipt_sha256),'prepared identity tuple refused')
 def guard(self):
  return super().guard()+' && test "$(date +%s)" -lt '+str(self.cutoff)
 def verify(self,pilot,lease):
  require(__import__('time').time()<self.cutoff,'prepared cutoff reached')
  baseline(self.baseline_path,self.baseline_sha)
  return super().verify(pilot,lease)
def load(receipt,receipt_sha,inventory,inventory_sha,cutoff):
 require(type(cutoff)is int and cutoff>0,'explicit prepared cutoff required')
 baseline(inventory,inventory_sha)
 raw=private(receipt);require(type(receipt_sha)is str and re.fullmatch('[0-9a-f]{64}',receipt_sha) and hashlib.sha256(raw).hexdigest()==receipt_sha,'fresh declared identity pin changed')
 value=json.loads(raw,object_pairs_hook=shared.unique_keys)
 require(type(value)is dict and set(value)=={'version','lease','providerUUID','account','uid','home','bootEpoch'} and type(value['version'])is int and value['version']==1 and value['home']==PROFILE['home'],'fresh identity schema refused')
 identity=PreparedIdentity(value['account'],value['uid'],value['lease'],value['providerUUID'],value['bootEpoch'],str(receipt),receipt_sha)
 object.__setattr__(identity,'cutoff',cutoff)
 object.__setattr__(identity,'baseline_path',str(inventory));object.__setattr__(identity,'baseline_sha',inventory_sha)
 return identity
def admit_provider(output,identity,cutoff,now):
 require(type(cutoff)is int and now<cutoff,'prepared cutoff reached')
 shared.verify_provider(output,identity.lease,identity.provider_uuid,now)
 fields=dict(row.split('\t',1) for row in output.split('provider_inventory_begin',1)[0].splitlines())
 require(cutoff<=int(fields['expires_epoch']),'declared cutoff exceeds provider expiry')
def bind_pilot(pilot,identity,cutoff):
 # Scope the existing imported rig cache to this already verified identity; the
 # frozen shared constructor/defaults are not changed or globally patched.
 pilot.identity._current=identity
 original=pilot.lab
 def bounded(*values):
  require(__import__('time').time()<cutoff,'lease dispatch cutoff reached')
  result=original(*values)
  require(__import__('time').time()<cutoff,'lease response crossed cutoff; no replay')
  return result
 pilot.lab=bounded
 return pilot
