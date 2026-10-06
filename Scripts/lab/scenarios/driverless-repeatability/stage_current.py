"""Trial-local caller of the existing owned UID502 installer, bound to signed bd7809dc1.
No historical packet edits, no installation replay, no guest permission bypass.
"""
import base64,hashlib,importlib.util,json,os,secrets,sys,time,types,uuid
from pathlib import Path
from guest_command import execute
R=Path(os.environ['KEYPATH_TRIAL_DIR']).resolve()
A=Path('/private/tmp/keypath-caps-checkpoint-bd7809dc1-clean-artifact')
SOURCE=Path('/private/tmp/vm-lab-reusable-setup/rig/artifact-stage.py')
SHORT=Path('/private/tmp/vm-lab-terminal-stage-d9fc-candidate/short_stage.py')
MAIN='1f215c470af8c7cdc5b4dd390efe0315762ef713720de347bb50f5db11ab8cc8'
ZIP='51c0dae837bbc26f416330e68ddeebab1143c4a0465c9ed60036afe469e0dcc0'
def require(v,why):
 if not v:raise RuntimeError(why)
def sha(raw):return hashlib.sha256(raw).hexdigest()
def module(path,name,wanted):
 raw=path.read_bytes();require(sha(raw)==wanted,'source hash changed')
 spec=importlib.util.spec_from_file_location(name,path);v=importlib.util.module_from_spec(spec);spec.loader.exec_module(v);return v
m=module(SOURCE,'owned_installer','9fc9fdc386d6bf2aa52434a2858fcdd44b304480dfa9c940a5115d74dc46181a')
s=module(SHORT,'short_program_loader','d19330a279f641b4d4b1aebb00d2fa4ebc60110c883e7b8b187e9da1af60fc17')
# Only the new caller's module instance is bound to current artifact facts.
m.PRODUCT=A/'keypath-caps-mutation-checkpoint-clean.zip'
m.PRODUCT_COMMIT='bd7809dc1da9b814ac00c826e676c2622d9ab4bd';m.PRODUCT_SHA=ZIP;m.PRODUCT_SIZE=97758815;m.MAIN_SHA=MAIN
m.RIG=Path('/private/tmp/keypath-caps-runtime-live-01/rpath/rig-tools-clean.zip')
m.RIG_SHA='b41a82211230384a9915b7e02699ad40d2268832c7fcaa65b1bfb30a8cb26dba';m.RIG_SIZE=36296
m.TARGET_SHA='5fb5e05e8f26954f1b4121cdb949f689cff9db325795ce51167a3f998044ced3'
m.FOCUS_SHA='da0ac107b311359c971db88392b7b6c95f7af6712f845778ae1d3ccc8b6150fb'
m.effective_expiry=lambda scope:scope['expiresEpoch']
def write(name,v):
 fd=os.open(R/name,os.O_CREAT|os.O_EXCL|os.O_WRONLY|os.O_NOFOLLOW,0o600)
 with os.fdopen(fd,'w') as f:json.dump(v,f,sort_keys=True);f.write('\n');f.flush();os.fsync(f.fileno())
def inputs():
 owned=json.loads((R/'owned-lease.json').read_text());ident=json.loads((R/'guest-identity.json').read_text())
 require(ident['lease']==owned['lease'] and ident['providerUUID']==owned['provider'] and ident['uid']==502 and ident['home']=='/Users/keypathqa_438d6abc','fresh ownership refused')
 require(time.time()+240<owned['hardCutoffEpoch'],'cutoff reserve refused')
 require(sha((A/'artifact-manifest.json').read_bytes())=='148c0b9bee66024d891aa3d9159974c202624298561d6af313c982eb070a83be','new artifact manifest changed')
 manifest=json.loads((A/'artifact-manifest.json').read_bytes())
 require(manifest['sourceCommit']=='bd7809dc1da9b814ac00c826e676c2622d9ab4bd' and manifest['packagedMainSHA256']==MAIN and (A/'KeyPath.app/Contents/MacOS/KeyPath').stat().st_size==107202336 and manifest['archiveSHA256']==ZIP and manifest['archiveSizeBytes']==97758815 and manifest['strictSignatureVerified'] and not manifest['hostInstalled'],'current artifact authority refused')
 require((A/'KeyPath.app/Contents/MacOS/KeyPath').stat().st_size==107202336 and sha((A/'KeyPath.app/Contents/MacOS/KeyPath').read_bytes())==MAIN,'current packaged main changed')
 scope=dict(ident,expiresEpoch=owned['hardCutoffEpoch'])
 return owned,ident,scope

