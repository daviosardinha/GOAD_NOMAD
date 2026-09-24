# Phase 03 operator scripts

The permanent implementation source of truth is the
`kingdoms/phase03-overlay` branch.

Current checkpoint:

- `validate-phase03-readiness.sh` is the read-only prerequisite gate.
- `apply-phase03.sh` is a guarded entrypoint and currently makes no lab changes.
- `validate-phase03-runtime.sh` composes readiness + source contract checks.
- `reset-phase03.sh` currently verifies neutral state because no permanent
  state-changing fixture has been added yet.
- `diagnostics/` preserves sanitized versions of the temporary headless-RDP
  and WPAD/mitm6 investigation helpers.
- `rickon-headless.sh`, `check-rickon-prereqs.sh`, and
  `install-rickon-headless.sh` are the permanent fail-closed Rickon→WS01
  victim-session candidate. The service definition is
  `ops/systemd/kingdoms-phase03-rickon.service`.
- The production candidate requires a local owner-only Rickon password file
  and a separately verified owner-only WS01 RDP SHA-256 fingerprint file.
  Neither is stored in Git. The installer copies the user unit but does not
  enable or start it.

Do not commit passwords, NetNTLMv2 captures, NT hashes, Kerberos keys or raw
secret-bearing evidence. Runtime evidence belongs in the operator evidence
directory; Git contains reusable infrastructure, diagnostics and sanitized
results.

Implementation order:

1. source contract and guard rails;
2. NORTH-specific deterministic fixtures;
3. apply/prove/reset coverage for each fixture;
4. runtime attack proof;
5. Phase 00-02 regression;
6. Notion course update with fresh NORTH screenshots.
