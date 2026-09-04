# Changelog

All notable project changes are documented in this file.

## [Unreleased] — GOAD Kingdoms

## [v1.1.1] - 2026-09-04

### Release
- Released **GOAD Kingdoms v1.1.1 — Lifecycle Reliability**.
- Runtime validation was completed from the origin-synchronized implementation commit `e40f7d2e7fdbcdbe5de342787471ade4b4f54c9c`.
- This maintenance release changes the segmented VMware start/stop control plane only; the v1.1.0 topology, WS01 foundation and Windows LPE curriculum are unchanged.

### Fixed
- Authenticate sudo before any segmented `start` VM state change and keep the sudo timestamp alive throughout long startup operations.
- Run the network/collision preflight before guest bring-up so privileged setup failures occur before the lab is partially started.
- Prevent temporary provisioning-route activation from failing late because the sudo timestamp expired.
- Run bounded Vagrant shutdown in its own process group and fully terminate/reap the timed-out Vagrant/Ruby tree before fallback begins.
- Refuse to enter fallback while the original Vagrant controller may still hold machine action locks.
- Replace the conflicting per-machine Vagrant fallback with lock-free VMware soft shutdown, retaining hard stop only as the final fallback.
- Verify final VMware power state before reporting a successful segmented shutdown.

### Validation
- Segmented start with an intentionally expired sudo ticket: **PASS**; authentication occurred before VM startup and remained valid through the approximately 7.5-minute lifecycle.
- Provisioning routes and exercise-mode restoration: **PASS**.
- The 180-second global `vagrant halt` timeout path was exercised: process-group reaping, grace period and VMware soft-stop fallback all passed.
- The former `another process is already executing an action on the machine` race was not reproduced.
- All six Windows guests and `GOAD-ROUTER` finished powered off, and the merged `main` clean-install source gate passed.

## [v1.1.0] - 2026-09-03

### Release
- Released **GOAD Kingdoms v1.1.0 — NORTH Workstation & Windows LPE**.
- Final validated source: `6285838af4dca55704092e2a6c0cc6a131be798f`.
- Complete clean-install runtime acceptance passed from origin-synchronized source and returned the range to deny-by-default `exercise` mode.

### Changed
- Renamed the public project identity from **GOAD_NOMAD** to **GOAD Kingdoms** (`GOAD_Kingdoms` in repository/directory contexts).
- Added a canonical GOAD Kingdoms milestone roadmap for development after v1.0.0.
- Established Git as the mandatory source of truth for testable project code: changes must be committed and pushed before a test checkout is synchronized and validated.
- Expanded the segmented Windows lifecycle, WinRM readiness gate, start/stop handling, provisioning-mode control and persistent NAT isolation from five guests to six.
- GOAD instance inventories are refreshed from committed canonical source during VMware install, and existing M1 instance Vagrantfiles receive the committed WS01 definition automatically.
- Removed GOAD compatibility from the legacy optional `ws01` extension to prevent a duplicate `GOAD-WS01` Vagrant identity; the extension remains available to GOAD-Light and GOAD-Mini.
- WS01 runtime reachability validation now uses the intended NORTH service contract (RDP 3389/tcp and WinRM HTTPS 5986/tcp) rather than requiring ICMP echo through the Windows client firewall.
- Windows LPE metadata distinguishes planned, candidate and implemented techniques; all 20 deterministic v1.1.0 scenarios are promoted to Implemented after reversible runtime validation.

