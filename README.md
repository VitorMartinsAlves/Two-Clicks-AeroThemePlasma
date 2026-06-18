# Two-Clicks-AeroThemePlasma

Este repositorio e uma distribuicao personalizada do AeroThemePlasma com foco em reduzir o numero de passos manuais para instalar e ajustar o visual Windows 7 Aero em KDE Plasma, especialmente em sistemas Arch/CachyOS.

O objetivo nao e substituir o projeto original nem reivindicar autoria sobre o tema. A ideia deste repo e manter uma versao mais direta para uso pessoal/testes, com scripts auxiliares para automatizar partes que normalmente precisam ser feitas na mao depois da instalacao.

## Creditos ao projeto original

Todo o tema, componentes Plasma/KWin, plasmoids, assets e a maior parte do codigo pertencem ao projeto original:

- Repositorio original: https://gitgud.io/aeroshell/atp/aerothemeplasma
- Espelho GitHub oficial/read-only: https://github.com/aeroshell-desktop/aerothemeplasma
- Projeto original: AeroThemePlasma, do grupo AeroShell

Este repo preserva os creditos originais abaixo e deve ser tratado como fork/customizacao. Se voce quer acompanhar desenvolvimento upstream, issues oficiais, licenca e documentacao canonica, use o repositorio original no GitGud.

## Intuito deste repo

Este repo existe para deixar o setup mais proximo de "dois cliques":

- instalar dependencias comuns automaticamente em Arch/CachyOS quando possivel
- reexecutar scripts no host quando o terminal estiver dentro de sandbox Flatpak
- compilar e instalar os componentes principais com mensagens de erro mais claras
- gerar manifestos de instalacao para facilitar uninstall/debug
- automatizar ajustes opcionais do terminal para ficar mais parecido com o Command Prompt do Windows 7
- criar um wrapper `winfetch` baseado em `fastfetch --logo "Windows 7"`

## Alteracoes feitas neste fork

### Instalador principal

O [install.sh](./install.sh) foi reescrito para ser mais defensivo e automatizado:

- usa `bash` com `set -Eeuo pipefail`
- detecta terminal dentro de Flatpak e tenta reexecutar no host com `flatpak-spawn` ou `host-spawn`
- impede execucao direta como root
- detecta `sudo` ou `doas`
- instala dependencias comuns em Arch/CachyOS com `pacman -S --needed`
- aceita `--skip-deps` para pular dependencias
- aceita `--no-host-spawn` para impedir reexecucao fora do sandbox
- aceita `--skip-x11`, preservando a opcao upstream
- clona ou atualiza os repositorios auxiliares em `repos/`
- compila e instala componentes com uma funcao comum de CMake
- copia manifestos para `manifest/`
- aplica um pequeno patch local nos CMakeLists dos componentes KWin para remover `add_definitions(${Qt6Widgets_DEFINITIONS})` quando necessario
- atualiza o banco MIME em `/usr/share/mime`

### Ajuste de terminal

Foi adicionado [scripts/setup_terminal.sh](./scripts/setup_terminal.sh) para automatizar a parte opcional do terminal documentada pelo upstream:

- adiciona bloco controlado ao `~/.bashrc`
- opcionalmente configura `fish` com `--fish`
- cria perfil do Konsole `AeroThemePlasma.profile`
- cria esquema de cores `WindowsCommandPrompt`
- instala a fonte TerminalVector com `--install-font`
- cria `~/.local/bin/winfetch` como wrapper para `fastfetch --logo "Windows 7"`
- coloca `~/.local/bin` no `PATH` pelo bloco do shell

Uso:

```bash
bash scripts/setup_terminal.sh --install-font
```

### Documentacao

O [INSTALL.md](./INSTALL.md) recebeu uma nota apontando para `scripts/setup_terminal.sh`, para que o ajuste de terminal nao precise ser feito todo manualmente.

### O que nao esta incluido

Geckium nao esta incluido neste repo. Ele continua sendo um projeto externo de AngelBruni:

- https://github.com/angelbruni/Geckium

Se voce quiser usar Geckium junto com AeroThemePlasma, instale separadamente seguindo a documentacao oficial do Geckium. Este repositorio nao redistribui os arquivos dele.

## Como usar esta versao

Instalacao completa:

```bash
bash install.sh
```

Sem instalar dependencias automaticamente:

```bash
bash install.sh --skip-deps
```

Sem componentes X11:

```bash
bash install.sh --skip-x11
```

Ajuste opcional do terminal:

```bash
bash scripts/setup_terminal.sh --install-font
```

Depois da instalacao, reinicie a sessao do Plasma.

## Aviso

Este projeto altera componentes de sistema, temas, KWin, Plasma e terminal se voce executar scripts auxiliares, e pode quebrar sua sessao se usado em uma versao de Plasma diferente da esperada. Faca backup antes de usar.

