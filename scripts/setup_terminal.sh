#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ORIGINAL_ARGS=("$@")

if [[ -n "${FLATPAK_ID:-}" && -z "${ATP_TERMINAL_HOST_SPAWNED:-}" ]]; then
    if command -v flatpak-spawn >/dev/null 2>&1; then
        exec flatpak-spawn --host env ATP_TERMINAL_HOST_SPAWNED=1 bash -lc \
            'cd "$1" || exit 1; shift; exec bash ./scripts/setup_terminal.sh "$@"' \
            bash "$SCRIPT_DIR/.." "${ORIGINAL_ARGS[@]}"
    elif command -v host-spawn >/dev/null 2>&1; then
        exec host-spawn env ATP_TERMINAL_HOST_SPAWNED=1 bash -lc \
            'cd "$1" || exit 1; shift; exec bash ./scripts/setup_terminal.sh "$@"' \
            bash "$SCRIPT_DIR/.." "${ORIGINAL_ARGS[@]}"
    fi
fi

INSTALL_BASH=1
INSTALL_FISH=0
INSTALL_KONSOLE=1
INSTALL_FONT=0
INSTALL_WINFETCH=1
PROFILE_NAME="AeroThemePlasma"
FONT_NAME="TerminalVector"
FONT_SIZE="9"
FONT_URL="https://www.yohng.com/files/TerminalVector.zip"
COLOR_SCHEME_NAME="WindowsCommandPrompt"
WINFETCH_LOGO="Windows 7"

log() {
    printf '==> %s\n' "$*"
}

warn() {
    printf 'Aviso: %s\n' "$*" >&2
}

die() {
    printf 'Erro: %s\n' "$*" >&2
    exit 1
}

usage() {
    cat <<EOF
Uso: $(basename "$0") [opcoes]

Opcoes:
  --no-bashrc        Nao altera ~/.bashrc
  --fish             Tambem altera ~/.config/fish/config.fish
  --no-fish          Nao altera ~/.config/fish/config.fish
  --no-konsole       Nao cria/atualiza perfil do Konsole
  --no-winfetch      Nao cria o comando ~/.local/bin/winfetch
  --install-font     Baixa e instala a fonte TerminalVector no usuario atual
  --profile-name N    Nome do perfil do Konsole (padrao: $PROFILE_NAME)
  --font-name N       Nome da fonte do perfil (padrao: $FONT_NAME)
  --font-size N      Tamanho da fonte do perfil (padrao: $FONT_SIZE)
  -h, --help         Mostra esta ajuda
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --no-bashrc)
            INSTALL_BASH=0
            ;;
        --fish)
            INSTALL_FISH=1
            ;;
        --no-fish)
            INSTALL_FISH=0
            ;;
        --no-konsole)
            INSTALL_KONSOLE=0
            ;;
        --no-winfetch)
            INSTALL_WINFETCH=0
            ;;
        --install-font)
            INSTALL_FONT=1
            ;;
        --profile-name)
            shift
            [[ $# -gt 0 ]] || die "--profile-name pede um valor."
            PROFILE_NAME="$1"
            ;;
        --font-name)
            shift
            [[ $# -gt 0 ]] || die "--font-name pede um valor."
            FONT_NAME="$1"
            ;;
        --font-size)
            shift
            [[ $# -gt 0 ]] || die "--font-size pede um valor."
            FONT_SIZE="$1"
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            die "Opcao desconhecida: $1"
            ;;
    esac
    shift
done

ensure_dependency() {
    command -v "$1" >/dev/null 2>&1 || die "Comando obrigatorio nao encontrado: $1"
}

replace_block() {
    local file="$1"
    local start_marker="$2"
    local end_marker="$3"
    local content="$4"

    local tmp
    tmp="$(mktemp)"

    if [[ -f "$file" ]]; then
        awk -v start="$start_marker" -v end="$end_marker" '
            $0 == start { skip = 1; next }
            $0 == end { skip = 0; next }
            !skip { print }
        ' "$file" > "$tmp"
    fi

    if [[ -s "$tmp" ]]; then
        printf '\n' >> "$tmp"
    fi

    printf '%s\n' "$content" >> "$tmp"
    mv "$tmp" "$file"
}

install_bashrc() {
    local bashrc="$HOME/.bashrc"
    local start="# >>> AeroThemePlasma terminal setup >>>"
    local end="# <<< AeroThemePlasma terminal setup <<<"

    log "Atualizando $bashrc"
    replace_block "$bashrc" "$start" "$end" "$(cat <<'EOF'
# >>> AeroThemePlasma terminal setup >>>
case $- in
    *i*)
        case ":$PATH:" in
            *:"$HOME/.local/bin":*) ;;
            *) export PATH="$HOME/.local/bin:$PATH" ;;
        esac

        PS1='C:${PWD//\//\\\\}> '
        printf '%s\n%s\n\n' \
            'Microsoft Windows [Version 6.1.7600]' \
            'Copyright (c) 2009 Microsoft Corporation.  All rights reserved.'
        ;;
esac
# <<< AeroThemePlasma terminal setup <<<
EOF
)"
}

install_fish_config() {
    local fish_dir="$HOME/.config/fish"
    local fish_config="$fish_dir/config.fish"
    local start="# >>> AeroThemePlasma terminal setup >>>"
    local end="# <<< AeroThemePlasma terminal setup <<<"

    mkdir -p "$fish_dir"
    log "Atualizando $fish_config"
    replace_block "$fish_config" "$start" "$end" "$(cat <<'EOF'
# >>> AeroThemePlasma terminal setup >>>
if status --is-interactive
    if not contains "$HOME/.local/bin" $PATH
        fish_add_path "$HOME/.local/bin"
    end

    printf '%s\n%s\n\n' \
        'Microsoft Windows [Version 6.1.7600]' \
        'Copyright (c) 2009 Microsoft Corporation.  All rights reserved.'

    function fish_prompt
        set -l path (string replace -a / '\' -- $PWD)
        printf 'C:%s> ' "$path"
    end
end
# <<< AeroThemePlasma terminal setup <<<
EOF
)"
}

