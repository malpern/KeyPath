import ast,json,pathlib,subprocess,unittest
RIG=pathlib.Path('/private/tmp/vm-lab-guest-identity')
IDENTITY=pathlib.Path('/private/tmp/keypath-guest-identity/Scripts/experiments/session-runtime/guest-identity.py')
HARNESS=pathlib.Path('/private/tmp/keypath-d8-readonly-transport-candidate/Scripts/experiments/session-runtime/held-secure-acceptance.py')
def shell_function(path,name):
 text=path.read_text();start=text.index(name+'() {');end=text.index('\n}',start)+2;return text[start:end]
def generated_read():
 tree=ast.parse(HARNESS.read_text());cls=next(n for n in tree.body if isinstance(n,ast.ClassDef) and n.name=='Guest')
 read=next(n for n in cls.body if isinstance(n,ast.FunctionDef) and n.name=='read')
 ns={'require':lambda v,m:None if v else (_ for _ in ()).throw(RuntimeError(m))};exec(compile(ast.Module(body=[read],type_ignores=[]),'actual-Guest.read','exec'),ns)
 # Actual selected tuple shape, public metadata only. Frozen source guard method
 # is called on an inert object rather than invoking verify/provider.
 guard=next(n for n in ast.walk(ast.parse(IDENTITY.read_text())) if isinstance(n,ast.FunctionDef) and n.name=='guard')
 import shlex
 gn={'shlex':shlex};exec(compile(ast.Module(body=[guard],type_ignores=[]),'actual-identity.guard','exec'),gn)
 from types import SimpleNamespace
 i=SimpleNamespace(account='keypathqa_438d6abc',uid=502,home='/Users/keypathqa_438d6abc',boot_epoch=1791140719)
 g=gn['guard'](i)+' && test "$(date +%s)" -lt 1791154292'
 calls=[];obj=SimpleNamespace(READ_STAGES=('identity.arguments',),check_account=lambda:None,guest_identity=SimpleNamespace(guard=lambda:g),lease='cbx_012345abcdef',pilot=SimpleNamespace(observe=lambda *v:calls.append(v)))
 ns['read'](obj,'/bin/ps -ww -p 3697 -o args=','identity.arguments')
 return calls[0],g
class RoundTrip(unittest.TestCase):
 def test_actual_remote_printf_q_and_provider_forwarding_preserve_exact_argv(self):
  args,guard=generated_read();body=args[-1]
  remote=shell_function(RIG/'bin/vm-lab','remote');guest=shell_function(RIG/'lib/remote.sh','guest_root')
  # Both source functions are executed unmodified. The only transport is a
  # local shell function called ssh; the provider is another local function.
  payload='''owned_manifest(){ print -r -- inert; }
field(){ case "$2" in status)print ready;; expires_epoch)print 9999999999;; provider)print parallels;; provider_resource)print 01234567-0123-4123-8123-0123456789ab;; esac; }
now_epoch(){ print 1; }
die(){ print -u2 refused; return 1; }
provider_stub(){ printf '%s\\0' "$@"; }
KEYPATH_LAB_PRLCTL=provider_stub
'''+guest+'\nguest_root "$@"\n'
  import tempfile
  with tempfile.TemporaryDirectory(dir='/private/tmp') as d:
   p=pathlib.Path(d)/'payload';p.write_text(payload)
   bash='''FORWARDED_SETTINGS=()
host=inert
emit_remote_payload(){ cat "$PAYLOAD"; }
ssh(){ /bin/zsh -c "${@: -1}"; }
'''+remote+'\nremote "$@"\n'
   import os
   r=subprocess.run(['/bin/bash','-c',bash,'inert',args[0],*args[2:]],env=dict(os.environ,PAYLOAD=str(p)),capture_output=True,check=False)
   self.assertEqual(r.returncode,0,r.stderr)
   actual=r.stdout.decode().split('\0')[:-1]
   self.assertEqual(actual,['exec','01234567-0123-4123-8123-0123456789ab','--','/bin/zsh','-lc',body])
 def test_actual_guard_false_never_reaches_ps_and_cannot_produce_255(self):
  args,guard=generated_read();body=args[-1]
  # Functions are inert stand-ins for selected public guest observations.
  prefix='''id(){ print 502; }; dscl(){ print 'NFSHomeDirectory: /Users/keypathqa_438d6abc'; }; stat(){ case "$2" in %Su)print keypathqa_438d6abc;; %u)print 502;; esac; }; sysctl(){ print '{ sec = 1791140719, usec = 0 }'; }; date(){ print 1; };
'''
  for accepted in (True,False):
   script=prefix+('' if accepted else 'id(){ print 999; };')+body.replace('/bin/ps -ww -p 3697 -o args=',"printf KEYPATH_INERT_ARGS")
   r=subprocess.run(['/bin/zsh','-lc',script],capture_output=True,text=True)
   self.assertEqual(r.returncode,0 if accepted else 1)
   self.assertEqual(r.stdout,'KEYPATH_INERT_ARGS' if accepted else '')
if __name__=='__main__':unittest.main()
