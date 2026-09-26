#!/bin/bash
# Optional, non-executable deployment configuration shared by setup.sh and
# setup-tui.sh. Values are KEY=VALUE pairs; command substitution is never run.

load_deployment_config() {
    local config_file="$1" line key value

    [[ -r "$config_file" ]] || {
        echo "Configuration file is not readable: $config_file" >&2
        return 1
    }

    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ "$line" =~ ^[[:space:]]*$ || "$line" =~ ^[[:space:]]*# ]] && continue
        if [[ ! "$line" =~ ^[[:space:]]*([A-Z][A-Z0-9_]*)[[:space:]]*=[[:space:]]*(.*)[[:space:]]*$ ]]; then
            echo "Invalid configuration line in $config_file: $line" >&2
            return 1
        fi
        key="${BASH_REMATCH[1]}"
        value="${BASH_REMATCH[2]}"
        if [[ "$value" =~ ^\"(.*)\"$ || "$value" =~ ^\'(.*)\'$ ]]; then
            value="${BASH_REMATCH[1]}"
        fi
        # Existing environment/CLI values have precedence over the file.
        if [[ -z "${!key+x}" ]]; then
            printf -v "$key" '%s' "$value"
            export "$key"
        fi
    done < "$config_file"
}
