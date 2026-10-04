#!/usr/bin/env python3
"""Read final KeyPath identity's own passive API report in an owned guest."""
import argparse,importlib.machinery,json,os,pathlib,sys,time,uuid
RIG=pathlib.Path(os.environ.get('VM_LAB_RIG_ROOT','/private/tmp/vm-lab-hid-rig'))
if str(RIG) not in ('/private/tmp/vm-lab-hid-rig','/private/tmp/vm-lab-guest-identity'):raise RuntimeError('unreviewed rig source root')
pilot=importlib.machinery.SourceFileLoader('session_pilot',str(RIG/'rig/physical-baseline.py')).load_module()
identity_module=importlib.machinery.SourceFileLoader('guest_identity',str(pathlib.Path(__file__).with_name('guest-identity.py'))).load_module()
def check(lease,identity=None):
 identity=identity or identity_module.GuestIdentity();identity.verify(pilot,lease);app=identity.app
 nonce=str(uuid.uuid4());path=identity.home+'/keypath-capability-'+nonce+'.json'
 pilot.lab(lease,'guest-root','--','/bin/zsh','-lc',
  identity.guard()+' && launchctl asuser '+str(identity.uid)+' sudo -H -u '+identity.account+' open -g -n "'+app+'" --args --session-capabilities --session-report '+path+' --session-nonce '+nonce)
 for attempt in range(20):
  time.sleep(.2)
  identity.verify(pilot,lease)
  values=pilot.objects(pilot.observe(lease,'guest-root','--','/bin/zsh','-lc','true; cat '+path+' 2>/dev/null; printf "\\n"; true'))
  if len(values)==1:
   value=values[0]
   if value.get('nonce')!=nonce or value.get('uid')!=identity.uid or value.get('state')!='capabilities' or not 0<=time.time()-(value.get('timestamp',0)+978307200)<5:
    raise RuntimeError('independent final-identity report mismatch')
   identity.verify(pilot,lease)
   pilot.lab(lease,'guest-root','--','/bin/zsh','-lc',identity.guard()+' && /bin/rm -f '+path)
   return value
 raise RuntimeError('independent KeyPath capability report unavailable')
if __name__=='__main__':
 parser=argparse.ArgumentParser();parser.add_argument('lease');identity_module.add_arguments(parser);args=parser.parse_args()
 print(json.dumps(check(args.lease,identity_module.from_arguments(args))))
