# KINGDOMS fresh-install lifecycle profiling

This branch measures GOAD/VMware installation, adds one bounded VMTools
reporting repair, and protects running VMs during controller timeout cleanup.
These changes follow the real-host profiling runs. They do not replace initial
Vagrant creation or skip the existing recovery provision cycle.

The profiling layer is intentionally observational:

- `goad/provider/vagrant/vmware_kingdoms.py` remains the authoritative lifecycle.
- Fresh guests still use the existing first `vagrant up` path.
- Failed first bring-up still uses the existing bounded recovery path.
- Installed `start` / `stop` behavior is unchanged.
- No VM is accepted merely because VMware reports it powered on.

The provider's reporting repair is separate from the observational wrapper.
Installed local start/stop paths do not enter this repair.

## Test layout

Keep the current installed range as the known-good regression baseline. Create a
second disposable GOAD/VMware instance for profiling. Both instances may exist on
disk, but never run both segmented instances at the same time because KINGDOMS
uses deterministic MAC/IP identities.

## Branch

```bash
git fetch origin
git switch perf/install-lifecycle
git pull --ff-only origin perf/install-lifecycle
```

Before creating the test instance, run the source guard:

```bash
bash scripts/validate-kingdoms-install-profile-source.sh
python3 -m unittest discover -s tests
```

Then launch the console and create/install the second GOAD/VMware instance using
the normal KINGDOMS workflow.

## What is measured

The provider-side profiler records the existing operations without replacing
them:

- host/network preflight
- generated inventory synchronization
- generated Vagrantfile compatibility synchronization
- router bring-up
- every Vagrant command invoked through the normal provider command path
- VMware Tools / forwarded-WinRM readiness per Windows guest
- failed-first-up recovery cycles when they occur
- bounded Vagrant recovery/halt operations
- total provider bring-up time

The Ansible phase records:

- provisioning management-plane preparation
- every full-install playbook independently
- final exercise-mode transition
- total Ansible phase time
- measured end-to-end time from provider install start through finalization

### Separate attempts and durable checkpoints

Each provider installation invocation gets a unique UTC timestamp/ID and a file:

```text
workspace/<instance>/install-timings/<attempt-id>.json
```

The file is checkpointed atomically after phases, on provider return, and on
Ansible completion, failure, or a handled interruption. A timing-write failure
warns once and does not fail the installation. New invocations create new files;
they never overwrite previous failed-attempt records. Existing captures from
before this change are not backfilled.

`recorded_elapsed` measures this invocation only, beginning at provider entry.
It excludes sudo preparation, separate manual recovery commands, and time
between invocations. `partial: true` denotes an unfinished attempt; after an
unhandled process termination its last checkpoint is a lower bound. Do not
present a resumed invocation as a clean installation benchmark, or sum nested
phase durations with their parent totals.

Vagrant labels are decided before executing the command:

- `first creation`: no provider state directory exists;
- `partial state`: a state directory exists without a machine ID;
- `existing VM`: a machine ID exists;
- `recovery up --provision`: the explicit existing recovery command.

These labels describe observed local metadata only. They do not establish VM
health or provisioning completion, and do not change Vagrant dispatch.

### SQL setup and Ansible retries

Local Ansible playbook invocations are recorded individually with their attempt
number and outcome, inside the parent playbook duration. The existing retry
limit is unchanged. Full profiled installations additionally enable SQL task
timings for `servers.yml`, with one file per playbook attempt:

```text
<attempt-id>.servers-attempt-<n>.tasks.jsonl
```

The local aggregate callback records task names, hosts, outcomes and durations
for `mssql` and `mssql_ssms`, including installer downloads, installations and
reboots. It omits task arguments/results and respects `no_log`. It waits for
async completion rather than treating an async launch as success; repeated
completion events cannot double-count a task. Durations may overlap across
hosts. The ten slowest completed SQL tasks are also printed after each playbook
attempt. Interrupted tasks with no completion event have no completed duration.

