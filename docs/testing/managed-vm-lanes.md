# Managed and Unmanaged VM Lanes

KeyPath installer QA uses two base images for each supported macOS version. A
base image is cloned for a test and is never itself used as a test machine.

## Lane definitions

| Lane | Base state | Purpose |
| --- | --- | --- |
| `managed-functional` | MDM enrolled; KeyPath PPPC, system-extension, and service-management profiles installed; KeyPath never installed | Deterministic system-extension, service-management, install, repair, upgrade, and uninstall scenarios; Input Monitoring still uses Apple's approval UI |
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

Lane verification reads the system profile inventory. On macOS 15, an
unprivileged `profiles show -type=configuration` invocation reports only the
current user's profiles and can hide every MDM-installed device profile. The
verifier therefore requires root or non-interactive `sudo` when the caller is
not root; inability to read the system inventory is an admission failure.

The generator derives PPPC designated requirements from the signed app. It
fails if the expected KeyPath identifiers or team change, rather than silently
creating an overly broad profile. The VirtualHID system extension remains
restricted to its upstream team and extension identifier.

Apple does not allow an MDM profile to grant `ListenEvent` (Input Monitoring).
The PPPC payload therefore uses `AllowStandardUserToSetSystemService`, which
lets a standard user make that choice without administrator authorization but
does not make the choice for them. Managed functional tests must complete and
verify the genuine Input Monitoring approval before claiming runtime readiness.

## Clone identity and MDM

Managed-clone concurrency depends on the provider's identity behavior. The
macOS 15 Tart lane randomizes the clone hardware identity, rejects a clone that
retains the base identity, and enrolls the personalized clone as a distinct MDM
device. Those leases therefore use the `unique-clone` identity scope and may
coexist when Tart host capacity permits.

The macOS 26 Parallels lane still inherits the base enrollment identity.
Multiple clones of that checkpoint can appear to the MDM server as the same
device, so commands and inventory updates could be routed to the wrong clone.
Those leases use a scope keyed by the shared enrollment identity, and admission
allows only one active lease in that scope. Do not remove that serialization
until clone personalization and fresh enrollment are proven on macOS 26.

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

For a managed lease, `create` derives a fresh policy set from that exact signed
installer, copies the manifest into the clone, publishes all three profiles,
waits for NanoMDM acknowledgements, queries the installed profile inventory,
and runs system-level lane admission before reporting the lease ready. Policy
publication routes through the base-specific enrollment identity stored under
the controller's `managed-identities` directory and fails closed when that
identity is absent or invalid.
The lease manifest records `managed_identity_scope`. Admission serializes only
leases that share the same enrollment identity; personalized macOS 15 clones
do not weaken the shared-identity protection for macOS 26.

After installation, managed tests must still verify behavior: KeyPath and the
runtime report Accessibility and Input Monitoring, the VirtualHID extension is
active, background services are approved, Kanata is running, and TCP readiness
responds. The presence of a profile is preparation, not proof that KeyPath works.
Run `keypath-lab scenario LEASE managed-capabilities` to capture and assert this
evidence. The scenario fails unless the lease is `managed-functional`.

Runtime readiness is deliberately stricter than registration or an open port.
The probe requires the Kanata launchd job to report `state = running`, sends a
real `RequestCurrentLayerName` request to port 37001, and requires a bounded
layer-bearing JSON response. A registered-but-stopped job, an open-but-silent
socket, or unrelated JSON is a failure.

The probe contract can be exercised without a VM:

```bash
Scripts/lab/mdm/tests/managed-capability-probe-tests.sh
```

## OS boundary

The generated legacy PPPC profile remains an admission input for macOS 15 and
26, but its Accessibility grant is functional only before macOS 26.2. On
macOS 26.2 and later, the managed Accessibility switches can appear enabled
while the system has no corresponding TCC grant. Runtime admission must require
KeyPath's independent permission result and must fail in that state.

[Apple's replacement](https://developer.apple.com/documentation/devicemanagement/privacypreferencespolicycontrol/services-data.dictionary)
is the declarative `com.apple.configuration.app-settings` configuration. Until
the lab publishes and verifies that declaration, macOS 26.2 and later cannot
claim a deterministic managed Accessibility lane. macOS 27 also removes the
legacy PPPC behavior entirely.