---

# AeroThemePlasma upstream README

## HIATUS NOTICE: This is a long overdue announcement, but development will slow down significantly as a result of real life priorities I have to take care of first. Estimated time until I continue development is unknown, but don't expect anything significant in the following few months, until August, probably. Thank you for your patience and support.

## Microsoft® Windows™ is a registered trademark of Microsoft® Corporation. This name is used for referential use only, and does not aim to usurp copyrights from Microsoft. Microsoft Ⓒ 2025 All rights reserved. All resources belong to Microsoft Corporation.

## Introduction

This is a project which aims to recreate the look and feel of Windows 7 as much as possible on KDE Plasma, whilst adapting the design to fit in with modern features provided by KDE Plasma and Linux.

ATP is in constant development and testing, it has been tested on:

- Arch Linux x64 and other Arch derivatives
- Plasma 6.6.1, KDE Frameworks 6.23.0, Qt 6.10.2
- 96 DPI scaling, multi monitor
- X11, Wayland*

*AeroThemePlasma currently lacks full Wayland support, which may result in Wayland-specific issues. 

## This software comes "as is" without warranty of any kind. It's always recommended to make backups of your system just in case. I am not responsible for broken systems, please proceed with caution.

The Plasma 5 version of ATP is available as a tag in this repository, however it is unmaintained and no longer supported.

If you find my work valuable consider donating:

<a href='https://ko-fi.com/M4M2NJ9PJ' target='_blank'><img height='42' style='border:0px;height:42px;' src='https://storage.ko-fi.com/cdn/kofi2.png?v=3' border='0' alt='Buy Me a Coffee at ko-fi.com' /></a>

