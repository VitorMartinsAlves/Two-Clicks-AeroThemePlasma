#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CUR_DIR="$SCRIPT_DIR"

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

on_error() {
    local exit_code=$?
    local line_no=$1
    printf '\n\033[1;31mA instalacao falhou na linha %s (codigo %s).\033[0m\n' "$line_no" "$exit_code" >&2
    printf 'Verifique a mensagem logo acima. Depois corrija o problema e execute este arquivo novamente.\n' >&2
    exit "$exit_code"
}
trap 'on_error $LINENO' ERR

ORIGINAL_ARGS=("$@")
INSTALL_ARGS=()
SKIP_DEPS=0
NO_HOST_SPAWN=0
ASSUME_YES=1

for arg in "$@"; do
    case "$arg" in
        --skip-deps)
            SKIP_DEPS=1
            ;;
        --no-host-spawn)
            NO_HOST_SPAWN=1
            ;;
        --yes|-y)
            ASSUME_YES=1
            ;;
        *)
            INSTALL_ARGS+=("$arg")
            ;;
    esac
done

if [[ -f /.flatpak-info && -z "${ATP_HOST_SPAWNED:-}" && "$NO_HOST_SPAWN" -eq 0 ]]; then
    if command -v flatpak-spawn >/dev/null 2>&1; then
        log "Detectei que voce esta dentro de um sandbox Flatpak; reexecutando no sistema host."
        exec flatpak-spawn --host env ATP_HOST_SPAWNED=1 bash -lc \
            'cd "$1" || exit 1; shift; exec bash ./install.sh "$@"' \
            bash "$CUR_DIR" "${ORIGINAL_ARGS[@]}"
    elif command -v host-spawn >/dev/null 2>&1; then
        log "Detectei que voce esta dentro de um sandbox Flatpak; reexecutando no sistema host."
        exec host-spawn env ATP_HOST_SPAWNED=1 bash -lc \
            'cd "$1" || exit 1; shift; exec bash ./install.sh "$@"' \
            bash "$CUR_DIR" "${ORIGINAL_ARGS[@]}"
    else
        die "Este terminal esta em Flatpak e nao encontrei flatpak-spawn/host-spawn para entrar no host."
    fi
fi

if [[ "$(id -u)" -eq 0 ]]; then
    die "Nao execute este script como root. Rode como usuario normal; ele pedira sudo/doas quando precisar."
fi

SU_CMD=sudo
if ! command -v "$SU_CMD" >/dev/null 2>&1; then
    SU_CMD=doas
    if ! command -v "$SU_CMD" >/dev/null 2>&1; then
        die "Nao encontrei sudo nem doas no sistema."
    fi
fi

has_arg() {
    local wanted=$1
    local arg
    for arg in "${INSTALL_ARGS[@]}"; do
        [[ "$arg" == "$wanted" ]] && return 0
    done
    return 1
}

source_os_release() {
    if [[ -r /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
    fi
}

detect_pkg_manager() {
    if command -v pacman >/dev/null 2>&1; then
        echo pacman
    elif command -v dnf >/dev/null 2>&1; then
        echo dnf
    elif command -v zypper >/dev/null 2>&1; then
        echo zypper
    elif command -v apt-get >/dev/null 2>&1; then
        echo apt
    else
        echo none
    fi
}

install_arch_deps() {
    local packages=(
        git
        cmake
        extra-cmake-modules
        ninja
        curl
        unzip
        qt6-virtualkeyboard
        qt6-multimedia
        qt6-5compat
        qt6-svg
        qt6-wayland
        plasma-wayland-protocols
        plasma5support
        shared-mime-info
        kvantum
        sddm
        sddm-kcm
        base-devel
        plasma-nm
        plasma-pa
        plasma-workspace
        plasma-desktop
    )

    if ! has_arg --skip-x11; then
        packages+=(kwin-x11 plasma-x11-session)
    fi

    local missing
    missing="$(pacman -T "${packages[@]}" || true)"
    if [[ -z "$missing" ]]; then
        log "Dependencias do CachyOS/Arch ja estao instaladas."
        return
    fi

    log "Instalando dependencias do CachyOS/Arch com pacman."
    printf '%s\n' "$missing"
    local pacman_flags=(-S --needed)
    if [[ "$ASSUME_YES" -eq 1 ]]; then
        pacman_flags+=(--noconfirm)
    fi
    "$SU_CMD" pacman "${pacman_flags[@]}" "${packages[@]}"
}

install_dependencies() {
    [[ "$SKIP_DEPS" -eq 1 ]] && {
        warn "Pulando instalacao de dependencias por causa de --skip-deps."
        return
    }

    source_os_release
    local manager
    manager="$(detect_pkg_manager)"

    case "$manager" in
        pacman)
            install_arch_deps
            ;;
        dnf|zypper|apt)
            warn "Detectei '$manager'. Para esta distro, instale as dependencias listadas no INSTALL.md e rode novamente."
            ;;
        none)
            warn "Nao encontrei gerenciador de pacotes conhecido. Instale as dependencias do INSTALL.md e rode novamente."
            ;;
    esac
}

