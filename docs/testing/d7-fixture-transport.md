# D7 fixture transport review candidate

The migrated physical trial uses `Scripts/experiments/session-runtime/d7-fixture.py`.
It derives from independently accepted D8 factory SHA256
`78d188b220934cfaf6f264bb3203dbe3c7ea24d8d2ef556a55e5dd7999800f1b`.
D8 source is unchanged. D7 accepts only exact `session-[0-9a-f]{16}` run IDs.
The existing parent entrypoint and dynamic imports are unchanged.

Explicit client construction uses the root-reviewed selected-scalar loader:
`sops -d --extract '["KEYPATH_FIXTURE_TOKEN"]' --output-type json` with captured
memory-only output and a10-second process timeout. It never decrypts the full
store, reads plaintext credential files, exports the token, or puts token values
in argv/logs/receipts. Import performs no credential or network operation.

TCP destination is frozen192.168.1.221:8080 with original
Host:keypath-hid-fixture.local:8080. Each mutation first verifies fresh ok:true,
firmware0.3.2-esp32s3/buildfc98a5acc0a5/platformwaveshare-esp32-s3-touch-lcd-1.69
and address192.168.1.221. Load requires idle/complete/aborted; arm requires exact
owned run loaded; start requires exact owned run armed; abort requires owned
loaded/armed/running. No mutation retries, DNS fallback or address following.

Responses and decoded NDJSON recursively reject reflected tokens before receipt
publication. Trace is bounded to256 entries, pages1..8, stable run/offset/count,
with zero retries. Existing trial uses page8. Socket timeout10s is not a whole
trace elapsed-time bound. Exclusive fixture ownership remains required because
status and mutation are separate requests. Reported firmware identity is not
binary/source attestation; deployedfc98 source provenance remains unresolved.

Pure checks (synthetic tokens/mock transport only):

```sh
PYTHONDONTWRITEBYTECODE=1 python3 Scripts/experiments/session-runtime/test-d7-fixture.py
```

This candidate does not authorize credential extraction, input, guest actions,
physical campaign execution, or permission/password changes. Independent source
review and a separately released execution packet remain required.
