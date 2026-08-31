<div align="center">
  <h1><img alt="GOAD (Game Of Active Directory)" src="./docs/mkdocs/docs/img/logo_GOAD3.png"></h1>
  <br>
</div>

**GOAD (v3)**

:bookmark: Documentation : [https://orange-cyberdefense.github.io/GOAD/](https://orange-cyberdefense.github.io/GOAD/)

## GOAD_NOMAD development

This fork is being extended into GOAD_NOMAD: a segmented Red Team training range that preserves the GOAD Active Directory environment while adding realistic network boundaries, pivoting, Windows local privilege escalation, domain persistence, and richer cross-domain / cross-forest progression.

Major project milestones and their completion gates are tracked in [`docs/GOAD_NOMAD_MILESTONES.md`](./docs/GOAD_NOMAD_MILESTONES.md). Individual implementation steps and bug fixes are not treated as separate milestones.

Current status: **Milestone 1 — Network Segmentation: VALIDATION PENDING.** The segmented runtime design has passed end-to-end validation on the development deployment, including Active Directory trusts, DNS, GOAD bots, MSSQL linked-server execution, persistent NAT isolation, and deny-by-default routing. The final gate is clean-checkout reproducibility: the committed source must pass static preflight, operate the existing deployment from a separate clone, and rerun the relevant DNS/trust configuration idempotently without manual repair.

Use `./scripts/lab-mode.sh provisioning` for Vagrant/Ansible maintenance and `./scripts/lab-mode.sh exercise` before starting the training environment. Run `./scripts/validate-network-segmentation-source.sh` after a fresh clone before operating a lab.

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