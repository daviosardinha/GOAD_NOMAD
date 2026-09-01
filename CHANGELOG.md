# Changelog

All notable GOAD_NOMAD changes are documented in this file.

## [v1.0.0] - 2026-09-01

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
