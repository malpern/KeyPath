"""One call, selected diagnostics only. No import-time network or retry."""
import hashlib,json,os,pathlib,selectors,stat,subprocess,time,uuid
import diagnostic_receipt
ROOT=pathlib.Path(__file__).resolve().parent

def collect(command,env,limit=65536,timeout=30):
    """Drain both pipes; stderr retention is bounded and raw bytes never persist."""
    p=subprocess.Popen(command,env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
    streams=selectors.DefaultSelector();streams.register(p.stdout,selectors.EVENT_READ,'stdout');streams.register(p.stderr,selectors.EVENT_READ,'stderr')
    out=bytearray();err=bytearray();overflow=False;deadline=time.monotonic()+timeout
    try:
        while streams.get_map():
            remaining=deadline-time.monotonic()
            if remaining<=0:raise subprocess.TimeoutExpired(command,timeout)
            for key,_ in streams.select(min(remaining,.2)):
                chunk=os.read(key.fileobj.fileno(),8192)
                if not chunk:streams.unregister(key.fileobj);continue
                if key.data=='stderr':
                    if len(err)+len(chunk)>limit:overflow=True
                    err.extend(chunk[:max(0,limit-len(err))])
                else:
                    if len(out)+len(chunk)>8*1024*1024:raise RuntimeError('transport stdout bound exceeded')
                    out.extend(chunk)
        rc=p.wait(timeout=max(.001,deadline-time.monotonic()))
        return rc,bytes(out).decode('utf-8'),None if overflow else bytes(err).decode('utf-8',errors='replace')
    except Exception:
        p.kill();p.wait();raise  # host transport only; guest completion may be unknown
    finally:
        streams.close();p.stdout.close();p.stderr.close()

def persist(directory,sequence,value):
    d=pathlib.Path(directory);s=d.lstat()
    if d!=d.resolve() or not stat.S_ISDIR(s.st_mode) or s.st_uid!=os.getuid() or stat.S_IMODE(s.st_mode)!=0o700:raise RuntimeError('diagnostic journal refused')
    p=d/('transport-'+str(sequence).zfill(6)+'.json');fd=os.open(p,os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,0o600)
    try:
        raw=(json.dumps(value,sort_keys=True)+'\n').encode()
        if os.write(fd,raw)!=len(raw):raise RuntimeError('diagnostic journal write refused')
        os.fsync(fd)
    finally:os.close(fd)
    fd=os.open(d,os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW)
    try:os.fsync(fd)
    finally:os.close(fd)

class Lab:
    def __init__(self,directory,host):self.directory=directory;self.host=host;self.sequence=0;self.last_diagnostic=None;self.stage=lambda:None;self.failures=[]
    def __call__(self,lease,verb,*args):
        nonce=uuid.uuid4().hex;env=dict(os.environ,VM_LAB_TRANSPORT_DIAGNOSTIC_NONCE=nonce)
        command=[str(ROOT/'bin/vm-lab'),'--host',self.host,'keypath',verb,lease,*args]
        self.sequence+=1;begin=time.monotonic()
        label=self.stage()
        allowed=('target','processes.table','processes.arguments','identity.process','identity.arguments','identity.hash','alive','preflight.console','preflight.signature','preflight.hash','preflight.target-executable','preflight.target-uid','preflight.target-hash','preflight.target-arguments','preflight.python','capture.preflight','capture.observe')
        allowed=tuple(k+suffix for k in allowed for suffix in ('','.identity','.command'))+('startup.worker-discovery','snapshot','parent-ready')
        label=label if label in allowed else None
        def metadata(v):
            if 'receiptSHA256' in v:v['frameReceiptSHA256']=v.pop('receiptSHA256')
            v.update(sequence=self.sequence,verb=verb if verb in ('status','guest-root') else 'other',readStage=label,elapsedSeconds=max(0,time.monotonic()-begin))
            v['receiptSHA256']=hashlib.sha256(json.dumps(v,sort_keys=True,separators=(',',':')).encode()).hexdigest()
            return v
        try:
            rc,out,err=collect(command,env)
            if not 0<=rc<=255:raise RuntimeError('host transport signal refusal')
            selected=diagnostic_receipt.receipt(err,nonce,rc)
        except Exception as e:
            selected=dict(version=1,nonce=nonce,classification='host-transport-observation-incomplete',diagnosticValid=False,exceptionClass=type(e).__name__ if type(e).__name__ in ('TimeoutExpired','RuntimeError','OSError','UnicodeDecodeError') else 'Exception')
            metadata(selected)
            if len(self.failures)<8:self.failures.append(selected)
            self.last_diagnostic=selected;persist(self.directory,self.sequence,selected)
            raise RuntimeError('owned guest transport observation incomplete; no replay') from None
        metadata(selected)
        if rc and len(self.failures)<8:self.failures.append(selected)
        self.last_diagnostic=selected;persist(self.directory,self.sequence,selected)
        if rc:raise RuntimeError('owned guest operation failed: '+verb+' exit='+str(rc)+'; diagnostics suppressed')
        return out
