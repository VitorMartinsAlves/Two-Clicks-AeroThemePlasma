#!/usr/bin/env bash

# Holds a non-blocking per-user lock for the lifetime of the calling installer
# process. The descriptor is intentionally global so it remains open.
ATP_INSTALL_LOCK_FD=""

acquire_installer_lock() {
    local lock_file="$1"
    local lock_dir
    local saved_umask

    if ! command -v flock >/dev/null 2>&1; then
        printf 'Erro: o comando flock (util-linux) e necessario para evitar instalacoes simultaneas.\n' >&2
        return 2
    fi

    lock_dir="$(dirname -- "$lock_file")"
    if [[ ! -d "$lock_dir" || ! -w "$lock_dir" ]]; then
        printf 'Erro: diretorio de lock inexistente ou sem permissao de escrita: %s\n' "$lock_dir" >&2
        return 2
    fi

    if [[ -L "$lock_file" ]]; then
        printf 'Erro: o arquivo de lock nao pode ser um link simbolico: %s\n' "$lock_file" >&2
        return 2
    fi

    saved_umask="$(umask)"
    umask 077
    if ! exec {ATP_INSTALL_LOCK_FD}>>"$lock_file"; then
        umask "$saved_umask"
        printf 'Erro: nao foi possivel abrir o arquivo de lock: %s\n' "$lock_file" >&2
        return 2
    fi
    umask "$saved_umask"

    if ! flock -n "$ATP_INSTALL_LOCK_FD"; then
        exec {ATP_INSTALL_LOCK_FD}>&-
        ATP_INSTALL_LOCK_FD=""
        printf 'Outra instalacao do AeroThemePlasma ja esta em execucao para este usuario.\n' >&2
        return 1
    fi
}
