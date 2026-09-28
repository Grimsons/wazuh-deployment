"""Resolve Wazuh artifact manifest entries across 4.x and 5.x formats."""

from ansible.errors import AnsibleFilterError


def _find(value, names):
    if isinstance(value, dict):
        for key, child in value.items():
            if str(key).lower() in names:
                yield child
            yield from _find(child, names)
    elif isinstance(value, list):
        for child in value:
            yield from _find(child, names)


def resolve_package(manifest, component, package_format, architecture):
    """Return url/checksum for a component, or fail closed."""
    components = list(_find(manifest, {component.lower()}))
    for entry in components:
        for candidate in _find(entry, {package_format.lower()}):
            for package in _find(candidate, {architecture.lower()}):
                if isinstance(package, dict):
                    url = package.get("url") or package.get("uri") or package.get("download_url")
                    checksum = package.get("sha256") or package.get("sha512") or package.get("checksum")
                    if url and checksum:
                        algorithm = "sha512" if package.get("sha512") else "sha256"
                        if str(checksum).startswith(("sha256:", "sha512:")):
                            algorithm, checksum = str(checksum).split(":", 1)
                        return {"url": url, "checksum": "%s:%s" % (algorithm, checksum)}
    raise AnsibleFilterError(
        "No checksummed %s/%s/%s artifact found in the Wazuh manifest"
        % (component, package_format, architecture)
    )


class FilterModule(object):
    def filters(self):
        return {"wazuh_resolve_package": resolve_package}
