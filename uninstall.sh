#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ASSUME_YES=0

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

SU_CMD=""
if command -v sudo >/dev/null 2>&1; then
    SU_CMD=sudo
elif command -v doas >/dev/null 2>&1; then
    SU_CMD=doas
else
    die "Nao encontrei sudo nem doas no sistema."
fi

# Build directories created by install.sh and its dependencies.
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

add_manifest() {
    local manifest="$1"
    local path

    [[ -f "$manifest" ]] || return 0

    while IFS= read -r path || [[ -n "$path" ]]; do
        [[ -n "$path" ]] || continue

        # install.sh uses CMAKE_INSTALL_PREFIX=/usr. Refuse unexpected paths
        # rather than allowing a malformed manifest to delete user data.
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

        # A broken symlink is still an installed filesystem entry.
        [[ -e "$path" || -L "$path" ]] || continue

        if [[ -z "${SEEN_FILES[$path]+present}" ]]; then
            SEEN_FILES["$path"]=1
            INSTALLED_FILES+=("$path")
        fi
    done < "$manifest"
}

# Prefer archived manifests; also inspect build directories for older installs.
shopt -s nullglob
for manifest in "$SCRIPT_DIR"/manifest/*_install_manifest.txt; do
    add_manifest "$manifest"
done
for build_dir in "${BUILD_DIRS[@]}"; do
    add_manifest "$SCRIPT_DIR/$build_dir/install_manifest.txt"
done

if [[ ${#INSTALLED_FILES[@]} -eq 0 ]]; then
    warn "Nenhum arquivo instalado do AeroThemePlasma foi encontrado nos manifestos."
    exit 0
fi

printf 'Foram encontrados %d arquivo(s) instalado(s) em /usr.\n' "${#INSTALLED_FILES[@]}"
printf 'A remocao usara somente os caminhos registrados nos manifestos do CMake.\n'

if [[ "$ASSUME_YES" -eq 0 ]]; then
    [[ -t 0 ]] || die "Execucao sem terminal. Revise os manifestos e execute novamente com --yes para confirmar."
    read -r -p "Deseja desinstalar o AeroThemePlasma? [y/N] " answer
    case "$answer" in
        [yY]|[yY][eE][sS]) ;;
        *)
            log "Desinstalacao cancelada."
            exit 0
            ;;
    esac
fi

log "Removendo arquivos registrados nos manifestos..."
"$SU_CMD" rm -f -- "${INSTALLED_FILES[@]}"

# Reset the first-run wizard flag; a quoted tilde would be treated literally.
if command -v kwriteconfig6 >/dev/null 2>&1; then
    kwriteconfig6 --file "$HOME/.config/aerothemeplasmarc" \
        --group OOTB --key wizardRun --type bool false
fi

log "Desinstalacao dos arquivos concluida."
printf 'Reinstale o pacote libplasma da sua distribuicao caso ele tenha sido substituido pela versao compilada do projeto.\n'
