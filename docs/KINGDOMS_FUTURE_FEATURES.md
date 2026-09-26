# Kingdoms — Future Features / Deferred Engineering

This file is the repository backlog for capabilities that are intentionally
deferred. Items here are **not** blockers for the currently accepted Kingdoms
phase unless they are explicitly promoted into the active curriculum.

## Phase 03 — Poison the Wells

Phase 03's current engineered attack catalogue is considered complete for the
present release baseline. The following coercion techniques are candidates for
a future Phase 03 expansion.

### DFSCoerce / MS-DFSNM

**Status:** Deferred / future implementation

Add DFSCoerce as an additional authentication-coercion primitive if NORTH
exposes the required MS-DFSNM behavior naturally.

Future engineering should follow the normal Kingdoms state-changing scenario
contract:

1. source/tool capability check;
2. read-only prerequisite discovery;
3. baseline capture;
4. controlled coercion;
5. independent proof that the intended NORTH identity authenticated outward;
6. meaningful relay/capture consequence where appropriate;
7. cleanup and exact restoration;
8. neutral runtime validation;
9. source regression coverage;
10. course walkthrough integration.

Do not add artificial DFS services solely to make the technique exist unless a
later curriculum decision explicitly requires that lab change.

### ShadowCoerce / MS-FSRVP

**Status:** Deferred / future implementation

Assess ShadowCoerce as an additional authentication-coercion primitive if an
appropriate NORTH target exposes MS-FSRVP naturally.

ShadowCoerce is **not** Shadow Credentials:

- ShadowCoerce abuses MS-FSRVP to force outbound authentication.
- Shadow Credentials abuses `msDS-KeyCredentialLink` and is already implemented
  in Phase 03 as a relay consequence.

Use the same engineering/rollback standard as other Phase 03 coercion scenarios.
Do not introduce File Server VSS Agent Service configuration only to manufacture
the attack unless a future curriculum decision explicitly approves it.

## Promotion rule

A deferred feature becomes part of the active Kingdoms phase only after:

- feasibility is proven in the existing lab;
- its addition does not regress earlier phases or segmentation;
- exact cleanup/restoration is proven;
- source regression coverage exists;
- the final phase regression is updated and passes; and
- the corresponding Notion lesson is added to the approved curriculum.

Until then these items remain roadmap work and do not block Phase 03 closure.
