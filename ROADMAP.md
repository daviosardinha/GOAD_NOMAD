# GOAD Kingdoms Roadmap

This roadmap tracks the work required to make future GOAD Kingdoms installations deterministic, recoverable and portable without destabilizing currently working deployments.

Baseline audited: `4ca0be89b2552c421942a1f1a1674752e569a903`.

## Delivery policy

- Implement each checklist item in a separate issue and pull request.
- Do not test risky lifecycle or dependency changes first against the working `16b7a2` lab.
- Require source validation, failure-path testing and a rollback plan before merge.
- Preserve deny-by-default exercise isolation.
- Treat a non-zero provider, provisioning, extension or isolation result as an installation failure.

## Phase 1 — Safe corrections and automated gates

- [ ] Propagate truthful noninteractive CLI exit codes for install, start, stop and validate.
- [ ] Propagate extension installation and provisioning failures.
- [ ] Fix the malformed trailing comma in `ad/DRACARYS/data/config.json`.
- [ ] Add CI for Bash syntax, Python parsing, structured-data validation and existing source validators.
- [ ] Add regression tests proving failed operations return non-zero.

## Phase 2 — Bootstrap hardening

- [ ] Build `~/.goad/.venv` atomically in a temporary location.
- [ ] Preserve an existing valid environment when bootstrap fails.
- [ ] Add an installation-complete marker and validate it before skipping bootstrap.
- [ ] Enforce provider prerequisites before instance and workspace creation.
- [ ] Pin Python dependencies, Galaxy collections and roles to tested versions.
- [ ] Produce a reproducible dependency lock and update process.

## Phase 3 — Network safety and recovery

- [ ] Restore the original network mode after failed or interrupted provisioning.
- [ ] Make cleanup conditional and idempotent when only part of the VM set exists.
- [ ] Verify actual VMware runtime NIC state instead of ignoring `vmrun` device errors.
- [ ] Add bounded retries for VMware device transitions.
- [ ] Make provisioning-mode entry transactional with rollback for partial failures.
- [ ] Record enough transition state to recover safely after interruption.
- [ ] Add fault-injection tests for every lifecycle phase.
- [ ] Prove failed provisioning cannot leave NAT, protected host routes or permissive router forwarding enabled.

## Phase 4 — Dependency and artifact compatibility

- [ ] Move from EOL `ansible-core==2.18.0` to a tested supported release.
- [ ] Test the selected Ansible release against every GOAD Kingdoms playbook.
- [ ] Define supported controller Python versions and reject unsupported combinations.
- [ ] Pin and validate the Debian router box.
- [ ] Monitor availability of all pinned Windows boxes.
- [ ] Run disposable clean-install, interrupted-install and resume matrices before release.

## Phase 5 — Platform and provider parity

### VirtualBox on Linux

- [ ] Reproduce NORTH, SEVENKINGDOMS, ESSOS and MANAGEMENT using VirtualBox host-only and internal networks.
- [ ] Port deterministic MAC and conflicting-instance protection.
- [ ] Port provisioning and exercise mode transitions and NAT isolation.
- [ ] Verify runtime adapter state through VirtualBox tooling.
- [ ] Validate clean install, resume, start, stop, failure cleanup and segmentation.

### Proxmox

- [ ] Build reusable Windows and Debian router templates with Packer.
- [ ] Model the four zones using dedicated or VLAN-aware Linux bridges.
- [ ] Port deployment into Terraform without VMware-specific assumptions.
- [ ] Preserve temporary provisioning reachability and deny-by-default exercise routing.
- [ ] Support remote Ansible provisioning and recovery.
- [ ] Validate segmentation from both the provisioning system and guest networks.

### Windows host support

Upstream GOAD supports Windows through WSL or native Python with a provisioning VM. GOAD Kingdoms needs an explicit Windows control-plane design rather than a direct port of Linux-only Bash and systemd behavior.

- [ ] Support Windows 11 hosts with VMware Workstation and VirtualBox.
- [ ] Define and test WSL and native-Python control paths.
- [ ] Replace or abstract `sudo`, systemd, `ip`, nftables and `/usr/local/sbin` assumptions.
- [ ] Configure and validate Windows VMware and VirtualBox host adapters safely.
- [ ] Discover interfaces dynamically and never hard-code interface indexes.
- [ ] Validate route selection, source address and interface metric before Ansible.
- [ ] Test repository paths containing spaces and Windows/WSL filesystem boundaries.
- [ ] Back up and roll back Windows routes and hypervisor network settings.

## Windows regression references

### Host route selection and WinRM HTTPS

Reference: [Orange-Cyberdefense/GOAD issue #497](https://github.com/Orange-Cyberdefense/GOAD/issues/497)

The reported installation failure demonstrated two distinct conditions:

1. Windows selected Wi-Fi instead of the VMware host-only adapter for the GOAD subnet.
2. After routing was corrected, some guests still needed WinRM HTTPS listener, certificate and firewall recovery.

Required regression coverage:

- [ ] Detect when traffic to a lab subnet selects Wi-Fi or another incorrect interface.
- [ ] Confirm the expected source address and hypervisor adapter.
- [ ] Test every guest on TCP port 5986 before Ansible.
- [ ] Perform an authenticated WSMan probe, not only a TCP test.
- [ ] Recover WinRM through an independent Vagrant or NAT management path where possible.
- [ ] Validate HTTPS listener, certificate binding and firewall state after recovery.

### Missing guest prerequisite

Reference: [Orange-Cyberdefense/GOAD issue #157](https://github.com/Orange-Cyberdefense/GOAD/issues/157)

- [ ] Validate required Windows features and tools such as `dnscmd` before dependent Ansible tasks.
- [ ] Install or repair missing prerequisites idempotently.
- [ ] Produce a specific diagnostic instead of failing deep inside domain provisioning.

## Release acceptance criteria

A provider and platform combination is supported only when all of the following pass:

- [ ] Clean installation from an empty host and provider state.
- [ ] Resume after a deliberately interrupted provider phase.
- [ ] Resume after a deliberately failed Ansible playbook.
- [ ] Failure returns a non-zero exit code.
- [ ] Failure restores or safely preserves the original network mode.
- [ ] Successful installation finishes in exercise mode.
- [ ] Runtime segmentation validation passes.
- [ ] Repeated install, start and stop operations are idempotent.
- [ ] Installation and recovery documentation is complete.