### Added
- `scripts/verify-test-source.sh`, a fail-closed source gate that rejects dirty, untracked, ahead, behind, diverged, untracked-upstream, or otherwise unverifiable test checkouts.
- Exact-commit source-gate support for detached reproducibility testing.
- `docs/DEVELOPMENT_WORKFLOW.md` documenting the Git-first development/test process.
- First-class `GOAD-WS01` Windows 10 workstation in NORTH at `10.4.10.31`, pinned to the `mayfly/windows10` `2024.01.06` VMware box.
- `NORTH\\rickon.stark` as the intended low-privilege WS01 foothold with Remote Desktop access and no local-administrator grant.
- `scripts/validate-ws01-source.sh` for the M2 workstation topology, identity, security-baseline and lifecycle source contract.
- `scripts/validate-ws01-runtime.sh` for focused exercise-mode validation of WS01 domain membership, Rickon access, low privilege, UAC, Windows Firewall, Defender, RDP and persistent NIC isolation.
- `ansible/ws01.yml` and `./goad.sh -t ws01 -i <instance-id>` for targeted, Git-driven WS01 materialization and baseline provisioning without replaying the full GOAD curriculum.
- Fail-closed VMware instance-collision preflight that derives the project's deterministic segmented MAC identities from committed Vagrant source and blocks another provider from registering the same identities on the shared vmnet10/vmnet20/vmnet30/vmnet99 fabric.
- Validated M2 WS01 clean-foundation checkpoint at source `4003f8b41f5344650f82c746b83b2fe8fec32010`: domain joined to NORTH, Rickon remains low privilege, exercise NAT remains persistently disabled, and UAC/Firewall/Defender remain enabled.
- Ansible-native Windows LPE framework with exactly 20 implemented techniques, named training profiles, a dedicated `windows-lpe.yml` entrypoint, fail-closed selection and deterministic lifecycle control.
- `docs/WINDOWS_LPE_CATALOG.md` and `scripts/validate-windows-lpe-framework-source.sh` to track and validate the LPE catalog/profile framework.
- Twenty resettable Windows LPE scenarios spanning service abuse, registry abuse, credential artifacts, scheduled tasks, token privileges, writable directories and installer policy.
- `service-abuse`, `credential-hunting`, `registry-abuse`, `token-abuse`, `mixed`, and `full-lpe` profiles.
- Full-catalog runtime gates proving apply → vulnerable → reset → clean → reapply → vulnerable behavior without candidate opt-in.

### Fixed
- Recover VMware Tools installation on Windows guests when the installer resets WinRM before the controller can issue its normal reboot; the lifecycle now performs one controlled recovery reboot and validates Tools plus guest-IP health.
- Guarantee restoration of exercise isolation when focused WS01 provider bring-up fails before Ansible provisioning starts.
- Propagate focused WS01 task failures through the non-interactive CLI exit status so unattended wrappers cannot report a failed deployment as finished successfully.
- Prevent duplicate segmented GOAD Kingdoms instances from producing VMware `padrConflict` / `can't set PADR` failures that leave apparently configured custom NICs without Layer-2 connectivity.
- Prevent lifecycle commands from unexpectedly prompting for sudo mid-operation by requiring a non-interactive cached-sudo preflight at the GOAD Kingdoms provider boundary.
- Correct the Windows LPE framework source validator so catalog list parsing is line-bounded and cannot consume comments/profile entries as fake technique IDs.

### Security
- The validated WS01 foundation keeps Defender, UAC and Windows Firewall enabled; WS01 is not sent through GOAD's server-only Defender role and is never added to `defender_off`.
- LPE selection remains fail-closed: normal profiles expose only implemented techniques, and the release contains no remaining candidate or planned deterministic scenario.
- `unquoted_service_path` deliberately grants low-privileged file-creation rights only on the ambiguous parent directory and validates that the legitimate privileged service executable itself is not writable by BUILTIN\\Users.

### Validation
- Network segmentation runtime: **28 PASS / 0 WARN / 0 FAIL**.
- Parent/child trust, cross-forest DNS and linked SQL exercise paths passed after provisioning NAT isolation.
- WS01 domain membership, Rickon low privilege, RDP/WinRM, UAC, Windows Firewall and Defender baseline passed.
- All 20 LPE techniques passed reversible lifecycle validation and remain **APPLIED / VULNERABLE** for training.
- Final runtime state: `exercise`, deny-by-default forwarding, six Windows NAT paths persistently isolated.

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

[v1.1.1]: https://github.com/daviosardinha/GOAD_NOMAD/releases/tag/v1.1.1
[v1.1.0]: https://github.com/daviosardinha/GOAD_NOMAD/releases/tag/v1.1.0
[v1.0.0]: https://github.com/daviosardinha/GOAD_NOMAD/releases/tag/v1.0.0
