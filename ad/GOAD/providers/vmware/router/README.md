# GOAD_NOMAD VMware Router

`GOAD-ROUTER` is the routing and segmentation plane for the VMware implementation of GOAD_NOMAD. It preserves the original GOAD identity and service relationships while preventing the student attack host from receiving flat Layer-3 access to every domain and forest.

## VMware networks

| VMware network | GOAD_NOMAD zone | Subnet | Router address | Host-side access |
| --- | --- | --- | --- | --- |
| `vmnet10` | NORTH | `10.4.10.0/24` | `10.4.10.1` | `10.4.10.254` |
| `vmnet20` | SEVENKINGDOMS | `10.4.20.0/24` | `10.4.20.1` | none |
| `vmnet30` | ESSOS | `10.4.30.0/24` | `10.4.30.1` | none |
| `vmnet99` | MANAGEMENT | `10.4.99.0/24` | `10.4.99.1` | `10.4.99.254` |

For the four GOAD_NOMAD VMware networks:

- VMware DHCP is disabled.
- VMware NAT is disabled.
- GOAD_NOMAD uses deterministic addressing.
- VMware does not provide inter-zone routing.
- Existing VMware networks such as `vmnet1` and `vmnet8` are preserved.

The student attack host attaches directly to NORTH through `vmnet10`. SEVENKINGDOMS and ESSOS deliberately have no host-side VMware adapters, so legitimate cross-zone traffic must traverse `GOAD-ROUTER`.

`vmnet99` is a host-visible router management network. The Windows GOAD guests are not attached to it, and the exercise firewall does not permit arbitrary MANAGEMENT-to-zone forwarding.

## Router adapters

`GOAD-ROUTER` is a Debian 11 VM with:

- adapter 0: Vagrant VMware NAT for operator SSH/provisioning;
- `vmnet10`: NORTH — `10.4.10.1/24`;
- `vmnet20`: SEVENKINGDOMS — `10.4.20.1/24`;
- `vmnet30`: ESSOS — `10.4.30.1/24`;
- `vmnet99`: MANAGEMENT — `10.4.99.1/24`.

The four custom interfaces are identified by deterministic MAC addresses rather than Linux interface names. IPv4 forwarding is enabled and reverse-path filtering is disabled on the routing VM.

The router's own Vagrant NAT adapter remains connected for operator control in both modes. Student traffic cannot use it as an inter-zone bypass because exercise forwarding is deny-by-default.

## Operating modes

GOAD_NOMAD separates deployment connectivity from the student attack surface. The supported controller is run from the repository root as the normal desktop user:

```bash
./scripts/lab-mode.sh status
./scripts/lab-mode.sh provisioning
./scripts/lab-mode.sh exercise
```

The controller invokes `sudo` itself only for host routing changes.

### Provisioning mode

Provisioning mode is intended for Vagrant, Ansible, maintenance, and lab updates. It:

- sets the five Windows VMware NAT adapters to `ethernet0.startConnected = "TRUE"`;
- connects those NAT adapters at runtime;
- installs temporary host routes to `10.4.20.0/24` and `10.4.30.0/24` through `10.4.10.1`;
- installs the permissive `nftables/provisioning.nft` router policy.

`router/provision.sh` intentionally bootstraps a new routing VM with an equivalent permissive provisioning policy. Provisioning mode is not the student training state.

### Exercise mode

Exercise mode is the normal training state. It:

- installs the persistent deny-by-default `nftables/exercise.nft` router policy;
- removes the temporary host routes to SEVENKINGDOMS and ESSOS;
- sets all five Windows provisioning adapters to `ethernet0.startConnected = "FALSE"`;
- disconnects those NAT adapters immediately at the VMware hypervisor layer.

The persistent `startConnected` setting prevents a Windows provisioning adapter from silently returning after a VM power cycle.

## Exercise firewall policy

The forward chain uses `policy drop` and permits established/related return traffic.

Validated cross-zone exceptions are:

| Source | Destination | Allowed traffic | Purpose |
| --- | --- | --- | --- |
| Winterfell `10.4.10.11` | Kingslanding `10.4.20.10` | host-to-host | NORTH child-domain / parent-domain AD traffic and dynamic RPC |
| Kingslanding `10.4.20.10` | Winterfell `10.4.10.11` | host-to-host | AD relationship traffic |
| Kingslanding `10.4.20.10` | Meereen `10.4.30.12` | host-to-host | SevenKingdoms ↔ ESSOS forest-trust traffic |
| Meereen `10.4.30.12` | Kingslanding `10.4.20.10` | host-to-host | forest-trust traffic |
| Winterfell `10.4.10.11` | Meereen `10.4.30.12` | TCP/UDP 53 | GOAD cross-forest conditional DNS forwarding |
| Meereen `10.4.30.12` | Winterfell `10.4.10.11` | TCP/UDP 53 | cross-forest DNS |
| Castelblack `10.4.10.22` | Braavos `10.4.30.23` | TCP 1433 | GOAD MSSQL linked-server relationship |
| Braavos `10.4.30.23` | Castelblack `10.4.10.22` | TCP 1433 | GOAD MSSQL linked-server relationship |

The broad DC-to-DC rules are deliberate because Active Directory uses dynamic RPC in addition to well-known service ports. Everything else traversing the router is denied unless explicitly added to the exercise policy.

## Milestone 1 validation record

The completed segmented topology was validated end-to-end with:

- NORTH → SevenKingdoms DC discovery;
- bidirectional NORTH / SevenKingdoms parent-child trust;
- SevenKingdoms → ESSOS DC discovery;
- bidirectional SevenKingdoms / ESSOS forest trust;
- cross-forest conditional DNS;
- Castelblack → Braavos linked SQL execution with remote `sa`;
- Braavos → Castelblack linked SQL execution with remote `sa`;
- healthy `connect_bot`, `ntlm_bot`, and `responder_bot` scheduled tasks;
- direct NORTH access from the student side;
- direct SevenKingdoms and ESSOS access denied from the student/host side;
- isolation of all five Windows provisioning NAT adapters;
- NAT isolation surviving repeated Windows VM power cycles;
- reversible provisioning → exercise → provisioning → exercise transitions;
- persistent deny-by-default `nftables` enforcement.

Windows NAT addresses are DHCP-assigned and may change. `scripts/lab-mode.sh` deliberately uses Vagrant VMX metadata and VMware device controls rather than hard-coding those provisioning addresses.

In exercise mode, Vagrant/VMware may report a guest's segmented `10.4.x.x` interface as its primary IP. This is expected. Normal Vagrant/Ansible maintenance should be performed in provisioning mode.

## Validation commands

Check the current lab mode from the repository root:

```bash
./scripts/lab-mode.sh status
```

Inspect the router directly from an instance provider directory:

```bash
vagrant ssh GOAD-ROUTER -c \
  'ip -br addr; echo; ip route; echo; cat /proc/sys/net/ipv4/ip_forward; echo; sudo nft list ruleset'
```

In exercise mode, the expected high-level state is:

- router forward policy: `drop`;
- host routes to `10.4.20.0/24` and `10.4.30.0/24`: absent;
- all five Windows `ethernet0.startConnected`: `FALSE`;
- NORTH remains directly reachable from the student host;
- SevenKingdoms and ESSOS are not directly reachable from the student host.
