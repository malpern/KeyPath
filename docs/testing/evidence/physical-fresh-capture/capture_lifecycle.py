"""Explicit old-capture retirement after retained timeout and fail-open proof."""
import json
import shlex
import fresh_capture

RETIRE_CODE = fresh_capture.TARGET_CODE.split('guard()\nif op',1)[0] + r'''
import signal
old=v['oldTarget'];pid=old['pid'];nonce=old['nonce']
ck(type(pid)is int and pid>0 and type(old['uid'])is int and old['uid']==502 and type(nonce)is str and str(__import__('uuid').UUID(nonce)).upper()==nonce.upper())
archive=home/('rig-target-retired-'+str(pid)+'-'+nonce+'.json')
def target_process():
 rows=[x for x in processes() if x[0]==pid]
 if not rows:return False
 ck(rows==[(pid,502,str(exe))])
 args=subprocess.run(['/bin/ps','-ww','-p',str(pid),'-o','args='],capture_output=True,text=True,check=True,timeout=5).stdout.strip()
 ck(args==str(exe));return True
def read_old():
 fd=os.open(report,os.O_RDONLY|os.O_NOFOLLOW|os.O_NONBLOCK)
 try:
  s=os.fstat(fd);ck(stat.S_ISREG(s.st_mode) and s.st_uid==502 and s.st_nlink==1 and not s.st_mode&0o7022 and 0<s.st_size<=262144)
  raw=os.read(fd,262145);meta=lambda x:(x.st_dev,x.st_ino,x.st_mode,x.st_uid,x.st_nlink,x.st_size,x.st_mtime_ns,x.st_ctime_ns)
  ck(len(raw)==s.st_size and meta(s)==meta(os.fstat(fd))==meta(report.lstat()))
 finally:os.close(fd)
 def unique(pairs):
  out={}
  for k,value in pairs:ck(k not in out);out[k]=value
  return out
 t=json.loads(raw,object_pairs_hook=unique)
 ck(type(t)is dict and set(t)==set(['aDowns', 'active', 'combinedSessionControl', 'combinedSessionControlDropped', 'combinedSessionControlJournal', 'commandConsumedSequence', 'commandPath', 'commandSequence', 'commandStatus', 'controlA', 'downs', 'flagsChangedDropped', 'flagsChangedJournal', 'focusLost', 'focusedMode', 'held', 'modeTransitions', 'modeTransitionsDropped', 'modifiers', 'monotonicAt', 'nonce', 'observedAt', 'pid', 'qDowns', 'requestedResponderFocused', 'secureInputEnabled', 'secureLength', 'secureSampleMatches', 'secureTest', 'text', 'uid', 'ups', 'windowKey']) and all(t.get(k)==old[k] for k in ('pid','uid','nonce','commandPath')))
 ck(all(type(t.get(k))is bool for k in ('active','windowKey','focusLost','secureTest','secureSampleMatches','requestedResponderFocused','secureInputEnabled','combinedSessionControl')))
 ck(all(type(t.get(k))is list and len(t[k])<=limit and all(type(row)is dict for row in t[k])for k,limit in (('flagsChangedJournal',512),('combinedSessionControlJournal',512),('modeTransitions',64))))
 ck(t.get('held')==[] and type(t.get('modifiers'))is int and t['modifiers']==0 and t.get('combinedSessionControl')is False)
 ck(all(type(t.get(k))is int and t[k]>=old[k] for k in ('downs','ups','qDowns','aDowns')))
 ck(type(t.get('observedAt'))in(int,float) and math.isfinite(t['observedAt']) and old['observedAt']<=t['observedAt']<=time.time())
 return t,raw,meta(s),meta
guard();paths();parent();ck(not os.path.lexists(archive) and target_process())
t,raw,signature,meta=read_old()
ck(time.time()-t['observedAt']<3 and all(t.get(k)is wanted for k,wanted in (('active',True),('windowKey',True),('focusLost',False),('requestedResponderFocused',True),('secureTest',False),('secureInputEnabled',False))))
ck(t.get('focusedMode')=='normal')
guard();ck(target_process());ck(time.time()<v['deadline'] and os.getuid()==502 and os.stat('/dev/console').st_uid==502)
os.kill(pid,signal.SIGTERM)  # One owned signal after the durable host retirement claim.
end=time.monotonic()+5
while True:
 guard();alive=target_process();ck(time.monotonic()<=end)
 if not alive:break
 time.sleep(min(.1,max(0,end-time.monotonic())))
# Dead-target JSON is historical retained evidence, never live liveness.
t,raw,signature,meta=read_old();guard();ck(not target_process())
fd=os.open(archive,os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,0o600)
try:ck(os.write(fd,raw)==len(raw));os.fsync(fd)
finally:os.close(fd)
fd=os.open(home,os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW)
try:os.fsync(fd)
finally:os.close(fd)
guard();ck(not target_process() and meta(report.lstat())==signature)
os.unlink(report)
fd=os.open(home,os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW)
try:os.fsync(fd)
finally:os.close(fd)
guard();ck(not os.path.lexists(report))
print(json.dumps(dict(target=t,archive=str(archive),exited=True,termAttempted=True,reportRemoved=True)))
'''


def retire(guest, scope, old_target, claim):
    if getattr(guest,'capture_retire_claimed',False):
        raise RuntimeError('capture retirement replay refused')
    if not guest.target_identity or tuple(guest.target_identity.get(k) for k in ('pid','uid','nonce')) != tuple(old_target.get(k) for k in ('pid','uid','nonce')):
        raise RuntimeError('capture retirement identity refused')
    value=fresh_capture.payload(guest,scope)
    value['oldTarget']={k:old_target[k] for k in ('pid','uid','nonce','commandPath','observedAt','downs','ups','qDowns','aDowns')}
    guest.capture_retire_claimed=True
    claim(dict(state='old-target-retirement-claimed',target=value['oldTarget'],parentPID=guest.parent,deadline=scope.deadline))
    command=('launchctl asuser 502 sudo -H -u '+shlex.quote(guest.account)
             +' /Library/Frameworks/Python.framework/Versions/3.13/bin/python3.13 -I -B -c '
             +shlex.quote(RETIRE_CODE)+' '+shlex.quote(json.dumps(value,sort_keys=True))+' retire')
    result=json.loads(guest.run(command))
    if type(result)is not dict or set(result)!= {'target','archive','exited','termAttempted','reportRemoved'} or not all(result.get(k)is True for k in ('exited','termAttempted','reportRemoved')):
        raise RuntimeError('capture retirement completion refused')
    expected=scope.home+'/rig-target-retired-'+str(old_target['pid'])+'-'+old_target['nonce']+'.json'
    if result['archive']!=expected or tuple(result['target'].get(k)for k in ('pid','uid','nonce'))!=tuple(old_target[k]for k in ('pid','uid','nonce')):
        raise RuntimeError('capture retirement completion identity refused')
    return result