def main():
 require(len(sys.argv)==3 and sys.argv[1] in ('preflight','install'),'phase/unique label required')
 phase,label=sys.argv[1:];owned,ident,scope=inputs()
 marker=uuid.uuid4().hex;token=secrets.token_hex(32)
 if phase=='install':
  require(json.loads((R/'connection02-verified.json').read_text())=={'passed':True,'stage':'complete'},'verified transfer prerequisite')
  reconciliation=json.loads((R/'install-absence02-result.json').read_text());require(reconciliation['actualStatus']==0 and json.loads(reconciliation['stdout'])=={'destinationsAbsent':True,'stagingPaths':[]},'previous attempt mutation not reconciled')
 if phase=='preflight':payload=m.ROUTE_MARKER
 else:
  product=m.read_file(m.PRODUCT,ZIP,120000000);require(len(product)==97758815,'artifact size changed')
  rig=m.read_file(m.RIG,m.RIG_SHA,1000000);require(len(rig)==m.RIG_SIZE,'rig archive size changed')
  require(sha((m.ROOT/'public_account_observer.py').read_bytes())=='a4317cdd70ec1f8d24d0a9857c5c9780d9ef3994e8c117966a47c5aaed70b7a7','observer source changed')
  m.zip_guard(product,{"KeyPath.app"},set())
  m.zip_guard(rig,{"VM Lab Rig Target.app","secure-focus"},set())
  payload=product
 product_server=m.OneShotArtifactServer(payload,'10.211.55.2',token)
 program_server=None
 try:
  if phase=='preflight':body=m.build_route_guest(scope,marker,product_server.url,token)
  else:body=m.build_guest(scope,ident,marker,base64.b64encode(rig).decode(),uuid.uuid4().hex,product_server.url,token)
  compile(body,"<actual-dispatch>","exec")
  raw=body.encode();program_token=secrets.token_hex(32)
  program_server=m.OneShotArtifactServer(raw,'10.211.55.2',program_token)
  command=s.launcher(m,scope,raw,program_server.url,program_token)
  # A failed read-only route claim can be followed by a distinct claim;
  # the exclusive install-intent is never replayable.
  write(label+'-install-intent.json' if phase=='install' else label+'-route-intent.json',dict(phase=phase,lease=owned['lease'],providerUUID=owned['provider'],boot=ident['bootEpoch'],cutoff=scope['expiresEpoch'],artifactSHA=ZIP,programSHA=sha(raw),noReplay=True))
  product_server.start();program_server.start()
  result=execute(label,command)
  require(product_server.used and product_server.completed and program_server.used and program_server.completed,'owned transfers incomplete')
  rows=result.rstrip('\n').splitlines();require(len(rows)==2 and rows[-1]==('PUBLIC_ROUTE_COMPLETE_' if phase=='preflight' else 'PUBLIC_ARTIFACTS_COMPLETE_')+marker,'result framing refused')
  value=json.loads(rows[0]);require(value.pop('marker')==marker,'result marker mismatch')
  if phase=='preflight':require(value=={'passed':True,'stage':'complete'},'read-only route refused')
  else:require(value==dict(installed=True,uid=502,bootEpoch=ident['bootEpoch'],mainSHA256=MAIN,targetSHA256=m.TARGET_SHA,focusSHA256=m.FOCUS_SHA),'installed facts refused')
  write(label+'-verified.json',value);print(json.dumps(value))
 finally:
  if program_server:
   write(label+'-transfer-status.json',dict(programUsed=program_server.used,programCompleted=program_server.completed,productUsed=product_server.used,productCompleted=product_server.completed))
   program_server.close()
  product_server.close()
if __name__=='__main__':main()
