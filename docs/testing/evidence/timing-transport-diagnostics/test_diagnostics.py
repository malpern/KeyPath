import pathlib
import subprocess
import tempfile
import unittest
import diagnostic_receipt as d

ROOT=pathlib.Path(__file__).parent
NONCE='a'*32


def function(path,name):
    text=path.read_text();start=text.index(name+'() {');end=text.index('\n}\n',start)+3
    return text[start:end]

class Tests(unittest.TestCase):
    def outer(self,producer=0,ssh=0,remote=None,nonce=NONCE):
        body=function(ROOT/'bin/vm-lab','remote')
        script='set -euo pipefail\nFORWARDED_SETTINGS=(VM_LAB_TRANSPORT_DIAGNOSTIC_NONCE)\nhost=inert\n'
        script+='VM_LAB_TRANSPORT_DIAGNOSTIC_NONCE='+nonce+'\n'
        script+='emit_remote_payload() { printf PAYLOAD; return '+str(producer)+'; }\n'
        script+='ssh() { cat >/dev/null; printf SAME_STDOUT; printf RAW_AUTH_ARGV_SECRET >&2; '
        if remote is not None:
            for stage in d.REMOTE:
                rc=remote if stage=='provider.exec.exit' else 0
                script+="printf '\\nVM_LAB_DIAG_V1 "+nonce+' '+stage+' '+str(rc)+"\\n' >&2; "
        script+='return '+str(ssh)+'; }\n'+body+'\nremote guest-root inert -- PUBLIC\n'
        return subprocess.run(['/bin/bash','-c',script],capture_output=True,text=True,timeout=3)

    def test_outer_pipeline_preserves_producer_or_ssh_status_stdout_once(self):
        for producer,ssh in [(0,0),(7,0),(0,255),(7,255),(0,17)]:
            with self.subTest(producer=producer,ssh=ssh):
                result=self.outer(producer,ssh)
                self.assertEqual(result.returncode,ssh or producer);self.assertEqual(result.stdout,'SAME_STDOUT')
                value=d.receipt(result.stderr,NONCE,result.returncode)
                self.assertTrue(value['diagnosticValid']);self.assertNotIn('RAW_AUTH_ARGV_SECRET',str(value))
                self.assertEqual(value['stages'][-3]['returnCode'],producer)
                self.assertEqual(value['stages'][-2]['returnCode'],ssh)

    def test_remote_return255_distinguished_from_missing_remote_entry_without_claiming_guest_cause(self):
        result=self.outer(0,255,255);value=d.receipt(result.stderr,NONCE,255)
        self.assertEqual(value['classification'],'provider-or-guest-exit255-unresolved')
        result=self.outer(0,255);value=d.receipt(result.stderr,NONCE,255)
        self.assertEqual(value['classification'],'outer-transport-or-remote-entry-unknown')

    def guest(self,status=0,guard_ok=True,nonce=NONCE):
        helper=function(ROOT/'lib/remote.sh','transport_diagnostic')
        guest=function(ROOT/'lib/remote.sh','guest_root')
        script='set -euo pipefail\nVM_LAB_TRANSPORT_DIAGNOSTIC_NONCE='+nonce+'\n'
        script+='owned_manifest() { printf manifest; }\nnow_epoch() { printf 1; }\ndie() { exit 1; }\n'
        state='ready' if guard_ok else 'not-ready'
        script+='field() { case "$2" in status) printf '+state+';; expires_epoch) printf 999;; provider) printf parallels;; provider_resource) printf 11111111-1111-1111-1111-111111111111;; esac; }\n'
        script+='fake_provider() { printf EXACT_PROVIDER_STDOUT; printf PRIVATE_ARGS_OR_AUTH >&2; printf x >> "$COUNT_FILE"; return '+str(status)+'; }\nKEYPATH_LAB_PRLCTL=fake_provider\n'
        with tempfile.TemporaryDirectory() as tmp:
            path=pathlib.Path(tmp)/'count';script+='COUNT_FILE='+str(path)+'\n'
            result=subprocess.run(['/bin/zsh','-c',script+helper+'\n'+guest+'\nguest_root inert PUBLIC\n'],capture_output=True,text=True,timeout=3)
            count=path.read_text() if path.exists() else ''
        return result,count

    def test_actual_remote_provider_once_and_return_preserved(self):
        for status in [0,1,255]:
            result,count=self.guest(status)
            self.assertEqual(result.returncode,status);self.assertEqual(count,'x')
            self.assertEqual(result.stdout,'EXACT_PROVIDER_STDOUT')
            self.assertIn('provider.exec.exit '+str(status),result.stderr)
        result,count=self.guest(guard_ok=False)
        self.assertEqual(result.returncode,1);self.assertEqual(count,'')
        self.assertIn('guest-root.enter',result.stderr);self.assertNotIn('owned-guard.passed',result.stderr)

    def test_invalid_nonce_refuses_before_any_dispatch(self):
        result=self.outer(nonce='BAD');self.assertEqual(result.returncode,64);self.assertEqual(result.stdout,'')
        result,count=self.guest(nonce='BAD');self.assertEqual(result.returncode,64);self.assertEqual(count,'')

    def test_default_absence_leaves_outputs_and_exit_unchanged_without_markers(self):
        result=self.outer(0,255,nonce='');self.assertEqual(result.returncode,255)
        self.assertNotIn(d.PREFIX,result.stderr)
        result,count=self.guest(255,nonce='');self.assertEqual(result.returncode,255);self.assertEqual(count,'x')
        self.assertNotIn(d.PREFIX,result.stderr)

    def test_partial_duplicate_order_wrongnonce_and_status_frames_are_not_valid(self):
        good=self.outer(0,255,255).stderr
        mutations=[good.replace('provider.exec.exit 255','provider.exec.exit true'),
                   good+f'VM_LAB_DIAG_V1 {NONCE} outer.ssh.exit 255\n',
                   good.replace('owned-guard.passed','provider.exec.enter',1),
                   good.replace(NONCE,'b'*32,1),good.replace('outer.pipeline.exit 255','outer.pipeline.exit 0'),
                   good.replace('provider.exec.exit 255','provider.exec.exit 256')]
        for value in mutations:
            result=d.receipt(value,NONCE,255);self.assertFalse(result['diagnosticValid']);self.assertEqual(result['stages'],[])
        result=d.receipt('SECRET'*12000,NONCE,255);self.assertFalse(result['diagnosticValid'])

    def test_raw_nonframes_do_not_change_selected_receipt_hash(self):
        good=self.outer(0,255,255).stderr
        self.assertEqual(d.receipt(good,NONCE,255),d.receipt(good+'different private stderr\n',NONCE,255))

if __name__=='__main__':unittest.main()
