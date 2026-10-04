import hashlib
import json
import os
import pathlib
import shlex
import tempfile
import types
import unittest
from unittest import mock
import fresh_capture as f
import measurement as m
from test_measurement import Fake, SCOPE

class CaptureTests(unittest.TestCase):
    def test_serial_parent_then_new_capture_before_any_snapshot(self):
        g=Fake();r=g.run()
        self.assertTrue(r['passed']);self.assertEqual(g.calls[:4],['preflight','start','capture','snapshot'])
        self.assertEqual(r['targetCleanupOwner'],'root; no target signal in no-input measurement')
    def guest(self, observations):
        g=types.SimpleNamespace(parent=10,parent_args=['/parent','--headless'],exe='/parent',account=SCOPE.account,target_identity=None)
        g.identity=lambda *a:dict(pid=10);g.calls=[];g.elapsed=0
        def run(command):g.calls.append(('launch',command));return json.dumps(dict(requestedAt=100))
        def read(command,stage):
            g.calls.append(('observe',command))
            v=observations.pop(0)
            if isinstance(v,Exception):raise v
            return json.dumps(v)
        g.run=run;g.read=read;g.wall=lambda:100+g.elapsed;g.mono=lambda:g.elapsed
        g.sleep=lambda s:setattr(g,'elapsed',g.elapsed+s)
        return g
    def observation(self):
        target=Fake().target();target['observedAt']=100
        return dict(target=target,identity=dict(pid=50,uid=502,nonce='target',executable=SCOPE.target_executable,binarySHA256=SCOPE.target_sha256,rawArguments=SCOPE.target_executable))
    def test_null_then_ready_single_claim_launch_and_exact_binding(self):
        g=self.guest([None,self.observation()]);claims=[]
        t=f.capture(g,SCOPE,claims.append,m.target_check,g.mono,g.wall,g.sleep)
        self.assertEqual(t['pid'],50);self.assertEqual(len(claims),1);self.assertEqual([x[0] for x in g.calls],['launch','observe','observe'])
        self.assertEqual(g.target_identity['binarySHA256'],SCOPE.target_sha256)
        with self.assertRaisesRegex(RuntimeError,'replay'):f.capture(g,SCOPE,claims.append,m.target_check,g.mono,g.wall,g.sleep)
        self.assertEqual(len(g.calls),3)
    def test_never_ready_deadline_and_error_have_no_relaunch(self):
        for rows,expected in ([None]*45,'deadline'),([ValueError('bad JSON')],'bad JSON'):
            g=self.guest(rows);claims=[]
            with self.assertRaisesRegex((RuntimeError,ValueError),expected):f.capture(g,SCOPE,claims.append,m.target_check,g.mono,g.wall,g.sleep)
            self.assertEqual(len(claims),1);self.assertEqual(sum(x[0]=='launch' for x in g.calls),1)
            self.assertIsNone(g.target_identity);self.assertLessEqual(g.elapsed,8.00001)
    def test_bad_focus_or_identity_refuses_without_another_read(self):
        for field,value in [('focusLost',True),('active',False),('identity',None)]:
            o=self.observation()
            if field=='identity':o['identity']['binarySHA256']='0'*64
            else:o['target'][field]=value
            g=self.guest([o]);claims=[]
            with self.assertRaises(RuntimeError):f.capture(g,SCOPE,claims.append,m.target_check,g.mono,g.wall,g.sleep)
            self.assertEqual(len(g.calls),2);self.assertIsNone(g.target_identity)
    def test_claim_crosses_cutoff_no_launch_and_no_replay(self):
        from dataclasses import replace
        g=self.guest([]);scope=replace(SCOPE,deadline=101)
        def claim(_):g.elapsed=2
        with self.assertRaisesRegex(RuntimeError,'cutoff'):f.capture(g,scope,claim,m.target_check,g.mono,g.wall,g.sleep)
        self.assertEqual(g.calls,[])
        with self.assertRaisesRegex(RuntimeError,'replay'):f.capture(g,scope,claim,m.target_check,g.mono,g.wall,g.sleep)
    def test_claim_exclusive_private_and_durable(self):
        with tempfile.TemporaryDirectory() as d:
            f.private_claim(d,dict(state='claimed'))
            p=pathlib.Path(d)/'target-launch-claim.json';self.assertEqual(p.stat().st_mode&0o777,0o600)
            with self.assertRaises(FileExistsError):f.private_claim(d,dict(state='changed'))
            self.assertEqual(json.loads(p.read_bytes()),dict(state='claimed'))
    def test_worker_requires_new_typed_permission_provenance(self):
        v=Fake().report();m.worker_check(v,(20,502,'worker'),Fake().wall())
        for field,value in [('inputAccessSource',None),('inputAccessSource',1),('inputAccessSource','legacy'),('accessibility',False),('effectiveInputAccess',1)]:
            with self.assertRaisesRegex(RuntimeError,'permission'):m.worker_check(dict(v,**{field:value}),(20,502,'worker'),Fake().wall())

