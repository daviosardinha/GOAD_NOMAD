# Installed KINGDOMS offline startup

The KINGDOMS console starts an already managed router through local `vmrun`
power control and checks SSH on `10.4.99.1:22`. It does not wait for the router's
NAT address. Mode switching and router runtime checks use the same management
SSH helper. The host must own `10.4.99.254/24`, never the router's `.1` address.

Normal console `start` also powers on all six installed Windows guests through
local `vmrun`, without invoking `vagrant up`, NAT address discovery, forwarded
WinRM ports, or automatic provisioning/recovery. It opens the existing temporary
router policy/routes before checking each inventory address directly on HTTPS
WinRM port 5986. Power-on is bounded to 60 seconds per guest; readiness uses up to
300 seconds per endpoint within a shared 600-second budget, with individual
network-operation timeouts. The original exercise isolation is restored even if
readiness fails or the operator interrupts startup. Already running guests are
not powered on again. Missing VM files or an unknown recorded mode cause `start`
to fail instead of silently creating or repairing machines.

A recorded `exercise` or `provisioning` mode selects this installed path.
Missing router state, failed SSH, or failed nftables readiness stops startup
without silently recreating or reprovisioning the router. Fresh instances with
no recorded mode still use Vagrant provisioning and need locally available
boxes plus package access for installation.

The SSH helper uses the instance's Vagrant private key, or Vagrant's initial
key if key insertion has not occurred. It pins the first management SSH host
key in the instance's `management_known_hosts`; a changed key is rejected.
Custom SSH identities are not automatically discovered.

The host-address timer now schedules from timer activation and repeats 15
seconds after the helper finishes. Setup activates the service synchronously.
Validation rejects an elapsed timer with no next run; an executing oneshot is
accepted while it is activating. This handles setup long after boot and avoids
overlap when interface recreation takes longer than the repeat interval.

## Apply to an existing lab

Stop all VMware guests before running network setup (the setup script enforces
this). From the updated repository:

```bash
sudo bash scripts/setup-vmware-networks.sh
bash scripts/check-vmware-networks.sh
./goad.sh
```

Select the existing instance and use `start`. Generated instance Vagrantfiles
gain disabled box-update checks automatically during the compatibility step.
Do not recreate the workspace. Direct `vagrant up GOAD-ROUTER` still uses the
provider's native NAT discovery; use the KINGDOMS console for installed startup.

## Host acceptance check

With all guests stopped, disable Wi-Fi and start the existing instance. Confirm
the log reports management SSH ready at `10.4.99.1`, the normal Windows readiness
checks pass, and the original exercise mode is restored. Verify the timer is
waiting with a next trigger and produces repeated successful service runs.
Repeat after restarting the timer long after host boot.

The repository regression tests mock VMware/systemd; they do not establish that
the full lab starts offline on Workstation. Explicit installation/repair still
uses its existing Vagrant path. The observed association between Wi-Fi state and
router NAT carrier does not establish the underlying VMware cause.
