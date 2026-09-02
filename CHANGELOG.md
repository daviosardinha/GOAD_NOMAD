# Changelog

All notable project changes are documented in this file.

## [Unreleased] — GOAD Kingdoms

### Changed
- Renamed the public project identity from **GOAD_NOMAD** to **GOAD Kingdoms** (`GOAD_Kingdoms` in repository/directory contexts).
- Added a canonical GOAD Kingdoms milestone roadmap for development after v1.0.0.
- Established Git as the mandatory source of truth for testable project code: changes must be committed and pushed before a test checkout is synchronized and validated.
- Expanded the segmented Windows lifecycle, WinRM readiness gate, start/stop handling, provisioning-mode control and persistent NAT isolation from five guests to six.
- GOAD instance inventories are refreshed from committed canonical source during VMware install, and existing M1 instance Vagrantfiles receive the committed WS01 definition automatically.
- Removed GOAD compatibility from the legacy optional `ws01` extension to prevent a duplicate `GOAD-WS01` Vagrant identity; the extension remains available to GOAD-Light and GOAD-Mini.

### Added
- `scripts/verify-test-source.sh`, a fail-closed source gate that rejects dirty, untracked, ahead, behind, diverged, untracked-upstream, or otherwise unverifiable test checkouts.
- Exact-commit source-gate support for detached reproducibility testing.
- `docs/DEVELOPMENT_WORKFLOW.md` documenting the Git-first development/test process.
- First-class `GOAD-WS01` Windows 10 workstation in NORTH at `10.4.10.31`, pinned to the `mayfly/windows10` `2024.01.06` VMware box.
- `NORTH\\rickon.stark` as the intended low-privilege WS01 foothold with Remote Desktop access and no local-administrator grant.
- `scripts/validate-ws01-source.sh` for the M2 workstation topology, identity, security-baseline and lifecycle source contract.
- `scripts/validate-ws01-runtime.sh` for focused exercise-mode validation of WS01 domain membership, Rickon access, low privilege, UAC, Windows Firewall, Defender, RDP and persistent NIC isolation.
- `ansible/ws01.yml` and `./goad.sh -t ws01 -i <instance-id>` for targeted, Git-driven WS01 materialization and baseline provisioning without replaying the full GOAD curriculum.

### Security
- WS01 starts with no planted LPE vulnerabilities. Defender, UAC and Windows Firewall remain at the native Windows client baseline; WS01 is not sent through GOAD's server-only Defender role and is never added to `defender_off`.

### Compatibility
- Milestone 1 and the `v1.0.0 — Segmented Foundation` release retain the historical GOAD_NOMAD name.
- Internal compatibility identifiers such as `goad_nomad.py`, `vmware_nomad.py`, class names, and existing lifecycle markers are intentionally retained during the first rename pass. They will be migrated separately only with regression coverage so the validated v1.0.0 lifecycle is not destabilized by a cosmetic rename.

## [v1.0.0] - 2026-09-01

> Historical release: this version was published under the **GOAD_NOMAD** project name.

### Added
- Default segmented VMware topology for the GOAD lab using NORTH (`vmnet10` / `10.4.10.0/24`), SEVENKINGDOMS (`vmnet20` / `10.4.20.0/24`), ESSOS (`vmnet30` / `10.4.30.0/24`), and MANAGEMENT (`vmnet99` / `10.4.99.0/24`).
- `GOAD-ROUTER`, a lightweight Debian routing plane attached to all lab zones.
- Explicit provisioning and exercise network modes.
- Deny-by-default exercise-mode nftables policy with only the validated cross-zone relationships required by the original GOAD scenario.
- Temporary host routes for protected networks during provisioning.
- Persistent Windows NAT isolation in exercise mode.
- GOAD_NOMAD runtime mode/status integration in `./goad.sh`.
- Clean-checkout source and runtime validation scripts for segmented networking.
- Human-readable installation timing/phase reporting.

### Changed
- GOAD on VMware is segmented by default instead of using the original flat `192.168.56.0/24` lab network.
- VMware guest bring-up now bootstraps the router and provisioning plane before Windows guests.
- `start`, `stop`, and install lifecycle handling are bounded and verified instead of relying solely on stock Vagrant behavior.
- Windows management readiness is verified before Ansible provisioning begins.
- Runtime startup restores the recorded lab mode instead of silently leaving the environment in a provisioning state.

### Fixed
- Vagrant/VMware cases where a protected-zone address was selected for WinRM before the host had a valid route to that network.
- Provider fail-open behavior where Ansible could continue after an incomplete VMware bring-up.
- VMware Tools/IP-discovery failures on older Windows boxes by adding bounded recovery and retry handling.
- SSMS provisioning hangs caused by the floating installer URL moving to a newer incompatible release; GOAD_NOMAD pins the GOAD-compatible SSMS 18 installer path.
- Child-domain DNS/ADWS readiness and repeat-run behavior uncovered by clean-install validation.
- Graceful shutdown hangs by adding a bounded controller timeout and verified force fallback for only the guests that remain running.
- Persistent NAT adapter state across stop/start and power-cycle operations.

### Validation
Milestone 1 was closed only after a fresh installation and clean-checkout runtime validation completed successfully with:

- **27 PASS**
- **0 WARN**
- **0 FAIL**

The validated final runtime state is **exercise mode** with Windows provisioning NAT disconnected and protected-zone routing enforced by `GOAD-ROUTER`.

### Compatibility
- This release preserves the original GOAD Active Directory scenario while changing the VMware network architecture and lifecycle around it.
- Non-GOAD labs/providers retain the upstream behavior unless explicitly handled by GOAD_NOMAD.

[v1.0.0]: https://github.com/daviosardinha/GOAD_NOMAD/releases/tag/v1.0.0
