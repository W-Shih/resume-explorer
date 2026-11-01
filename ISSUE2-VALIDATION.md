# Issue-2 implementation validation

Date: 2026-11-01. Candidate: `0.1.0-beta.1+issue2`.

The implementation covers stages B/C and adds observation traces for stage A. The actual Group 2 failure has not been reproduced in the original Horizon VDI environment. No production RCA is claimed. Stage D live acceptance is still pending; the version is deliberately not promoted to beta.2.

## Automated checks

Run `tests/Issue2.Tests.ps1` in PowerShell. It uses a fake clock and injected Explorer adapters, with no real Explorer operations. Tests assert action counts, identity selection, final states, persistence and original indices. No third party modules are required.

Covered scenarios include normal and 12-second delayed creation, detection timeout, duplicate identities, multiple candidates, multiple-to-single history, identity replacement, disappearing baseline, unstable baseline, unavailable controls, window loss, capped error backoff, recovery after more than three errors, error streak reset, clipped deadline, late candidate stability, configurable deadlines, invalid configuration, uncertain Invoke, navigation exception/timeout, old matching paths, checkpoint failure, group isolation, invalid paths, path roots, stale fingerprints, retry selection, completed/uncertain child runs, atomic report replacement, new-window ambiguity/deduplication, interrupted stability, transient enumeration failure, full-run checkpoint integration and global Shell failure.

The implementation stores phase-labelled observations inside each item's `Diagnostics.Samples`, including raw/deduplicated counts, Raw/Root HWND, process fingerprint, identity, path and read errors. This intentionally keeps the complete trace in the checkpoint rather than requiring a separate JSONL file. Reports may grow with group size and configured deadlines. COM references are retained only in live transactions, never serialized.

Local results: **38 adapter/integration tests passed on PowerShell 7.6.1**, Windows build 22631. Windows PowerShell 5.1 parser accepted the core; executing the 5.1 test script was blocked by the machine execution policy. The policy was not changed or bypassed, so 5.1 runtime compatibility remains unverified. A read-only native Shell COM observation in the restricted agent process returned access denied (`0x80070005`); this is an execution-environment limitation, not evidence about the original Issue-2 root cause.

## Live acceptance still required

- Reproduce the original failure with the diagnostic candidate; record Windows build, PowerShell version, group sizes, load, concurrent interaction and raw/root grouping.
- Produce a redacted trace before attributing the failure to duplicate enumeration, delayed exposure, incomplete baseline, COM replacement or concurrent tab operations. Synthetic tests demonstrate handling of these conditions; they do not establish the real root cause.
- Verify the original two-window/three-tab scenario and six-group configurations with duplicate paths, cold and slow VDI responses, concurrent operations in another window, target-window tab additions/closures and closed/stale retry targets.
- Complete a partial restore followed by an explicit subset retry into a previewed target; verify no unrelated existing tab is navigated. Keep reports and retry family together.
- Perform 20 normal multi-group restores in the original supported environment and record every outcome and duration. Test windows are organized manually; the product never closes windows or kills Explorer.
- Validate RawHwnd tab grouping and COM identity stability on that environment. If unreliable, keep conservative stops and design a separate identity mapping rather than guessing candidates.

No strict wall-clock limit is claimed for blocking synchronous COM/UIA calls. Background/no-focus restore, ZIP/Shell namespaces, restart, GUI and snapshot history remain outside this change.
