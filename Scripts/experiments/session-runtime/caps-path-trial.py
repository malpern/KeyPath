#!/usr/bin/env python3
"""Fixture-scoped Caps Lock -> F18 feasibility, owned guest only; no product policy change."""
import importlib.machinery,json,pathlib,re,shlex,subprocess,sys,time
ROOT=pathlib.Path(__file__).resolve().parents[3];RIG=pathlib.Path('/private/tmp/vm-lab-hid-rig')
pilot=importlib.machinery.SourceFileLoader('caps_pilot',str(RIG/'rig/physical-baseline.py')).load_module()
lease=sys.argv[1];sha=sys.argv[2]
matching=json.dumps({'VendorID':51966,'ProductID':16400,'SerialNumber':'2884855553BC'})
base='true; test "$(stat -f %Su /dev/console)" = keypathqa && launchctl asuser 501 sudo -H -u keypathqa /usr/bin/hidutil property --matching '+shlex.quote(matching)
record={'passed':False,'lease':lease,'scope':'owned guest / verified physical fixture','binarySHA256':sha,'cases':[]}
def read():return pilot.observe(lease,'guest-root','--','/bin/zsh','-lc',base+' --get UserKeyMapping; true').strip()
def empty(value):
 rows=value.splitlines()
 if len(rows)<2 or rows[0].split()!=['RegistryID','Key','Value']:return False
 return re.fullmatch(r'[0-9a-fA-F]+\s+UserKeyMapping\s+(?:\(null\)|\(\s*\))', '\n'.join(rows[1:])) is not None
def write(value):return pilot.lab(lease,'guest-root','--','/bin/zsh','-lc',base+' --set '+shlex.quote(json.dumps({'UserKeyMapping':value}))+'; true')
dest=ROOT/'evidence/session-runtime'/f'{lease}-caps-path-{int(time.time())}.json';changed=False
try:
 record['usb']=pilot.verify_usb(lease);record['mappingBefore']=read()
 if not empty(record['mappingBefore']):raise RuntimeError('existing mapping is not confirmed empty; refuse replacement')
 changed=True;record['setResult']=write([{'HIDKeyboardModifierMappingSrc':0x700000039,'HIDKeyboardModifierMappingDst':0x70000006d}]);record['mappingAfter']=read()
 for mode in ['remap','hrm-tap','hrm-hold']:
  subprocess.run([sys.executable,str(RIG/'rig/prepare-target.py'),lease,'--account','keypathqa'],check=True,stdout=subprocess.DEVNULL)
  result=subprocess.run([sys.executable,str(ROOT/'Scripts/experiments/session-runtime/physical-trial.py'),lease,'--label','caps-f18-'+mode,'--mode',mode,'--caps-via-f18','--expected-input','1','--binary-sha',sha],capture_output=True,text=True)
  values=pilot.objects(result.stdout);record['cases'].append({'mode':mode,'exit':result.returncode,'result':values})
  print(json.dumps(record['cases'][-1]),flush=True)
  if result.returncode:raise RuntimeError('physical Caps Lock trial did not pass')
 record['passed']=True
except Exception as error:record['error']=str(error)
finally:
 if changed:
  try:record['clearResult']=write([]);record['mappingRestored']=empty(read())
  except Exception as error:record.update(passed=False,cleanupError=str(error),mappingRestored=False)
 if not record.get('mappingRestored'):record['passed']=False
 dest.write_text(json.dumps(record,indent=2)+'\n');print(json.dumps({'passed':record['passed'],'evidence':str(dest),'mappingRestored':record.get('mappingRestored')}))
sys.exit(0 if record['passed'] else 79)
