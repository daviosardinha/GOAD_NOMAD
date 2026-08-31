<div align="center">
  <h1><img alt="GOAD (Game Of Active Directory)" src="./docs/mkdocs/docs/img/logo_GOAD3.png"></h1>
  <br>
</div>

**GOAD (v3)**

:bookmark: Documentation : [https://orange-cyberdefense.github.io/GOAD/](https://orange-cyberdefense.github.io/GOAD/)

## GOAD_NOMAD development

This fork is being extended into GOAD_NOMAD: a segmented Red Team training range that preserves the GOAD Active Directory environment while adding realistic network boundaries, pivoting, Windows local privilege escalation, domain persistence, and richer cross-domain / cross-forest progression.

Major project milestones and their completion gates are tracked in [`docs/GOAD_NOMAD_MILESTONES.md`](./docs/GOAD_NOMAD_MILESTONES.md). Individual implementation steps and bug fixes are not treated as separate milestones.

Current status: **Milestone 1 — Network Segmentation: COMPLETE.** The five original GOAD Windows systems now operate in segmented NORTH, SEVENKINGDOMS, and ESSOS zones behind a deny-by-default routing plane while preserving the required Active Directory trusts, DNS behavior, GOAD bots, and MSSQL linked-server relationships. The committed implementation passed the final clean-checkout reproducibility gate on 2026-08-31 from source commit `3997cc44539b009577807cea9361842963af2000` with **27 PASS / 0 WARN / 0 FAIL**.

Use `./scripts/lab-mode.sh provisioning` for Vagrant/Ansible maintenance and `./scripts/lab-mode.sh exercise` before starting the training environment. For source-only checks run `bash scripts/validate-network-segmentation-source.sh`; for the complete clean-checkout/runtime gate run `bash scripts/validate-network-segmentation.sh` with `GOAD_PROVIDER_DIR` pointing to the deployed provider directory.

Milestone 2 remains **PLANNED / NOT STARTED**. Completing Milestone 1 does not automatically begin the next implementation phase.

## Description
GOAD is a pentest active directory LAB project.
The purpose of this lab is to give pentesters a vulnerable Active directory environment ready to use to practice usual attack techniques.

> [!CAUTION]
> This lab is extremely vulnerable, do not reuse recipe to build your environment and do not deploy this environment on internet without isolation (this is a recommendation, use it as your own risk).<br>
> This repository was build for pentest practice.

![goad_screenshot](./docs/img/goad_screenshot.png)

## Licenses
This lab use free Windows VM only (180 days). After that delay enter a license on each server or rebuild all the lab (may be it's time for an update ;))

## Available labs

- GOAD Lab family and extensions overview
<div align="center">
<img alt="GOAD" width="800" src="./docs/img/diagram-GOADv3-full.png">
</div>

- [GOAD](https://orange-cyberdefense.github.io/GOAD/labs/GOAD/) : 5 vms, 2 forests, 3 domains (full goad lab)
<div align="center">
<img alt="GOAD" width="800" src="./docs/img/GOAD_schema.png">
</div>

- [GOAD-Light](https://orange-cyberdefense.github.io/GOAD/labs/GOAD-Light/) : 3 vms, 1 forest, 2 domains (smaller goad lab for those with a smaller pc)
<div align="center">
<img alt="GOAD Light" width="600" src="./docs/img/GOAD-Light_schema.png">
</div>

- [MINILAB](https://orange-cyberdefense.github.io/GOAD/labs/MINILAB/): 2 vms, 1 forest, 1 domain (basic lab with one DC (windows server 2019) and one Workstation (windows 10))

- [SCCM](https://orange-cyberdefense.github.io/GOAD/labs/SCCM/) : 4 vms, 1 forest, 1 domains, with microsoft configuration manager installed
<div align="center">
<img alt="SCCM" width="600" src="./docs/img/SCCMLAB_overview.png">
</div>

- [NHA](https://orange-cyberdefense.github.io/GOAD/labs/NHA/) : A challenge with 5 vms and 2 domains. no schema provided, you will have to find out how break it.
<div align="center">
<img alt="SCCM" width="600" src="./docs/img/logo_NHA.jpeg">
</div>

- [DRACARYS](https://orange-cyberdefense.github.io/GOAD/labs/DRACARYS/) : A challenge with 3 vms and 1 domains. no schema provided, you will have to find out how break it.
<div align="center">
<img alt="SCCM" width="600" src="./docs/img/dracarys_logo.png">
</div>