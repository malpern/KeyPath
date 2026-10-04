"""One normal LS target launch after the admitted foreground parent; no input."""
import json
import pathlib
import shlex
import time
import uuid

TARGET_CODE = r'''import hashlib,json,math,os,pathlib,re,shlex,stat,subprocess,sys,time
v=json.loads(sys.argv[1]);op=sys.argv[2]
home=pathlib.Path(v['home']);exe=home/'Applications/VM Lab Rig Target.app/Contents/MacOS/RigTarget';app=exe.parents[2]
report=home/'rig-target.json'
def ck(value):
 if not value:raise RuntimeError('fresh capture guard refused')
def guard():
 ck(os.getuid()==502 and os.environ.get('HOME')==str(home) and os.stat('/dev/console').st_uid==502 and time.time()<v['deadline'])
 boot=subprocess.run(['/usr/sbin/sysctl','-n','kern.boottime'],capture_output=True,text=True,check=True,timeout=5).stdout
 m=re.search(r'sec = ([0-9]+),',boot);ck(m and int(m[1])==v['bootEpoch'] and time.time()<v['deadline'])
def paths():
 ck(str(exe)==v['targetExecutable'])
 for p in (home,home/'Applications',app,app/'Contents',app/'Contents/MacOS'):
  s=p.lstat();ck(p==p.resolve() and stat.S_ISDIR(s.st_mode) and s.st_uid==502 and not s.st_mode&0o7022)
 fd=os.open(exe,os.O_RDONLY|os.O_NOFOLLOW|os.O_NONBLOCK)
 try:
  s=os.fstat(fd);ck(stat.S_ISREG(s.st_mode) and s.st_uid==502 and s.st_nlink==1 and s.st_mode&0o111 and not s.st_mode&0o7022)
  h=hashlib.sha256()
  while True:
   b=os.read(fd,1048576)
   if not b:break
   h.update(b)
  meta=lambda x:(x.st_dev,x.st_ino,x.st_mode,x.st_uid,x.st_nlink,x.st_size,x.st_mtime_ns,x.st_ctime_ns)
  ck(meta(s)==meta(os.fstat(fd))==meta(exe.lstat()) and h.hexdigest()==v['targetSHA256'])
 finally:os.close(fd)
 subprocess.run(['/usr/bin/codesign','--verify','--deep','--strict','-R=anchor apple generic and certificate leaf[subject.OU] = "X2RKZ5TG99"',str(app)],stdin=subprocess.DEVNULL,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,check=True,timeout=20)
def processes():
 raw=subprocess.run(['/bin/ps','-ww','-axo','pid=,uid=,comm='],capture_output=True,text=True,check=True,timeout=5).stdout
 ck(len(raw)<262144);rows=[]
 for line in raw.splitlines():
  a=line.split(maxsplit=2);ck(len(a)==3 and a[0].isdigit() and a[1].isdigit());rows.append((int(a[0]),int(a[1]),a[2]))
 return rows
def parent():
 p=v['parent'];ck(type(p['pid'])is int and p['pid']>0)
 rows=processes();ck([x for x in rows if x[0]==p['pid']]==[(p['pid'],502,v['parentExecutable'])])
 raw=subprocess.run(['/bin/ps','-ww','-p',str(p['pid']),'-o','args='],capture_output=True,text=True,check=True,timeout=5).stdout.strip()
 ck(shlex.split(raw)==p['arguments'])
def absent():
 ck(not any(pathlib.PurePosixPath(x[2]).name=='RigTarget' for x in processes()) and not os.path.lexists(report))
guard()
if op in ('preflight','launch'):
 paths();absent()
 if op=='launch':
  parent();guard();requested=time.time()
  # One dispatch, no -g, no input, no args, no fallback or mutation retry.
  subprocess.run(['/usr/bin/open','-n',str(app)],stdin=subprocess.DEVNULL,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,check=True,timeout=8)
  guard();print(json.dumps(dict(requestedAt=requested)))
 else:
  guard();print(json.dumps(dict(executable=str(exe),binarySHA256=v['targetSHA256'])))
elif op=='observe':
 parent();guard()
 if not os.path.lexists(report):print('null')
 else:
  fd=os.open(report,os.O_RDONLY|os.O_NOFOLLOW|os.O_NONBLOCK)
  try:
   s=os.fstat(fd);ck(stat.S_ISREG(s.st_mode) and s.st_uid==502 and s.st_nlink==1 and not s.st_mode&0o7022 and 0<s.st_size<=65536)
   raw=os.read(fd,65537);meta=lambda x:(x.st_dev,x.st_ino,x.st_mode,x.st_uid,x.st_nlink,x.st_size,x.st_mtime_ns,x.st_ctime_ns)
   ck(len(raw)==s.st_size and meta(s)==meta(os.fstat(fd))==meta(report.lstat()))
  finally:os.close(fd)
  def unique(pairs):
   out={}
   for k,value in pairs:ck(k not in out);out[k]=value
   return out
  t=json.loads(raw,object_pairs_hook=unique);ck(type(t)is dict and type(t.get('pid'))is int and t['pid']>0 and type(t.get('uid'))is int and t['uid']==502 and type(t.get('nonce'))is str)
  ck(str(__import__('uuid').UUID(t['nonce'])).upper()==t['nonce'].upper())
  stamp=t.get('observedAt');ck(type(stamp)in(int,float) and math.isfinite(stamp) and v['requestedAt']<=stamp<=time.time() and time.time()-stamp<3)
  rows=processes();ck([x for x in rows if pathlib.PurePosixPath(x[2]).name=='RigTarget']==[(t['pid'],502,str(exe))])
  args=subprocess.run(['/bin/ps','-ww','-p',str(t['pid']),'-o','args='],capture_output=True,text=True,check=True,timeout=5).stdout.strip();ck(args==str(exe))
  command=home/('rig-target-control-'+str(t['pid'])+'-'+t['nonce']);s=command.lstat()
  ck(command==command.resolve() and stat.S_ISDIR(s.st_mode) and s.st_uid==502 and stat.S_IMODE(s.st_mode)==0o700 and t.get('commandPath')==str(command/'command.json'))
  parent();guard();print(json.dumps(dict(target=t,identity=dict(pid=t['pid'],uid=502,nonce=t['nonce'],executable=str(exe),binarySHA256=v['targetSHA256'],rawArguments=args))))
else:raise RuntimeError('fresh capture operation refused')
'''


