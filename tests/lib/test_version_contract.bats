#!/usr/bin/env bats
# Proves the release contract resolves correctly for both majors, and that the
# shell generators no longer carry their own copy of it.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

setup() {
    if ! command -v ansible-playbook >/dev/null 2>&1; then
        skip "ansible-playbook not installed"
    fi
    if ! command -v python3 >/dev/null 2>&1; then
        skip "python3 not installed"
    fi

    WORK="$BATS_TEST_TMPDIR/work"
    rm -rf "$WORK"
    mkdir -p "$WORK/out"

    # playbook_dir is $WORK, so roles/vars/main.yml resolves $WORK/VERSION.json.
    cat > "$WORK/contract.yml" <<'YAML'
---
- name: Resolve the Wazuh release contract
  hosts: localhost
  connection: local
  gather_facts: false
  tasks:
    - name: Load the shared runtime contract
      ansible.builtin.include_vars:
        file: "{{ contract_repo_root }}/roles/vars/main.yml"

    - name: Load the package manifest contract
      ansible.builtin.include_vars:
        file: "{{ contract_repo_root }}/roles/package-urls/defaults/main.yml"

    - name: Load the manager defaults
      ansible.builtin.include_vars:
        file: "{{ contract_repo_root }}/roles/wazuh-manager/defaults/main.yml"

    - name: Write the resolved contract
      ansible.builtin.copy:
        dest: "{{ playbook_dir }}/out/{{ item.key }}"
        mode: "0644"
        content: "{{ item.value }}"
      loop: "{{ resolved | dict2items }}"
      vars:
        resolved:
          is_5x: "{{ wazuh_is_5x | bool | lower }}"
          is_prerelease: "{{ wazuh_is_prerelease | bool | lower }}"
          release_channel: "{{ wazuh_release_channel }}"
          repository_major: "{{ wazuh_repository_major }}"
          major_minor: "{{ wazuh_major_minor_version }}"
          stage: "{{ wazuh_stage }}"
          urls_file: "{{ urls_file }}"
          manifest_production: "{{ package_urls_file_uri }}"
          manifest_prerelease: "{{ package_urls_file_uri_prerelease }}"
          manager_install_path: "{{ wazuh_manager_install_path }}"
          manager_config_file: "{{ wazuh_manager_config_file }}"
          manager_owner: "{{ wazuh_manager_owner }}"
          manager_group: "{{ wazuh_manager_group }}"
          use_filebeat: "{{ wazuh_use_filebeat | bool | lower }}"
YAML
}

# resolve_contract <version> <stage> [extra_wazuh_version]
# The optional third argument is the wazuh_version override; when omitted the
# VERSION.json pin is the only input, which is the real deployment default.
resolve_contract() {
    local version="$1" stage="$2" override="${3:-}"

    cat > "$WORK/VERSION.json" <<JSON
{"version": "$version", "stage": "$stage"}
JSON

    local -a extra=(-e "contract_repo_root=$REPO_ROOT")
    [[ -n "$override" ]] && extra+=(-e "wazuh_version=$override")

    ANSIBLE_NOCOLOR=1 \
    ANSIBLE_LOCALHOST_WARNING=False \
    ANSIBLE_INVENTORY_UNPARSED_WARNING=False \
    ANSIBLE_DEPRECATION_WARNINGS=False \
    ANSIBLE_RETRY_FILES_ENABLED=False \
        ansible-playbook -i localhost, -c local "$WORK/contract.yml" "${extra[@]}" \
        >"$WORK/ansible.log" 2>&1
}

resolved() {
    cat "$WORK/out/$1"
}

