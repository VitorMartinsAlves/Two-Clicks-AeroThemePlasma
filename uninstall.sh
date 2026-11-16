#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ASSUME_YES=0
TEST_MODE="${ATP_UNINSTALL_TEST_MODE:-0}"
SYSTEM_ROOT="${ATP_UNINSTALL_TEST_ROOT:-}"
TEST_OWNED="${ATP_UNINSTALL_TEST_OWNED:-}"

usage() {
    cat <<EOF
Uso: $(basename "$0") [--yes|-y]

  --yes, -y  Remove os arquivos sem pedir confirmacao.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --yes|-y) ASSUME_YES=1 ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            printf 'Opcao desconhecida: %s\n' "$1" >&2
            usage >&2
            exit 2
            ;;
    esac
    shift
done

log() {
    printf '\033[1;34m==>\033[0m %s\n' "$*"
}

warn() {
    printf '\033[1;33mAviso:\033[0m %s\n' "$*" >&2
}

die() {
    printf '\033[1;31mErro:\033[0m %s\n' "$*" >&2
    exit 1
}

if [[ "$TEST_MODE" != "1" && "$(id -u)" -eq 0 ]]; then
    die "Execute como usuario normal, sem sudo na chamada. O script pedira privilegios quando necessario."
fi

if [[ "$TEST_MODE" == "1" ]]; then
    [[ -n "$SYSTEM_ROOT" && -d "$SYSTEM_ROOT" ]] || die "ATP_UNINSTALL_TEST_ROOT precisa apontar para uma raiz temporaria existente."
    local_script_dir="$(cd -- "$SCRIPT_DIR" && pwd -P)"
    local_test_root="$(cd -- "$SYSTEM_ROOT" && pwd -P)"
    [[ "$local_script_dir" == /tmp/* && "$local_test_root" == /tmp/* ]] || die "Modo de teste permitido somente com script e raiz temporaria dentro de /tmp."
    SYSTEM_ROOT="$local_test_root"
    PACKAGE_MANAGER='test'
    SU_CMD=""
else
    if command -v pacman >/dev/null 2>&1; then
        PACKAGE_MANAGER=pacman
    elif command -v dpkg-query >/dev/null 2>&1; then
        PACKAGE_MANAGER=dpkg
    elif command -v rpm >/dev/null 2>&1; then
        PACKAGE_MANAGER=rpm
    elif command -v apk >/dev/null 2>&1; then
        PACKAGE_MANAGER=apk
    else
        die "Nao encontrei uma base de pacotes suportada (pacman, dpkg, rpm ou apk). Por seguranca, nenhum arquivo sera removido."
    fi

    if command -v sudo >/dev/null 2>&1; then
        SU_CMD=sudo
    elif command -v doas >/dev/null 2>&1; then
        SU_CMD=doas
    else
        die "Nao encontrei sudo nem doas no sistema."
    fi
fi

# Every path is still validated as an absolute /usr path from CMake. In tests,
# only the filesystem root is redirected; production always uses the real path.
BUILD_DIRS=(
    "repos/libplasma/build"
    "repos/uac-polkit-agent/build"
    "repos/smod/build"
    "repos/smod/smodglow/build"
    "repos/smod/smodglow/build-wl"
    "repos/aeroshell-workspace/build"
    "repos/aeroshell-kwin-components/build"
    "repos/aeroshell-kwin-components/build_x11"
    "repos/aeroshell-sddm-kcm/build"
    "repos/aerothemeplasma-icons/build"
    "repos/aerothemeplasma-sounds/build"
    "build"
    "build_x11"
)

declare -A SEEN_FILES=()
declare -a INSTALLED_FILES=()
declare -a LOGICAL_FILES=()
declare -a MANIFESTS_USED=()
declare -a FILES_TO_REMOVE=()

add_manifest() {
    local manifest="$1"
    local path
    local resolved_path

    [[ -f "$manifest" ]] || return 0
    MANIFESTS_USED+=("$manifest")

    while IFS= read -r path || [[ -n "$path" ]]; do
        [[ -n "$path" ]] || continue

        case "$path" in
            /usr/*) ;;
            *)
                warn "Ignorando caminho fora de /usr no manifesto: $path"
                continue
                ;;
        esac

        case "/$path/" in
            *"/../"*)
                warn "Ignorando caminho com traversal no manifesto: $path"
                continue
                ;;
        esac

        resolved_path="$path"
        if [[ "$TEST_MODE" == "1" ]]; then
            resolved_path="$SYSTEM_ROOT$path"
        fi

        [[ -e "$resolved_path" || -L "$resolved_path" ]] || continue

        if [[ -z "${SEEN_FILES[$path]+present}" ]]; then
            SEEN_FILES["$path"]=1
            LOGICAL_FILES+=("$path")
            INSTALLED_FILES+=("$resolved_path")
        fi
    done < "$manifest"
}

package_owns_path() {
    local path="$1"

    case "$PACKAGE_MANAGER" in
        test)
            [[ -f "$TEST_OWNED" ]] && grep -Fxq -- "$path" "$TEST_OWNED"
            ;;
        *)
            # Check every package database available on the host. A system may
            # have more than one package manager installed, and any owner wins.
            if command -v pacman >/dev/null 2>&1 && pacman -Qo -- "$path" >/dev/null 2>&1; then
                return 0
            fi
            if command -v dpkg-query >/dev/null 2>&1 && dpkg-query -S -- "$path" >/dev/null 2>&1; then
                return 0
            fi
            if command -v rpm >/dev/null 2>&1 && rpm -qf -- "$path" >/dev/null 2>&1; then
                return 0
            fi
            if command -v apk >/dev/null 2>&1 && apk info --who-owns "$path" >/dev/null 2>&1; then
                return 0
            fi
            return 1
            ;;
    esac
}

archive_manifests() {
    local archive_root="$SCRIPT_DIR/manifest/consumed"
    local archive_dir
    local source
    local index=0

    (("${#MANIFESTS_USED[@]}" > 0)) || return 0
    mkdir -p "$archive_root"
    archive_dir="$(mktemp -d "$archive_root/run.XXXXXX")"

    for source in "${MANIFESTS_USED[@]}"; do
        [[ -f "$source" ]] || continue
        mv -- "$source" "$archive_dir/$(printf '%03d' "$index")-$(basename "$source")"
        index=$((index + 1))
    done

    log "Manifestos consumidos arquivados em: ${archive_dir#"$SCRIPT_DIR"/}"
}

rollback_snapshot_exists() {
    if [[ "$TEST_MODE" == "1" ]]; then
        [[ "${ATP_UNINSTALL_TEST_ROLLBACK_PENDING:-0}" == "1" ]]
        return
    fi

    local config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
    [[ -f "$config_home/aerothemeplasma/rollback/user.json" \
        || -f /var/lib/aerothemeplasma/rollback/system.json ]]
}

restore_configuration() {
    [[ "$TEST_MODE" == "1" ]] && return 0

    local restore_script="$SCRIPT_DIR/scripts/restore_config.py"
    local config_home="${XDG_CONFIG_HOME:-$HOME/.config}"

    if [[ ! -f "$config_home/aerothemeplasma/rollback/user.json" \
        && ! -f /var/lib/aerothemeplasma/rollback/system.json ]]; then
        return 0
    fi

    [[ -f "$restore_script" ]] || die "Snapshot de rollback existe, mas o script de restauracao esta ausente: $restore_script"
    command -v python3 >/dev/null 2>&1 || die "Python 3 e necessario para restaurar as configuracoes. Instale Python 3 e execute novamente."

    log "Restaurando configuracoes pessoais do KDE (somente arquivos sem alteracoes posteriores)..."
    local restore_status=0
    python3 "$restore_script" --scope user || restore_status=$?
    if [[ "$restore_status" -eq 1 ]]; then
        die "Falha ao ler ou restaurar o snapshot pessoal. Nenhum arquivo instalado sera removido."
    elif [[ "$restore_status" -eq 2 ]]; then
        warn "Configuracoes pessoais editadas depois da aplicacao do tema foram preservadas; o snapshot permanece para revisao."
    fi

    if [[ -f /var/lib/aerothemeplasma/rollback/system.json ]]; then
        log "Restaurando configuracoes globais e do SDDM..."
        restore_status=0
        "$SU_CMD" python3 "$restore_script" --scope system || restore_status=$?
        if [[ "$restore_status" -eq 1 ]]; then
            die "Falha ao ler ou restaurar o snapshot do sistema. Os arquivos do tema nao serao removidos."
        elif [[ "$restore_status" -eq 2 ]]; then
            warn "Configuracoes do sistema editadas depois da aplicacao do tema foram preservadas; o snapshot permanece para revisao."
        fi
    fi
}

# Collect both the archived manifests and older build-directory manifests.
shopt -s nullglob
for manifest in "$SCRIPT_DIR"/manifest/*_install_manifest.txt; do
    add_manifest "$manifest"
done
for build_dir in "${BUILD_DIRS[@]}"; do
    add_manifest "$SCRIPT_DIR/$build_dir/install_manifest.txt"
done

printf 'Foram encontrados %d caminho(s) existente(s) nos manifestos.\n' "${#INSTALLED_FILES[@]}"

if [[ "$ASSUME_YES" -eq 0 ]] && { [[ "${#INSTALLED_FILES[@]}" -gt 0 ]] || rollback_snapshot_exists; }; then
    [[ -t 0 ]] || die "Execucao sem terminal. Revise os manifestos/snapshots e execute novamente com --yes para confirmar."
    read -r -p "Deseja desinstalar o AeroThemePlasma e restaurar suas configuracoes? [y/N] " answer
    case "$answer" in
        [yY]|[yY][eE][sS]) ;;
        *)
            log "Desinstalacao cancelada."
            exit 0
            ;;
    esac
fi

restore_configuration

local_index=0
for path in "${LOGICAL_FILES[@]}"; do
    resolved_path="${INSTALLED_FILES[$local_index]}"
    local_index=$((local_index + 1))

    if package_owns_path "$path"; then
        warn "Preservando arquivo pertencente a um pacote instalado: $path"
        continue
    fi

    FILES_TO_REMOVE+=("$resolved_path")
done

if [[ "${#FILES_TO_REMOVE[@]}" -gt 0 ]]; then
    printf 'Arquivos que serao removidos: %d\n' "${#FILES_TO_REMOVE[@]}"
    if [[ "$TEST_MODE" == "1" ]]; then
        rm -f -- "${FILES_TO_REMOVE[@]}"
    else
        "$SU_CMD" rm -f -- "${FILES_TO_REMOVE[@]}"
        if command -v update-mime-database >/dev/null 2>&1; then
            "$SU_CMD" update-mime-database /usr/share/mime
        fi
    fi
else
    log "Nenhum arquivo elegivel para remocao; os arquivos pertencentes a pacotes foram preservados."
fi

# A consumed manifest must not be re-used after the distro package has been
# reinstalled. Archive the manifest sources only after all requested removals
# completed successfully; subsequent uninstalls cannot delete restored files.
archive_manifests

log "Desinstalacao concluida."
printf 'Arquivos pertencentes a pacotes da distribuicao foram preservados. Reinstale libplasma se a versao compilada do projeto o substituiu.\n'