set_install_dirs() {
    if [[ -z "${LIBEXEC_DIR:-}" ]]; then
        LIBEXEC_DIR=lib
    fi
    if [[ -z "${UAC_LIBEXEC_DIR:-}" ]]; then
        UAC_LIBEXEC_DIR=lib
    fi

    if command -v dnf >/dev/null 2>&1; then
        LIBEXEC_DIR=libexec
        UAC_LIBEXEC_DIR=libexec/kf6
    fi

    export LIBEXEC_DIR UAC_LIBEXEC_DIR
}

ensure_command() {
    command -v "$1" >/dev/null 2>&1 || die "Comando obrigatorio nao encontrado: $1"
}

ensure_tools() {
    ensure_command git
    ensure_command cmake
    ensure_command update-mime-database
}

clone_or_update() {
    local url=$1
    local dir=$2

    if [[ -d "$dir/.git" ]]; then
        log "Atualizando $dir"
        git -C "$dir" fetch --prune
        git -C "$dir" pull --ff-only
    elif [[ -e "$dir" ]]; then
        die "A pasta repos/$dir ja existe, mas nao e um repositorio git. Renomeie/remova essa pasta e rode de novo."
    else
        log "Clonando $dir"
        git clone "$url" "$dir"
    fi
}

build_install_cmake() {
    local source_dir=$1
    local build_dir=$2
    shift 2

    log "Configurando $source_dir ($build_dir)"
    cmake -DCMAKE_INSTALL_PREFIX=/usr "$@" -B "$build_dir" "$source_dir"
    log "Compilando $source_dir"
    cmake --build "$build_dir"
    log "Instalando $source_dir"
    "$SU_CMD" cmake --install "$build_dir"
}

copy_manifest() {
    local manifest_source=$1
    local manifest_target=$2

    if [[ -f "$manifest_source" ]]; then
        cp "$manifest_source" "$CUR_DIR/manifest/$manifest_target"
    else
        warn "Manifest nao encontrado: $manifest_source"
    fi
}

patch_aeroshell_kwin_components() {
    local cmake_file
    local files=(
        "$CUR_DIR/repos/aeroshell-kwin-components/effects_cpp/x11/kde-effects-aeroglassblur/CMakeLists.txt"
        "$CUR_DIR/repos/aeroshell-kwin-components/effects_cpp/x11/aeroglide/CMakeLists.txt"
        "$CUR_DIR/repos/aeroshell-kwin-components/effects_cpp/x11/startupfeedback/CMakeLists.txt"
        "$CUR_DIR/repos/aeroshell-kwin-components/effects_cpp/wayland/aeroglide/CMakeLists.txt"
        "$CUR_DIR/repos/aeroshell-kwin-components/effects_cpp/wayland/kde-effects-aeroglassblur/CMakeLists.txt"
        "$CUR_DIR/repos/aeroshell-kwin-components/effects_cpp/wayland/startupfeedback/CMakeLists.txt"
    )

    for cmake_file in "${files[@]}"; do
        [[ -f "$cmake_file" ]] || continue
        sed -i '/^add_definitions(${Qt6Widgets_DEFINITIONS})$/d' "$cmake_file"
    done
}

install_dependencies
set_install_dirs
ensure_tools

mkdir -p "$CUR_DIR/repos" "$CUR_DIR/manifest"
cd "$CUR_DIR/repos"

clone_or_update https://gitgud.io/aeroshell/libplasma.git libplasma
build_install_cmake "$CUR_DIR/repos/libplasma" "$CUR_DIR/repos/libplasma/build"
copy_manifest "$CUR_DIR/repos/libplasma/build/install_manifest.txt" libplasma_install_manifest.txt

clone_or_update https://gitgud.io/aeroshell/uac-polkit-agent.git uac-polkit-agent
build_install_cmake "$CUR_DIR/repos/uac-polkit-agent" "$CUR_DIR/repos/uac-polkit-agent/build" \
    "-DCMAKE_INSTALL_LIBEXECDIR=$UAC_LIBEXEC_DIR"