[![](https://img.shields.io/badge/Discord-5865F2?style=for-the-badge&logo=discord&logoColor=white)](https://discord.gg/ZDeT6vdqMp)

[AeroThemePlasma](https://github.com/aeroshell-desktop/aerothemeplasma) and all of its AeroShell components are available as read-only [GitHub mirrors](https://github.com/aeroshell-desktop/).

## Installation

See [INSTALL.md](./INSTALL.md) for a detailed installation guide.

## Credits 

Huge thanks to everyone who helped out along the way by contributing, testing, providing suggestions and generally making ATP possible:

### Forked code

- Intika's [Digital Clock Lite](https://store.kde.org/p/1225135/) plasmoid
- [Adhe](https://store.kde.org/p/1386465/), [oKcerG](https://github.com/oKcerG/QuickBehaviors) and [SnoutBug](https://store.kde.org/p/1720532) for making SevenStart possible
- Zren's [Win7 Show Desktop](https://store.kde.org/p/2151247) plasmoid
- [Mirko Gennari](https://store.kde.org/p/998614), DrGordBord and [bionegative](https://www.pling.com/p/998823) for making SevenBlack possible
- DrGordBord's [Windows 7 Kvantum](https://store.kde.org/p/1679903) theme
- [taj-ny](https://github.com/taj-ny)'s [kwin-effects-forceblur](https://github.com/taj-ny/kwin-effects-forceblur)

### Contributors
- [Souris-2d07](https://gitgud.io/souris) for making the following: 
    - Cursor theme
    - Plymouth theme (old)
    - SDDM theme
    - KWin decoration theme
    - Most KWin C++ effects
    - Other minor KWin features and scripts
- [That Linux Dude Dominic Hayes](https://github.com/dominichayesferen) for making the following: 
    - Lock screen UI 
    - Icon theme
- [catpswin56](https://gitgud.io/catpswin56/) for help with SevenTasks, Sound Mixer plasmoid, Gadgets menu, Polkit UAC skin, as well as many more contributions
- [QuinceTart10](https://github.com/QuinceTart10) and [Gamer95875](https://github.com/Gamer95875) for making the sound themes
- (In collaboration with) [kfh83](https://github.com/kfh83), [TorutheRedFox](https://github.com/TorutheRedFox) and [ALTaleX](https://github.com/ALTaleX531/dwm_colorization_calculator/blob/main/main.py) for figuring out accurate Aero glass blur and colorization effects
- [AngelBruni](https://github.com/angelbruni) for contributing several SVG textures, most notably the clock in DigitalClockLite Seven
- [ricewind012](https://github.com/ricewind012/) for .bashrc Microsoft Windows header
- [furkrn](https://gitgud.io/furkrn) for creating and maintaining the [Plymouth theme](https://github.com/furkrn/PlymouthVista)
- [IcyGuidance](https://gitgud.io/IcyGuidance) for designing the notification badges in SevenTasks

### Special Thanks 

- [MondySpartan](https://www.deviantart.com/mondyspartan/art/Windows-10-Year-2010-Edition-1016859431) for inspiring the notification design

### Cool projects you should really check out

- [Geckium](https://github.com/angelbruni/Geckium) by AngelBruni
- [Aero UserChrome](https://gitgud.io/souris/aero-userchrome) by Souris (Geckium in combination with Aero UserChrome works well with AeroThemePlasma)
- [VistaThemePlasma](https://gitgud.io/aeroshell/vtp/vistathemeplasma/) by catpswin56
- [LonghornThemePlasma](https://gitgud.io/catpswin56/longhornthemeplasma) by catpswin56
- [VB1ThemePlasma](https://gitgud.io/catpswin56/vista-beta-plasma) by catpswin56
- [Harmony](https://gitgud.io/catpswin56/harmony) by catpswin56
- [SMOD Themes](https://gitgud.io/catpswin56/smod-themes) by catpswin56, a collection of themes that can be used with the SMOD window decoration theme
- [X6Shell](https://gitgud.io/x6shell) by catpswin56
- [Ice2K.sys](https://toiletflusher.neocities.org/ice2k/) by 0penrc
- [AeroThemePlasma-Nix](https://github.com/nyakase/aerothemeplasma-nix/) by [nyakase](https://github.com/nyakase)

## Vista variant

Initially I wanted to make a Vista variant of AeroThemePlasma but [catpswin56](https://gitgud.io/catpswin56) beat me to it, use [VistaThemePlasma](https://gitgud.io/aeroshell/vtp/vistathemeplasma) if you want a Vista theme.

## Aero apps for AeroThemePlasma
- [Aero Dolphin](https://gitgud.io/atmk/dolphin-aero) by Albert Tomanek
- [Aero GwenView](https://gitgud.io/atmk/gwenview-aero) by Albert Tomanek
- [Aero KolourPaint](https://invent.kde.org/albert-tomanek/kolourpaint/-/tree/saribbon-aero) by Albert Tomanek
- [Gadgets](https://gitgud.io/catpswin56/win-gadgets) by catpswin56
- [WinXplorer](https://gitgud.io/catpswin56/winxplorer) by catpswin56
- [execbin](https://gitgud.io/catpswin56/execbin) (run dialog) by catpswin56
- [LinVer](https://gitgud.io/wackyideas/linver) (version dialog) by WackyIdeas
- [Device Manager](https://github.com/actuallyaridan/linux-devmgmt) by ActuallyAridan
- ~~[Sevulet](https://gitgud.io/snailatte/sevulet) by [snailatte](https://gitgud.io/snailatte)~~

To install most of these, the commands to run after cloning are: `mkdir build; cd build; cmake .. -DCMAKE_INSTALL_PREFIX=/usr; sudo make install`.

## Screenshots

### Desktop

![desktop](screenshots/desktop.png)

### Start Menu

![start_menu](screenshots/start_menu.png)
![start_menu_search](screenshots/start_menu_search.png)
![start_menu_apps](screenshots/start_menu_apps.png)
![start_menu_openshell](screenshots/start_menu_openshell.png)

### Clock

![clock](screenshots/clock.png)

### System Tray

![battery](screenshots/battery.png)
![systray](screenshots/system_tray.png)

### Sound Mixer 

![mixer](screenshots/mixer.png)
![mixer_expanded](screenshots/mixer_expanded.png)

### Notifications 

![notification](screenshots/notification.png)
![notification-progress](screenshots/notification-progress.png)

### Desktop Icons 

![desktop-icons](screenshots/icons.png)

### Lockscreen 

![lockscreen](screenshots/lockscreen.png)

### Aero Peek

![aero-peek](screenshots/peek.png)

### Alt-Tab Switcher

![alt-tab](screenshots/alt-tab.png)

### Colorization 

![colorization](screenshots/colorization.png)
Regular colorization:
![regular-colorization](screenshots/aeroblur.png)
Basic colorization:
![basic-colorization](screenshots/aeroblursimple.png)
Maximized opaque colorization:
![maximized-colorization](screenshots/aeroblur_opaque.png)

### Decorations

![decorations](screenshots/decorations.png)

Decoration themes:

![decoration-themes](screenshots/smod_theme.png)

### Gadgets 

![gadgets](screenshots/gadgets.png)

### Network details

![network-details](screenshots/network-details.png)

### Librewolf

![librewolf](screenshots/geckium.png)

### User Account Control (Polkit)

![uac](screenshots/uac.png)
![uac-trusted](screenshots/uac-trusted.png)

### Taskbar

![taskbar](screenshots/jumplist.png)
![taskbar_tooltips](screenshots/seventasks_media.png)
![taskbar_inactive](screenshots/seventasks_inactive.png)
![taskbar_compact](screenshots/seventasks_compact.png)