install_konsole_profile() {
    local konsole_dir="$HOME/.local/share/konsole"
    local profile_file="$konsole_dir/$PROFILE_NAME.profile"
    local color_scheme_file="$konsole_dir/$COLOR_SCHEME_NAME.colorscheme"
    local konsolerc="$HOME/.config/konsolerc"

    mkdir -p "$konsole_dir"
    mkdir -p "$HOME/.config"

    log "Criando $color_scheme_file"
    cat > "$color_scheme_file" <<EOF
[Background]
Color=0,0,0

[BackgroundIntense]
Color=85,85,85

[Color0]
Color=0,0,0

[Color0Intense]
Color=85,85,85

[Color1]
Color=170,0,0

[Color1Intense]
Color=255,85,85

[Color2]
Color=0,170,0

[Color2Intense]
Color=85,255,85

[Color3]
Color=170,85,0

[Color3Intense]
Color=255,255,85

[Color4]
Color=0,0,170

[Color4Intense]
Color=85,85,255

[Color5]
Color=170,0,170

[Color5Intense]
Color=255,85,255

[Color6]
Color=0,170,170

[Color6Intense]
Color=85,255,255

[Color7]
Color=170,170,170

[Color7Intense]
Color=255,255,255

[Foreground]
Color=170,170,170

[ForegroundIntense]
Color=255,255,255

[General]
Description=$COLOR_SCHEME_NAME
Opacity=1
Wallpaper=
EOF

    log "Criando $profile_file"
    cat > "$profile_file" <<EOF
[Appearance]
AntiAliasFonts=false
BoldIntense=false
ColorScheme=$COLOR_SCHEME_NAME
Font=$FONT_NAME,$FONT_SIZE,-1,5,50,0,0,0,0,0
LineSpacing=0
UseFontLineChararacters=false

[Cursor Options]
BlinkingCursorEnabled=true
CursorShape=1

[General]
Command=/bin/bash
Name=$PROFILE_NAME
Parent=FALLBACK/
TerminalMargin=0

[Terminal Features]
BlinkingCursorEnabled=true
EOF

    if command -v kwriteconfig6 >/dev/null 2>&1; then
        log "Definindo $PROFILE_NAME como perfil padrao do Konsole"
        kwriteconfig6 --file "$konsolerc" --group "Desktop Entry" --key "DefaultProfile" --type string "$PROFILE_NAME.profile"
    else
        warn "kwriteconfig6 nao encontrado; nao foi possivel definir o perfil padrao automaticamente."
        warn "Abra o Konsole e selecione manualmente $PROFILE_NAME.profile em Manage Profiles."
    fi
}

install_font() {
    local fonts_dir="$HOME/.local/share/fonts"
    local tmp_dir
    local zip_path

    ensure_dependency curl
    ensure_dependency unzip

    mkdir -p "$fonts_dir"
    tmp_dir="$(mktemp -d)"
    zip_path="$tmp_dir/TerminalVector.zip"

    log "Baixando $FONT_NAME"
    curl -L "$FONT_URL" -o "$zip_path"
    unzip -o "$zip_path" -d "$tmp_dir" >/dev/null

    local font_file
    font_file="$(find "$tmp_dir" -type f \( -iname '*.ttf' -o -iname '*.otf' \) | head -n 1)"
    [[ -n "$font_file" ]] || die "Nao encontrei nenhum arquivo de fonte no pacote baixado."

    log "Instalando fonte em $fonts_dir"
    cp "$font_file" "$fonts_dir/"
    if command -v fc-cache >/dev/null 2>&1; then
        fc-cache -f "$fonts_dir" >/dev/null
    fi
}

font_is_installed() {
    command -v fc-match >/dev/null 2>&1 || return 1
    fc-match "$FONT_NAME" | grep -qi "$FONT_NAME"
}

install_winfetch_wrapper() {
    local bin_dir="$HOME/.local/bin"
    local wrapper="$bin_dir/winfetch"

    ensure_dependency fastfetch
    mkdir -p "$bin_dir"

    log "Criando $wrapper"
    cat > "$wrapper" <<EOF
#!/usr/bin/env sh
exec fastfetch --logo "$WINFETCH_LOGO" "\$@"
EOF
    chmod +x "$wrapper"
}

main() {
    if [[ "$INSTALL_BASH" -eq 0 && "$INSTALL_FISH" -eq 0 && "$INSTALL_KONSOLE" -eq 0 && "$INSTALL_FONT" -eq 0 && "$INSTALL_WINFETCH" -eq 0 ]]; then
        die "Nada para fazer."
    fi

    if [[ "$INSTALL_BASH" -eq 1 ]]; then
        install_bashrc
    fi

    if [[ "$INSTALL_FISH" -eq 1 ]]; then
        install_fish_config
    fi

    if [[ "$INSTALL_KONSOLE" -eq 1 ]]; then
        install_konsole_profile
    fi

    if [[ "$INSTALL_WINFETCH" -eq 1 ]]; then
        install_winfetch_wrapper
    fi

    if [[ "$INSTALL_FONT" -eq 1 ]]; then
        install_font
    else
        if ! font_is_installed; then
            warn "A fonte $FONT_NAME nao foi encontrada no sistema. Use --install-font ou instale-a manualmente."
        fi
    fi

    log "Concluido."
}

main
