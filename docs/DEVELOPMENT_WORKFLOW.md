# GOAD Kingdoms Development & Test Workflow

GOAD Kingdoms uses **Git as the only source of truth for testable project code**.

This policy exists to prevent a locally repaired lab or test checkout from drifting away from the code that other users will actually clone.

## Non-negotiable rule

**Do not fix project code directly on a test machine and then treat that machine as the validated implementation.**

The supported development order is:

1. Make the change in the project Git branch.
2. Commit it.
3. Push it to the branch's upstream remote.
4. On the test machine, fetch/pull or check out the exact pushed commit.
5. Run the source gate.
6. Run the relevant validation.
7. If validation fails, return to step 1. Do not leave an uncommitted test-machine repair behind.

In short:

```text
Git change -> commit -> push -> test checkout sync -> source gate -> test
```

Never:

```text
edit test VM/checkout -> make it work -> forget to reproduce the fix in Git
```

## Mandatory source gate

Before a reproducibility or milestone validation, run:

```bash
bash scripts/verify-test-source.sh
```

The gate fails closed if:

- the working tree or index is dirty;
- the current branch has no upstream;
- the branch is ahead of its upstream;
- the branch is behind its upstream;
- the branch has diverged from its upstream;
- remote refs cannot be fetched.

For an exact immutable test candidate, pin the expected commit:

```bash
bash scripts/verify-test-source.sh <commit-sha>
```

A detached HEAD is accepted only when an expected commit is supplied and matches HEAD exactly.

## Test-machine procedure

Normal branch test:

```bash
cd ~/Documents/GOAD_Kingdoms
git fetch origin
git switch <branch>
git pull --ff-only
bash scripts/verify-test-source.sh
```

Exact-commit reproducibility test:

```bash
cd ~/Documents/GOAD_Kingdoms
git fetch origin
git checkout --detach <commit-sha>
bash scripts/verify-test-source.sh <commit-sha>
```

After the source gate passes, run the requested project validator or lifecycle test.

## Runtime state versus source state

A deployed VMware lab naturally contains runtime state that is not stored in Git: VM disks, generated Vagrant metadata, domain databases, service state, routing counters, and similar artifacts.

That is expected.

What must never drift silently is the **project source used to create or control that runtime state**. Scripts, Ansible roles, provider code, templates, router policies, validation logic, and documentation changes must all originate from committed Git source.

## Emergency debugging

Temporary diagnostic commands may be run on a test machine, but any project-code change that fixes the problem must be recreated in Git, committed, pushed, pulled back into the test checkout, and revalidated from that clean source before the fix is considered complete.

A milestone cannot be closed from a dirty checkout or from a test machine containing unique source changes.

## Branch discipline

- `main` is the stable/released integration baseline.
- Feature/refactor work happens on a named branch.
- Test only pushed commits from that branch.
- Merge only after the branch's required validation passes.
- Release only from `main` after the release candidate is merged and validated.

## Rename compatibility

The public project name is **GOAD Kingdoms** (`GOAD_Kingdoms` in repository/directory contexts).

Milestone 1 shipped as GOAD_NOMAD v1.0.0. Historical release notes remain unchanged. Some internal Python/module/environment identifiers may temporarily retain `nomad` names for compatibility while they are migrated separately with regression testing.
