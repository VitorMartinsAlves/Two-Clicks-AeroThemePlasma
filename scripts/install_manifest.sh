#!/usr/bin/env bash

# Merge a newly generated CMake install manifest into the persistent manifest
# used by uninstall.sh. Keep historical paths so updates do not orphan files
# that were installed by an earlier version.
merge_install_manifest() {
    local source="$1"
    local target="$2"
    local temporary

    if [[ ! -f "$source" ]]; then
        printf 'Erro: manifesto de origem nao encontrado: %s\n' "$source" >&2
        return 1
    fi

    if [[ "$source" == "$target" ]]; then
        printf 'Erro: o manifesto de origem e o destino sao iguais: %s\n' "$source" >&2
        return 1
    fi

    if ! mkdir -p -- "$(dirname -- "$target")"; then
        printf 'Erro: nao foi possivel criar o diretorio do manifesto: %s\n' "$(dirname -- "$target")" >&2
        return 1
    fi

    temporary="$(mktemp "${target}.tmp.XXXXXX")" || return 1

    if [[ -f "$target" ]]; then
        if ! awk 'NF && !seen[$0]++ { print }' "$target" "$source" > "$temporary"; then
            rm -f -- "$temporary"
            return 1
        fi
        if ! chmod --reference="$target" "$temporary"; then
            rm -f -- "$temporary"
            printf 'Erro: nao foi possivel preservar as permissoes do manifesto: %s\n' "$target" >&2
            return 1
        fi
    else
        if ! awk 'NF && !seen[$0]++ { print }' "$source" > "$temporary"; then
            rm -f -- "$temporary"
            return 1
        fi
        chmod 0644 "$temporary" || {
            rm -f -- "$temporary"
            return 1
        }
    fi

    if ! mv -f -- "$temporary" "$target"; then
        rm -f -- "$temporary"
        return 1
    fi
}
