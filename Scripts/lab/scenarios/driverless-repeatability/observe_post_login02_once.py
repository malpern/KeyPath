import hashlib,importlib.util,json,os,sys,time
from pathlib import Path
ROOT=Path(os.environ['KEYPATH_TRIAL_DIR']).resolve()
assert len(sys.argv)==2 and sys.argv[1] in ('identity','readiness')
label=sys.argv[1];owned=json.loads((ROOT/'owned-lease.json').read_bytes());assert time.time()+180<owned['hardCutoffEpoch']
base=Path('/private/tmp/keypath-artifact-stage-owned-modes/rig');name='observe-prepared-session.py' if label=='identity' else 'readiness.py'
wanted='83fb457af8eb265637e6f9f195071f7b62bc735eb029c180d3243a8fa8ef2c57' if label=='identity' else '93d216a0ae96bd224582542ad6fce849fae0eee031418862766224c33f01c595'
assert hashlib.sha256((base/name).read_bytes()).hexdigest()==wanted
cli=Path('/private/tmp/vm-lab-sdk-guestroot-595-regular-candidate/bin/vm-lab');assert hashlib.sha256(cli.read_bytes()).hexdigest()=='8c0f284643db41a40ed2c20af12a5fe576bb4da3e9b59604389657b732d78e11'
assert hashlib.sha256((cli.parents[1]/'lib/remote.sh').read_bytes()).hexdigest()=='1ccb6fd8a6b13d2f4a205d6059c0abc454999287acb2fdff7a42c4f01dc6e9fa'
sys.path.insert(0,str(base));spec=importlib.util.spec_from_file_location('fresh_observer',base/name);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
T=m.Transport;m.Transport=lambda host,tenant,lease:T(host,tenant,lease,cli=cli)
os.environ['VM_LAB_REGISTRY']=str(ROOT/'tenants.tsv')
args=[str(base/name),owned['lease'],'--host','malpern@mini','--tenant','keypath']
if label=='identity':args+=['--descriptor-receipt','/private/tmp/keypath-runtime-baseline-438d/account-descriptor.json','--descriptor-sha','3e00545730546b8a36cdae8c580d717640017e4c053cd9239268f4aff4fcee78']
else:args+=['--identity-receipt',str(ROOT/'guest-identity.json'),'--identity-sha',hashlib.sha256((ROOT/'guest-identity.json').read_bytes()).hexdigest()]
args+=['--inventory-receipt','/private/tmp/keypath-runtime-baseline-438d/inventory-python-pinned.json','--inventory-sha','7285826ed9f6f845599fdce653c0adf47d6fac7bfc5551234d44a45144bd07a6','--session-receipt','/private/tmp/keypath-438d6abc-session-setup/state.json','--session-sha','ea4c4c50b623d520de8dbb322f090bb696e4c42eda749d0afee495066d3fcfe9','--journal',str(ROOT/(label+'-post-login03-state.json'))]
sys.argv=args;sys.exit(m.main())
