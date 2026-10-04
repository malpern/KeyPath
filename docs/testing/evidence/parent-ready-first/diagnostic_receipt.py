"""Parse bounded fixed diagnostic frames. Never returns or hashes raw stderr."""
import hashlib
import json
import re

PREFIX='VM_LAB_DIAG_V1 '
REMOTE=['guest-root.enter','owned-guard.passed','provider.exec.enter','provider.exec.exit']
OUTER=['outer.producer.exit','outer.ssh.exit','outer.pipeline.exit']


def receipt(stderr, nonce, returncode):
    if re.fullmatch('[0-9a-f]{32}',nonce) is None or type(returncode) is not int or not 0 <= returncode <= 255:
        raise ValueError('invalid diagnostic request')
    result={'version':1,'nonce':nonce,'operationReturnCode':returncode,'diagnosticValid':False,
            'classification':'diagnostic-incomplete','stages':[]}
    try:
        if type(stderr) is not str or len(stderr)>65536:
            raise ValueError('diagnostic bound')
        stages=[]
        for line in stderr.splitlines():
            if not line.startswith(PREFIX):continue
            match=re.fullmatch(r'VM_LAB_DIAG_V1 ([0-9a-f]{32}) ([a-z.-]+) (0|[1-9][0-9]{0,2})',line)
            if not match or match[1]!=nonce or match[2] not in REMOTE+OUTER or int(match[3])>255:
                raise ValueError('diagnostic frame')
            stages.append({'stage':match[2],'returnCode':int(match[3])})
        if not 3<=len(stages)<=7 or [r['stage'] for r in stages[-3:]]!=OUTER:
            raise ValueError('diagnostic completion')
        remote=stages[:-3]
        if [r['stage'] for r in remote]!=REMOTE[:len(remote)]:raise ValueError('diagnostic sequence')
        if any(r['returnCode']!=0 for r in remote[:-1]) or (len(remote)<4 and any(r['returnCode'] for r in remote)):
            raise ValueError('diagnostic entry status')
        producer,ssh,pipeline=[r['returnCode'] for r in stages[-3:]]
        if pipeline!=(ssh or producer) or pipeline!=returncode:raise ValueError('diagnostic status')
        classification='completed-status-observed'
        if producer:classification='payload-producer-failed'
        elif not remote:classification='outer-transport-or-remote-entry-unknown'
        elif len(remote)==1:classification='remote-guard-or-script-incomplete'
        elif len(remote)<4:classification='provider-dispatch-incomplete'
        elif remote[-1]['returnCode']==255:classification='provider-or-guest-exit255-unresolved'
        elif ssh!=remote[-1]['returnCode']:classification='outer-response-or-remote-exit-incomplete'
        result.update(diagnosticValid=True,classification=classification,stages=stages)
    except ValueError:
        pass
    encoded=json.dumps(result,sort_keys=True,separators=(',',':')).encode()
    result['receiptSHA256']=hashlib.sha256(encoded).hexdigest()
    return result
