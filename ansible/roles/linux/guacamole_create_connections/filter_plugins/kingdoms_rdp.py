"""Single permission predicate for generated RDP connections and their cleanup."""


def kingdoms_rdp_allowed(host, user_domain, user_name, user_groups, domains):
    groups = {value.casefold() for value in user_groups}
    same_domain = user_domain.casefold() == host.get("domain", "").casefold()
    if same_domain and "domain admins" in groups:
        return True
    local = host.get("local_groups", {})
    grants = local.get("Administrators", []) + local.get("Remote Desktop Users", [])
    identities = groups | {user_name.casefold()}
    if "Remote Desktop Users" not in host.get("exact_local_groups", []):
        # Preserve legacy connection generation outside the Kingdoms opt-in.
        return any(grant.rsplit("\\", 1)[-1].casefold() in identities for grant in grants)
    # Never match an identically named account/group in a different domain.
    domain = domains[user_domain]
    prefixes = {user_domain.casefold(), domain["netbios_name"].casefold()}
    qualified = {prefix + "\\" + identity for prefix in prefixes for identity in identities}
    return any(grant.casefold() in qualified for grant in grants)


class FilterModule:
    def filters(self):
        return {"kingdoms_rdp_allowed": kingdoms_rdp_allowed}