The callback is inert without the invocation-specific environment variable.
Standalone playbooks and later console commands do not reuse a completed
profile. No SQL provisioning/retry logic or global Ansible configuration changes.
See the [Ansible callback documentation](https://docs.ansible.com/projects/ansible/latest/plugins/callback.html)
for how aggregate callbacks coexist with normal console output.

### Bounded VMTools reporting repair

During Windows installation readiness, host guest-IP queries now have individual
10-second limits inside the existing polling deadline. If reporting remains
unavailable, KINGDOMS permits **one** VMTools service restart per readiness check.
The repair resolves the guest's current forwarded HTTP WinRM port with a bounded
15-second metadata query, authenticates through the existing WinRM session, and
checks that the service and Tools executable exist. Windows service-stop/start
waits are limited to 20 seconds each. Host reporting is then rechecked for up to
60 seconds and the authenticated guest service check must also pass.

An absent service, failed authentication, failed restart or failed reporting
check returns to the existing failure/recovery handling. Repeated polling in the
same readiness check cannot repeatedly restart the service. The existing path
that tolerates delayed IP reporting for an otherwise healthy guest remains in
place. A failed first `vagrant up` still requires the graceful shutdown and
bounded `up --provision` cycle; successful guest-IP reporting never skips the
remoting or static-IP provisioners. Direct inventory WinRM remains a separate
gate before Ansible.

This addresses the observed SRV02 reporting failure. It is not a root-cause fix
for the initial Vagrant adapter/communicator failure, which still needs a
real-host trace.

### Timeout cleanup preserves VMware guest processes

The recovery command retains its 600-second limit. Cleanup previously sent
SIGTERM/SIGKILL to the complete process group created for Vagrant. VMware's
`vmware-vmx` process can remain in that group after starting the VM, so a
controller timeout could also terminate the guest's monitor.

Cleanup now inspects the group and signals individual controller PIDs. It
preserves VM monitors, the graphics sandbox, and their descendants, including
descendants reparented during cleanup. Executable identity, process creation
time and group membership are checked before signaling. New controller helpers
are discovered during the bounded cleanup window; an unknown/unreadable process
or surviving controller makes cleanup incomplete. A running protected VM does
not prevent successful controller cleanup. An incomplete cleanup blocks another
bounded operation or installation attempt in the same provider session, as well
as the existing local-shutdown paths.

The regression suite covers a VM monitor sharing Vagrant's group, controller
termination/escalation, protected descendants, unrelated work, process identity
changes and incomplete-cleanup guards. It also includes a POSIX process test
using copies of `sleep` as simulated `vmware-vmx` and `vmrun` executables. This
test runs with GOAD's existing `psutil` dependency and process inspection access;
it explicitly skips when those prerequisites are unavailable. It does not boot
or terminate real VMware guests.

The failed `fe65df-goad-vmware` attempt on 2026-09-06 lasted 29m14s overall.
SRV02's recovery reached the remoting provisioner, then hit its 600-second
limit. Its VMX log records `Caught signal 15` at approximately 18:01 UTC, matching
the timeout cleanup, and the next Windows boot recorded an unclean shutdown.
This strongly implicates group cleanup in the VM's power loss; the log does not
identify the signal sender. The earlier remoting stall still needs diagnosis.
This is a failed unattended benchmark, and a resumed run must be labelled as
such. Preserve the failed attempt's JSON and VMware/Windows logs when resuming.

## First observed run: 2026-09-06

Instance `380f24-goad-vmware` required manual SRV02 service restart and a graceful
stop/`up --provision` recovery. Its two install commands measured 26m03s (failed)
and 2h10m29s (resumed/completed), excluding manual work between commands. All five
Server guests encountered the initial Vagrant guest-communication error; the
Windows 10 guest completed initial provisioning on its first attempt.

The resumed run measured `servers.yml` at 43m36s, including a SQL setup failure
and playbook retry. It finished in exercise mode and subsequently completed
local stop/start with a 1m35s startup. These observations are an assisted recovery
baseline, not a successful unattended fresh-install benchmark.

Look for lines beginning with:

```text
GOAD Kingdoms install timing:
```

A successful full install ends with:

```text
=== KINGDOMS INSTALL TIMING SUMMARY ===
```

## Decision rule for the next PR

Do not optimize from intuition. Use the first fresh-install capture to identify
where wall-clock time is actually spent.

The next optimization should preserve initial Vagrant materialization. Candidate
post-materialization changes are only justified where the timing capture shows
meaningful repeated lifecycle/recovery overhead after a VM already exists and its
canonical KINGDOMS management endpoint can be proven healthy.

The current installed baseline must continue to pass online and offline
`start`, `stop`, `start_vm`, and `stop_vm` regression testing before any install
optimization is merged.
