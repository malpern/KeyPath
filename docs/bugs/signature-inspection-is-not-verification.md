# Signature inspection is not verification

The local candidate builder called codesign with display flags inside
kp_verify_signature. The identity contract likewise inspected metadata without
verifying signed bytes. A signed bundle with a modified Info.plist still returned
success from display and retained its original authority and team metadata.

Both paths now verify strict signature integrity. The identity contract verifies
each required component explicitly, including the bridge dylib and simulator in
Contents/Library/KeyPath, before comparing identifiers and signing requirements.
This complements the post-resource-copy forbidden-payload gate; it does not
replace Developer ID identity checks or notarization.

Scripts/tests/test_signature_integrity.py exercises verification flags and failure
propagation, rejects invalid component integrity despite valid-looking identity
metadata, and signs a disposable app ad hoc before modifying its Info.plist to
prove actual codesign rejection. It needs no signing credential or product build.
