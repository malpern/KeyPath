# Managed and Unmanaged VM Lanes

KeyPath installer QA uses two base images for each supported macOS version. A
base image is cloned for a test and is never itself used as a test machine.

## Lane definitions

| Lane | Base state | Purpose |
| --- | --- | --- |
| `managed-functional` | MDM enrolled; KeyPath PPPC, system-extension, and service-management profiles installed; KeyPath never installed | Deterministic install, use, repair, upgrade, and uninstall scenarios without testing Apple's approval UI |
| `unmanaged-ui` | No MDM enrollment, lab profiles, KeyPath installation, or KeyPath TCC history | A small set of tests that verify KeyPath correctly explains and responds to real macOS approval prompts |

Do not convert a clone from one lane into the other. Enrollment, TCC,
DriverKit, Background Items, and System Extension state can survive an apparent
cleanup. Reusing one base would make a failure impossible to attribute to the
installer or to leftover platform state.

This requires two base images per macOS version, not two permanent VMs per
test. CrabBox creates disposable clones from the appropriate powered-off base.

## Managed base build

1. Start from a clean macOS base that has never installed KeyPath.
2. Enroll the VM in the lab MDM and confirm `profiles status -type enrollment`.
3. Generate profiles from the exact signed KeyPath release candidate:

   ```bash
   Scripts/lab/mdm/generate-keypath-profiles \
     --app /path/to/KeyPath.app \
     --output /tmp/keypath-profiles
   ```

4. Publish the three profiles through MDM and wait for successful installation.
5. Copy the three profiles and `manifest.json` into
   `/Library/KeyPathLab/managed-policy/` in the base. This immutable copy lets
   admission verify the exact policy without depending on a live MDM response.
6. Run `Scripts/lab/mdm/verify-lane managed-functional --manifest
   /Library/KeyPathLab/managed-policy/manifest.json`.
7. Shut down the VM and create the managed base checkpoint.

The generator derives PPPC designated requirements from the signed app. It
fails if the expected KeyPath identifiers or team change, rather than silently
creating an overly broad profile. The VirtualHID system extension remains
restricted to its upstream team and extension identifier.

## Clone identity and MDM

Initially run managed clones sequentially. A checkpoint made after enrollment
contains the enrollment identity. Multiple concurrent clones of that checkpoint
can appear to the MDM server as the same device. Profiles already installed in
the checkpoint remain useful, but commands and inventory updates can be routed
to the wrong clone.

Before enabling concurrent managed tests, add a clone-personalization phase
that enrolls each clone with a unique MDM identity, or prove that the chosen
virtualization and MDM stack regenerate device identity safely. Do not infer
this from a single successful clone.

## Test admission rules

The harness verifies its lane automatically before installing KeyPath:

- `managed-functional` requires active MDM enrollment, all three lab profile
  identifiers, and the profile manifest used to build the base.
- `unmanaged-ui` requires all three managed profile identifiers to be absent.
- A lane mismatch is an infrastructure failure. It must not be reported as a
  KeyPath product failure.
- Managed admission verifies the policy profile hashes and rejects a signed app
  whose bundle IDs, teams, or designated requirements do not match that policy.

Create every lease with an explicit lane:

```bash
Scripts/lab/keypath-lab create --macos 26 --lane managed-functional \
  --commit "$COMMIT" --installer dist/KeyPath.zip
```

The lane is recorded in the lease manifest and determines the base name. It
cannot be changed after creation. Managed macOS 27 creation is rejected until
that policy has been proven.

After installation, managed tests must still verify behavior: KeyPath and the
runtime report Accessibility and Input Monitoring, the VirtualHID extension is
active, background services are approved, Kanata is running, and TCP readiness
responds. The presence of a profile is preparation, not proof that KeyPath works.
Run `keypath-lab scenario LEASE managed-capabilities` to capture and assert this
evidence. The scenario fails unless the lease is `managed-functional`.

## OS boundary

The generated PPPC profile is for macOS 15 and 26. macOS 27 changes managed
privacy consent and needs its own separately proven configuration. Until that
spike passes, macOS 27 must not claim the same deterministic permission lane.