class ActualBodyTests(unittest.TestCase):
    def test_actual_generated_public_launch_and_poll_no_input_or_second_launch(self):
        self.exercise()
    def test_actual_prelaunch_hash_parent_uid_ownership_and_expiry_refuse(self):
        for fault in ('hash','parent','uid','mode','link','expired'):
            with self.subTest(fault=fault):self.exercise(fault)
    def test_actual_generated_raw_space_path_rejects_extra_arguments(self):
        for fault in ('target-extra','target-prefix','target-quoted'):
            with self.subTest(fault=fault):self.exercise(fault)
    def exercise(self,fault=None):
        with tempfile.TemporaryDirectory(dir='/private/tmp') as directory:
            home=pathlib.Path(directory);exe=home/'Applications/VM Lab Rig Target.app/Contents/MacOS/RigTarget';exe.parent.mkdir(parents=True);exe.write_bytes(b'inert target');exe.chmod(0o755)
            for directory_path in (home/'Applications',exe.parents[2],exe.parents[1],exe.parent):directory_path.chmod(0o755)
            original_lstat=pathlib.Path.lstat;original_stat=os.stat;original_fstat=os.fstat;calls=[];live=[];now=[100]
            def owned(s):
                fields=('st_dev','st_ino','st_mode','st_uid','st_gid','st_nlink','st_size','st_mtime_ns','st_ctime_ns')
                values={key:getattr(s,key) for key in fields};values['st_uid']=502
                return types.SimpleNamespace(**values)
            def lstat(p):
                s=owned(original_lstat(p))
                if fault=='mode' and p==exe:s.st_mode|=0o020
                if fault=='link' and p==exe:s.st_nlink=2
                return s
            def stat(p,*args,**kwargs):
                if str(p)=='/dev/console':return types.SimpleNamespace(st_uid=502)
                return original_stat(p,*args,**kwargs)
            def run(args,**kwargs):
                calls.append(args)
                if args[0]=='/usr/sbin/sysctl':out='{ sec = 90, usec = 0 }'
                elif args[0]=='/usr/bin/codesign':
                    out=''
                    if fault=='expired':now[0]=1000
                elif args[:3]==['/bin/ps','-ww','-axo']:out='10 502 /parent\n'+''.join(str(pid)+' 502 '+str(exe)+'\n' for pid in live)
                elif args[:3]==['/bin/ps','-ww','-p']:
                    out='/parent --foreign' if fault=='parent' else ('/parent --headless' if args[3]=='10' else (str(exe)+' --foreign' if fault=='target-extra' else ('foreign '+str(exe) if fault=='target-prefix' else (shlex.quote(str(exe)) if fault=='target-quoted' else str(exe)))))
                elif args[0]=='/usr/bin/open':
                    self.assertEqual(args,['/usr/bin/open','-n',str(exe.parents[2])]);live.append(50);out=''
                else:raise AssertionError(args)
                return types.SimpleNamespace(stdout=out,returncode=0)
            value=dict(home=str(home),bootEpoch=90,deadline=900,targetExecutable=str(exe),targetSHA256=hashlib.sha256(exe.read_bytes()).hexdigest(),parent=dict(pid=10,arguments=['/parent','--headless']),parentExecutable='/parent')
            if fault=='hash':value['targetSHA256']='0'*64
            from contextlib import redirect_stdout
            import io
            def execute(op):
                out=io.StringIO()
                with mock.patch.dict(os.environ,HOME=str(home)),mock.patch.object(os,'getuid',return_value=501 if fault=='uid' else 502),mock.patch.object(os,'stat',side_effect=stat),mock.patch.object(os,'fstat',side_effect=lambda fd:owned(original_fstat(fd))),mock.patch.object(pathlib.Path,'lstat',lstat),mock.patch('subprocess.run',side_effect=run),mock.patch('time.time',side_effect=lambda:now[0]),mock.patch('sys.argv',['inert',json.dumps(value),op]),redirect_stdout(out):
                    exec(compile(f.TARGET_CODE,'actual-generated-fresh-capture','exec'),{})
                return json.loads(out.getvalue())
            if fault and not fault.startswith('target-'):
                with self.assertRaises(RuntimeError):execute('launch')
                self.assertFalse(any(x[0]=='/usr/bin/open'for x in calls));return
            self.assertEqual(execute('preflight')['binarySHA256'],value['targetSHA256'])
            launched=execute('launch');value.update(launched)
            self.assertIsNone(execute('observe'))
            nonce='12345678-1234-4234-8234-123456789012';control=home/('rig-target-control-50-'+nonce);control.mkdir(mode=0o700)
            t=Fake().target();t.update(pid=50,nonce=nonce,observedAt=100,commandPath=str(control/'command.json'))
            (home/'rig-target.json').write_text(json.dumps(t));(home/'rig-target.json').chmod(0o644)
            if fault and fault.startswith('target-'):
                with self.assertRaisesRegex(RuntimeError,'fresh capture guard refused'):execute('observe')
                self.assertEqual(calls[-1],['/bin/ps','-ww','-p','50','-o','args='])
                self.assertEqual(sum(x[0]=='/usr/bin/open'for x in calls),1)
                return
            r=execute('observe');self.assertEqual(r['identity']['pid'],50)
            self.assertEqual(r['identity']['rawArguments'],str(exe))
            self.assertEqual(sum(x[0]=='/usr/bin/open'for x in calls),1)
            with self.assertRaises(RuntimeError):execute('launch')
            self.assertEqual(sum(x[0]=='/usr/bin/open'for x in calls),1)

if __name__=='__main__':unittest.main()
