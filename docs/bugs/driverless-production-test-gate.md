# Driverless production test gate

The October 6 broad gate exposed three stale integration contracts. An interrupted-write test called normal staging with corrupt sources; the stronger production validator correctly refused before creating a journal. The fixture now constructs the interrupted prior write directly under the operation gate, retaining the recovery refusal and subsequent repair assertions.

Session Caps owner recovery and the experimental timeout admission used direct process probes. They now use the canonical provider: recovery retains EPERM-as-live semantics, while timeout admission still requires a successful zero-signal probe. The standalone experimental harness compiles the canonical probe source. Permission snapshot and raw diagnostic reads also go through the existing provider façade; raw listening/posting facts remain distinct from combined session readiness.

Five reviewed screenshot baselines changed intentionally: three home-row timing views omit Quick Tap for On Press mode; General includes explicit Caps Lock setup; Repair omits privileged-helper controls. Existing tolerances remain unchanged. These baselines do not establish final customer UX approval.

Validation: 21 focused recovery/lint tests passed; the standalone admission harness passed 15 adverse schema cases plus bounded initialization/preparation checks. The full canonical gate passed **5,445 tests** in 193 seconds, with zero Swift/module-cache/app warnings and seven expected error-path app log entries. Logs: `/private/tmp/keypath-production-full-tests-v2/`. The failed first gate is preserved in `...-v1/`. Accessibility checks passed across 380 files. Local integration relay currency was `0 149`; this is not a fresh GitHub master qualification.

Toolchain deviation remains explicit: Xcode 27 and a verified cached Metal library, with the temporary build plugin restored byte-for-byte. This does not prove fresh Metal compilation, notarization, Gatekeeper acceptance, physical compatibility beyond the existing fixture, genuine OS timeout, or live acceptance of these new source changes.