copy_manifest "$CUR_DIR/repos/uac-polkit-agent/build/install_manifest.txt" uac-polkit-agent_install_manifest.txt

clone_or_update https://gitgud.io/aeroshell/smod.git smod
log "Compilando e instalando smod"
(
    cd "$CUR_DIR/repos/smod"
    bash install.sh "${INSTALL_ARGS[@]}"
)
copy_manifest "$CUR_DIR/repos/smod/build/install_manifest.txt" smod_install_manifest.txt
copy_manifest "$CUR_DIR/repos/smod/smodglow/build-wl/install_manifest.txt" smodglow_install_manifest.txt
if ! has_arg --skip-x11; then
    copy_manifest "$CUR_DIR/repos/smod/smodglow/build/install_manifest.txt" smodglow-x11_install_manifest.txt
fi

clone_or_update https://gitgud.io/aeroshell/aeroshell-workspace.git aeroshell-workspace
build_install_cmake "$CUR_DIR/repos/aeroshell-workspace" "$CUR_DIR/repos/aeroshell-workspace/build"
"$SU_CMD" mkdir -p /usr/share/mime/packages
"$SU_CMD" update-mime-database /usr/share/mime
copy_manifest "$CUR_DIR/repos/aeroshell-workspace/build/install_manifest.txt" aeroshell-workspace_install_manifest.txt

clone_or_update https://gitgud.io/aeroshell/aeroshell-kwin-components.git aeroshell-kwin-components
patch_aeroshell_kwin_components
build_install_cmake "$CUR_DIR/repos/aeroshell-kwin-components" "$CUR_DIR/repos/aeroshell-kwin-components/build" \
    -DKWIN_BUILD_WAYLAND=ON
copy_manifest "$CUR_DIR/repos/aeroshell-kwin-components/build/install_manifest.txt" aeroshell-kwin-components_install_manifest.txt
if ! has_arg --skip-x11; then
    build_install_cmake "$CUR_DIR/repos/aeroshell-kwin-components" "$CUR_DIR/repos/aeroshell-kwin-components/build_x11" \
        -DKWIN_BUILD_WAYLAND=OFF \
        -DKWIN_INSTALL_MISC=OFF
    copy_manifest "$CUR_DIR/repos/aeroshell-kwin-components/build_x11/install_manifest.txt" aeroshell-kwin-components-x11_install_manifest.txt
fi

clone_or_update https://gitgud.io/aeroshell/aeroshell-sddm-kcm.git aeroshell-sddm-kcm
build_install_cmake "$CUR_DIR/repos/aeroshell-sddm-kcm" "$CUR_DIR/repos/aeroshell-sddm-kcm/build"
copy_manifest "$CUR_DIR/repos/aeroshell-sddm-kcm/build/install_manifest.txt" aeroshell-sddm-kcm_install_manifest.txt

clone_or_update https://gitgud.io/aeroshell/atp/aerothemeplasma-icons aerothemeplasma-icons
build_install_cmake "$CUR_DIR/repos/aerothemeplasma-icons" "$CUR_DIR/repos/aerothemeplasma-icons/build"
copy_manifest "$CUR_DIR/repos/aerothemeplasma-icons/build/install_manifest.txt" icons_install_manifest.txt

clone_or_update https://gitgud.io/aeroshell/atp/aerothemeplasma-sounds aerothemeplasma-sounds
build_install_cmake "$CUR_DIR/repos/aerothemeplasma-sounds" "$CUR_DIR/repos/aerothemeplasma-sounds/build"
copy_manifest "$CUR_DIR/repos/aerothemeplasma-sounds/build/install_manifest.txt" sounds_install_manifest.txt

build_install_cmake "$CUR_DIR" "$CUR_DIR/build" "-DCMAKE_INSTALL_LIBEXECDIR=$LIBEXEC_DIR"
copy_manifest "$CUR_DIR/build/install_manifest.txt" aerothemeplasma_install_manifest.txt
if ! has_arg --skip-x11; then
    build_install_cmake "$CUR_DIR" "$CUR_DIR/build_x11" \
        "-DCMAKE_INSTALL_LIBEXECDIR=$LIBEXEC_DIR" \
        -DINSTALL_X11_COMPONENTS=ON
    copy_manifest "$CUR_DIR/build_x11/install_manifest.txt" aerothemeplasma-x11_install_manifest.txt
fi

log "Instalacao concluida."
printf 'Reinicie a sessao do Plasma para carregar todos os componentes do AeroThemePlasma.\n'