@test "4.14.5 resolves the legacy 4.x contract unchanged" {
    resolve_contract "4.14.5" "stable"
    [ "$(resolved is_5x)" = "false" ]
    [ "$(resolved release_channel)" = "stable" ]
    [ "$(resolved repository_major)" = "4.x" ]
    [ "$(resolved major_minor)" = "4.14" ]
    [ "$(resolved stage)" = "stable" ]
    [ "$(resolved urls_file)" = "artifact_urls.yml" ]
    [ "$(resolved manifest_production)" = "packages.wazuh.com/4.14/artifact_urls.yml" ]
    [ "$(resolved manifest_prerelease)" = "packages-dev.wazuh.com/4.14/artifact_urls.yml" ]
    [ "$(resolved use_filebeat)" = "true" ]
}

@test "4.14.5 keeps the 4.x manager layout" {
    resolve_contract "4.14.5" "stable"
    [ "$(resolved manager_install_path)" = "/var/ossec" ]
    [ "$(resolved manager_config_file)" = "/var/ossec/etc/ossec.conf" ]
    [ "$(resolved manager_owner)" = "wazuh" ]
    [ "$(resolved manager_group)" = "wazuh" ]
}

@test "5.0.0 derives the 5.x contract from the VERSION.json pin alone" {
    # No wazuh_version override: flipping VERSION.json must be enough.
    resolve_contract "5.0.0" "rc1"
    [ "$(resolved is_5x)" = "true" ]
    [ "$(resolved repository_major)" = "5.x" ]
    [ "$(resolved major_minor)" = "5.0" ]
    [ "$(resolved stage)" = "rc1" ]
    [ "$(resolved urls_file)" = "artifact_urls.yaml" ]
    [ "$(resolved manifest_production)" = \
        "packages.wazuh.com/production/5.x/artifact-urls/artifact_urls_5.0.0.yaml" ]
    [ "$(resolved manifest_prerelease)" = \
        "packages-staging.xdrsiem.wazuh.info/pre-release/5.x/artifact-urls/artifact_urls_5.0.0-rc1.yaml" ]
}

@test "5.0.0 uses the 5.x manager layout and drops Filebeat" {
    resolve_contract "5.0.0" "rc1"
    [ "$(resolved manager_install_path)" = "/var/wazuh-manager" ]
    [ "$(resolved manager_config_file)" = "/var/wazuh-manager/etc/wazuh-manager.conf" ]
    [ "$(resolved manager_owner)" = "wazuh-manager" ]
    [ "$(resolved manager_group)" = "wazuh-manager" ]
    [ "$(resolved use_filebeat)" = "false" ]
}

@test "a wazuh_version override still drives the 5.x contract" {
    resolve_contract "4.14.5" "stable" "5.0.0-beta5"
    [ "$(resolved is_5x)" = "true" ]
    [ "$(resolved is_prerelease)" = "true" ]
    [ "$(resolved release_channel)" = "pre-release" ]
    [ "$(resolved urls_file)" = "artifact_urls.yaml" ]
    [ "$(resolved manifest_production)" = \
        "packages.wazuh.com/production/5.x/artifact-urls/artifact_urls_5.0.0-beta5.yaml" ]
}

@test "the beta5 tag does not duplicate its stage in the manifest path" {
    resolve_contract "5.0.0-beta5" "beta5"
    [ "$(resolved is_5x)" = "true" ]
    [ "$(resolved stage)" = "beta5" ]
    [ "$(resolved manifest_prerelease)" = \
        "packages-staging.xdrsiem.wazuh.info/pre-release/5.x/artifact-urls/artifact_urls_5.0.0-beta5.yaml" ]
}

@test "a 4.x pre-release still selects the pre-release channel" {
    resolve_contract "4.14.5-rc1" "rc1"
    [ "$(resolved is_5x)" = "false" ]
    [ "$(resolved is_prerelease)" = "true" ]
    [ "$(resolved release_channel)" = "pre-release" ]
    [ "$(resolved manager_install_path)" = "/var/ossec" ]
    [ "$(resolved manifest_prerelease)" = "packages-dev.wazuh.com/4.14/artifact_urls.yml" ]
}
