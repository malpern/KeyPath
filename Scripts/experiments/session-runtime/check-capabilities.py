#!/usr/bin/env python3
"""Read final KeyPath identity's own passive API report in an owned guest."""
import importlib.machinery,json,pathlib,sys,time,uuid
RIG=pathlib.Path('/private/tmp/vm-lab-hid-rig')
pilot=importlib.machinery.SourceFileLoader('session_pilot',str(RIG/'rig/physical-baseline.py')).load_module()
APP='/Users/keypathqa/Applications/KeyPath.app'
def check(lease):
 nonce=str(uuid.uuid4());path='/Users/keypathqa/keypath-capability-'+nonce+'.json'
 pilot.lab(lease,'guest-root','--','/bin/zsh','-lc',
  'true; test "$(stat -f %Su /dev/console)" = keypathqa && launchctl asuser 501 sudo -H -u keypathqa open -g -n "'+APP+'" --args --session-capabilities --session-report '+path+' --session-nonce '+nonce+'; true')
 for attempt in range(20):
  time.sleep(.2)
  values=pilot.objects(pilot.observe(lease,'guest-root','--','/bin/zsh','-lc','true; cat '+path+' 2>/dev/null; printf "\\n"; true'))
  if len(values)==1:
   value=values[0]
   if value.get('nonce')!=nonce or value.get('uid')!=501 or value.get('state')!='capabilities' or not 0<=time.time()-(value.get('timestamp',0)+978307200)<5:
    raise RuntimeError('independent final-identity report mismatch')
   pilot.lab(lease,'guest-root','--','/bin/rm','-f',path)
   return value
 raise RuntimeError('independent KeyPath capability report unavailable')
if __name__=='__main__':print(json.dumps(check(sys.argv[1])))
