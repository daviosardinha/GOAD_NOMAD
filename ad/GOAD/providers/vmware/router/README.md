# GOAD_NOMAD VMware Router

This directory contains the first routing-plane implementation for the segmented GOAD_NOMAD VMware lab.

## VMware networks

Create the following host-only/custom VMware networks before bringing up `GOAD-ROUTER`:

| VMware network | GOAD_NOMAD zone | Subnet | Router address |
| --- | --- | --- | --- |
| `vmnet10` | NORTH | `10.4.10.0/24` | `10.4.10.1` |
| `vmnet20` | SEVENKINGDOMS | `10.4.20.0/24` | `10.4.20.1` |
| `vmnet30` | ESSOS | `10.4.30.0/24` | `10.4.30.1` |
| `vmnet99` | MANAGEMENT | `10.4.99.0/24` | `10.4.99.1` |

For `vmnet10`, `vmnet20`, and `vmnet30`:

- Do not enable VMware NAT.
- Disable VMware DHCP; GOAD_NOMAD uses deterministic addresses.
- Do not configure any VMware-provided inter-network routing.

`vmnet99` is the control/provisioning plane and is not part of the student attack path.

## Milestone 1 behaviour

`GOAD-ROUTER` is a small Debian 11 VM managed by Vagrant. During the first milestone it has:

- Vagrant's normal NAT adapter in slot 0 for SSH/provisioning.
- `vmnet10` in slot 1.
- `vmnet20` in slot 2.
- `vmnet30` in slot 3.
- `vmnet99` in slot 4.
- IPv4 forwarding enabled.
- `nftables` installed and enabled.
- A temporary allow-forward firewall policy.

The permissive forwarding policy is intentional for the first test. We will change it to deny-by-default only after the five original GOAD hosts have been moved to their final zones and the following legitimate paths have been validated:

- NORTH DC02/Winterfell <-> SEVENKINGDOMS DC01/Kingslanding (parent/child AD traffic).
- SEVENKINGDOMS DC01/Kingslanding <-> ESSOS DC03/Meereen (forest-trust AD traffic).
- NORTH SRV02/Castleblack <-> ESSOS SRV03/Braavos (MSSQL trusted link).

The Vagrant NAT interface is also temporary. It exists only so we do not break provisioning while the segmented management plane is being introduced.

## Validation

After provisioning, validate the router with:

```bash
vagrant status
vagrant ssh -c 'ip -br addr; echo; ip route; echo; cat /proc/sys/net/ipv4/ip_forward; echo; systemctl is-enabled nftables; systemctl is-active nftables; echo; sudo nft list ruleset'
```

`/proc/sys/net/ipv4/ip_forward` must return `1`. We read the kernel value directly instead of calling `sysctl` because Debian's non-login `vagrant` user shell may not include `/usr/sbin` in `PATH`.

A normal `vagrant reload` must preserve all four `10.4.x.1/24` addresses and keep `nftables` active without reprovisioning.
