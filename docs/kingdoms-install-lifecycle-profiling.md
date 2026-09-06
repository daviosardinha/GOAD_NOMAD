# KINGDOMS fresh-install lifecycle profiling

This branch measures the existing GOAD/VMware installation path before any
post-materialization optimization is attempted.

The profiling layer is intentionally observational:

- `goad/provider/vagrant/vmware_kingdoms.py` remains the authoritative lifecycle.
- Fresh guests still use the existing first `vagrant up` path.
- Failed first bring-up still uses the existing bounded recovery path.
- Installed `start` / `stop` behavior is unchanged.
- No VM is accepted merely because VMware reports it powered on.

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