def payload(guest, scope):
    value = dict(home=scope.home, bootEpoch=scope.boot_epoch, deadline=scope.deadline,
                 targetExecutable=scope.target_executable, targetSHA256=scope.target_sha256)
    if guest.parent is not None:
        value.update(parentExecutable=guest.exe,
                     parent=dict(pid=guest.parent, arguments=guest.parent_args))
    return value


def command(guest, value, operation):
    return ('launchctl asuser 502 sudo -H -u ' + shlex.quote(guest.account)
            + ' /Library/Frameworks/Python.framework/Versions/3.13/bin/python3.13 -I -B -c '
            + shlex.quote(TARGET_CODE) + ' ' + shlex.quote(json.dumps(value, sort_keys=True))
            + ' ' + shlex.quote(operation))


def preflight(guest, scope):
    return json.loads(guest.read(command(guest, payload(guest, scope), 'preflight'), 'capture.preflight'))


def capture(guest, scope, claim, target_check, monotonic=time.monotonic, wall=time.time, sleep=time.sleep):
    if getattr(guest, 'capture_claimed', False):
        raise RuntimeError('fresh capture replay refused')
    guest.identity(guest.parent, guest.parent_args)
    value = payload(guest, scope)
    guest.capture_claimed = True
    claim(dict(state='fresh-target-launch-claimed', lease=scope.lease,
               parentPID=guest.parent, targetExecutable=scope.target_executable,
               targetSHA256=scope.target_sha256, deadline=scope.deadline))
    if wall() >= scope.deadline:
        raise RuntimeError('lease dispatch cutoff reached')
    launched = json.loads(guest.run(command(guest, value, 'launch')))
    if type(launched) is not dict or set(launched) != {'requestedAt'} or type(launched['requestedAt']) not in (int, float):
        raise RuntimeError('fresh capture launch receipt refused')
    value['requestedAt'] = launched['requestedAt']
    deadline = monotonic() + 8
    while True:
        if monotonic() >= deadline or wall() >= scope.deadline:
            raise RuntimeError('fresh capture startup deadline')
        observed = json.loads(guest.read(command(guest, value, 'observe'), 'capture.observe'))
        if monotonic() > deadline or wall() >= scope.deadline:
            raise RuntimeError('fresh capture startup deadline')
        if observed is not None:
            if type(observed) is not dict or set(observed) != {'target', 'identity'}:
                raise RuntimeError('fresh capture observation refused')
            binding = target_check(observed['target'], wall(), uid=scope.uid)
            identity = observed['identity']
            if tuple(identity.get(k) for k in ('pid', 'uid', 'nonce')) != binding or identity.get('executable') != scope.target_executable or identity.get('binarySHA256') != scope.target_sha256:
                raise RuntimeError('fresh capture identity refused')
            guest.target_identity = identity
            return observed['target']
        sleep(min(.2, deadline - monotonic(), scope.deadline - wall()))


def private_claim(directory, value):
    """Exclusive durable host intent before the sole target launch dispatch."""
    import os
    path = pathlib.Path(directory) / 'target-launch-claim.json'
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    try:
        raw = (json.dumps(value, sort_keys=True) + '\n').encode()
        if os.write(fd, raw) != len(raw):
            raise RuntimeError('fresh capture claim write refused')
        os.fsync(fd)
    finally:
        os.close(fd)
    fd = os.open(directory, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)
