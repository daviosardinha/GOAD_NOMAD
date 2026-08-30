#!/usr/bin/env bash
set -euo pipefail

readonly NETWORKING_FILE="/etc/vmware/networking"
readonly VMWARE_NETWORKS="/usr/bin/vmware-networks"

failures=0

ok()   { printf '[OK]   %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*"; }
fail() { printf '[FAIL] %s\n' "$*"; failures=$((failures + 1)); }

[[ -f "${NETWORKING_FILE}" ]] || { fail "${NETWORKING_FILE} not found"; exit 1; }

check_value() {
  local net="$1" key="$2" expected="$3"
  local actual
  actual="$(awk -v k="VNET_${net}_${key}" '$1=="answer" && $2==k {print $3}' "${NETWORKING_FILE}" | tail -n1)"
  if [[ "${actual}" == "${expected}" ]]; then
    ok "vmnet${net} ${key}=${expected}"
  else
    fail "vmnet${net} ${key}: expected '${expected}', got '${actual:-missing}'"
  fi
}

check_no_nat() {
  local net="$1"
  local actual
  actual="$(awk -v k="VNET_${net}_NAT" '$1=="answer" && $2==k {print $3}' "${NETWORKING_FILE}" | tail -n1)"
  if [[ -z "${actual}" || "${actual}" == "no" ]]; then
    ok "vmnet${net} NAT=off"
  else
    fail "vmnet${net} NAT is enabled"
  fi
}

for spec in \
  '10 10.4.10.0 yes NORTH' \
  '20 10.4.20.0 no SEVENKINGDOMS' \
  '30 10.4.30.0 no ESSOS' \
  '99 10.4.99.0 yes MANAGEMENT'
do
  read -r net subnet host_adapter label <<<"${spec}"
  echo "--- vmnet${net} / ${label} ---"
  check_value "${net}" DHCP no
  check_value "${net}" HOSTONLY_NETMASK 255.255.255.0
  check_value "${net}" HOSTONLY_SUBNET "${subnet}"
  check_value "${net}" VIRTUAL_ADAPTER "${host_adapter}"
  check_no_nat "${net}"
  echo
done

check_value 10 HOSTONLY_HOSTADDR 10.4.10.254
check_value 99 HOSTONLY_HOSTADDR 10.4.99.254

# Only NORTH and MANAGEMENT intentionally expose host-side interfaces.
for spec in '10 10.4.10.254/24' '99 10.4.99.254/24'; do
  read -r net expected_cidr <<<"${spec}"
  if ip link show "vmnet${net}" >/dev/null 2>&1; then
    ok "host interface vmnet${net} exists"
    if ip -4 -o addr show dev "vmnet${net}" | awk '{print $4}' | grep -Fxq "${expected_cidr}"; then
      ok "vmnet${net} host address=${expected_cidr}"
    else
      fail "vmnet${net} does not have expected host address ${expected_cidr}"
    fi
  else
    fail "host interface vmnet${net} is missing"
  fi
done

for net in 20 30; do
  if ip link show "vmnet${net}" >/dev/null 2>&1; then
    fail "host interface vmnet${net} exists; this would bypass segmentation"
  else
    ok "host interface vmnet${net} is absent as designed"
  fi
done

echo
if [[ -x "${VMWARE_NETWORKS}" ]]; then
  "${VMWARE_NETWORKS}" --status || warn "vmware-networks status returned non-zero"
else
  warn "${VMWARE_NETWORKS} not found"
fi

echo
if (( failures == 0 )); then
  echo '[READY] VMware host networking matches GOAD_NOMAD design.'
else
  echo "[NOT READY] ${failures} validation check(s) failed."
  exit 1
fi
