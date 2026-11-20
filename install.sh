#!/usr/bin/env bash
# Black-White universal installer: Arch Linux + Fedora
# Run as a regular user: chmod +x install.sh && ./install.sh

set -Eeuo pipefail

SRC="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CFG="${XDG_CONFIG_HOME:-$HOME/.config}"
STAMP="$(date +%Y%m%d-%H%M%S)"
WALL_DIR="$HOME/Documents/wallpapers"

say()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m  %s\n' "$*" >&2; }
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }
ask()  { local answer; read -r -p "$1 [y/N] " answer; [[ "${answer,,}" == y || "${answer,,}" == yes ]]; }

if [[ $EUID -eq 0 ]]; then
    die "Не запускай установщик через sudo. Запусти ./install.sh от обычного пользователя — sudo будет вызван внутри."
fi

[[ -f "$SRC/hypr/hyprland.lua" ]] || die "Не найдена папка hypr/. Распакуй весь архив и запускай install.sh из корня проекта."
[[ -d "$SRC/waybar" && -d "$SRC/wofi" && -d "$SRC/mako" && -f "$SRC/mako/config" && -d "$SRC/temporal" ]] || die "В архиве отсутствуют необходимые папки waybar/, wofi/, mako/ или temporal/."

# Detect current distro only to show a helpful hint. User still chooses explicitly.
if [[ -r /etc/os-release ]]; then
    . /etc/os-release
    DETECTED="${ID:-unknown}"
else
    DETECTED="unknown"
fi

printf '\n'
printf '  BLACK-WHITE | Hyprland Lua setup\n'
printf '  ─────────────────────────────────\n'
printf '  Обнаруженная система: %s\n\n' "$DETECTED"
printf '  Выбери дистрибутив:\n'
printf '    1) Arch Linux и совместимые (EndeavourOS, Manjaro*)\n'
printf '    2) Fedora Linux\n'
printf '    0) Выход\n\n'
read -r -p '  Твой выбор [1/2/0]: ' DISTRO_CHOICE

case "$DISTRO_CHOICE" in
    1) DISTRO="arch" ;;
    2) DISTRO="fedora" ;;
    0) say "Установка отменена."; exit 0 ;;
    *) die "Неверный выбор. Запусти install.sh ещё раз и выбери 1, 2 или 0." ;;
esac

case "$DISTRO" in
    arch)
        command -v pacman >/dev/null 2>&1 || die "Выбран Arch, но pacman не найден. Проверь выбор дистрибутива."
        ;;
    fedora)
        command -v dnf >/dev/null 2>&1 || die "Выбрана Fedora, но dnf не найден. Проверь выбор дистрибутива."
        ;;
esac

printf '\n'
say "Выбрано: $([[ $DISTRO == arch ]] && echo 'Arch Linux' || echo 'Fedora Linux')"
warn "Будут установлены системные пакеты и скопированы конфиги Black-White."
warn "Существующие ~/.config/hypr, waybar и wofi будут сохранены в резервные копии."
if ! ask "Продолжить?"; then
    say "Установка отменена."
    exit 0
fi

# ---------- 1. Install packages ----------
if [[ "$DISTRO" == "arch" ]]; then
    say "Обновление баз пакетов и установка зависимостей Arch Linux..."
    sudo pacman -Syu --needed --noconfirm \
        hyprland hyprpaper hyprpolkitagent polkit \
        xdg-desktop-portal-hyprland xdg-desktop-portal-gtk \
        waybar wofi mako kitty dolphin \
        pipewire pipewire-pulse pipewire-alsa wireplumber \
        pavucontrol playerctl brightnessctl \
        bluez bluez-utils blueman \
        networkmanager \
        ttf-roboto ttf-font-awesome

    # hyprshot may be in the repos or in the AUR depending on the Arch derivative.
    if ! command -v hyprshot >/dev/null 2>&1; then
        if pacman -Si hyprshot >/dev/null 2>&1; then
            sudo pacman -S --needed --noconfirm hyprshot
        elif command -v yay >/dev/null 2>&1; then
            yay -S --needed --noconfirm hyprshot
        elif command -v paru >/dev/null 2>&1; then
            paru -S --needed --noconfirm hyprshot
        else
            warn "hyprshot не найден. Установи его из AUR (например, yay -S hyprshot), иначе ALT+S не будет работать."
        fi
    fi

elif [[ "$DISTRO" == "fedora" ]]; then
    # Fedora's base repositories may ship a Hyprland build that is too old
    # for this project's Lua config. Use a COPR that tracks current Hyprland.
    say "Подготовка DNF COPR..."
    if ! dnf copr --help >/dev/null 2>&1; then
        if dnf --version 2>/dev/null | head -n1 | grep -qi 'dnf5'; then
            sudo dnf install -y dnf5-plugins
        else
            sudo dnf install -y dnf-plugins-core
        fi
    fi
    dnf copr --help >/dev/null 2>&1 || die "Не удалось подключить команду 'dnf copr'. Установи DNF COPR plugin вручную."

    say "Подключение COPR nett00n/hyprland (сторонний репозиторий Hyprland)..."
    sudo dnf copr enable -y nett00n/hyprland

    say "Установка Hyprland и его компонентов из COPR..."
    sudo dnf install -y \
        hyprland hyprpaper hyprpolkitagent xdg-desktop-portal-hyprland

    say "Установка приложений и системных зависимостей из Fedora..."
    sudo dnf install -y \
        xdg-desktop-portal-gtk \
        waybar wofi mako kitty dolphin \
        pipewire pipewire-alsa pipewire-pulseaudio wireplumber \
        pavucontrol playerctl brightnessctl \
        bluez blueman \
        NetworkManager NetworkManager-tui \
        google-roboto-fonts fontawesome-fonts

    # Optional package: keep the rest of the installation usable if this
    # COPR build is temporarily unavailable.
    if ! command -v hyprshot >/dev/null 2>&1; then
        if sudo dnf install -y hyprshot; then
            say "hyprshot установлен."
        else
            warn "hyprshot не найден в подключённых репозиториях. ALT+S не заработает, пока не установишь hyprshot отдельно."
        fi
    fi
fi

# ---------- 2. Services ----------
if command -v systemctl >/dev/null 2>&1; then
    if systemctl list-unit-files bluetooth.service >/dev/null 2>&1; then
        if ask "Включить Bluetooth при запуске системы?"; then
            sudo systemctl enable --now bluetooth.service || warn "Не удалось включить Bluetooth."
        fi
    fi

    if ! systemctl is-active --quiet NetworkManager.service; then
        warn "NetworkManager сейчас не активен. В конфиге Waybar кнопка сети запускает nmtui."
        if ask "Включить NetworkManager? (если используешь другой менеджер сети, ответь N)"; then
            sudo systemctl enable --now NetworkManager.service || warn "Не удалось включить NetworkManager."
        fi
    fi

    systemctl --user enable --now pipewire.socket pipewire-pulse.socket wireplumber.service \
        >/dev/null 2>&1 || warn "Не удалось включить пользовательские PipeWire units автоматически. В KDE они обычно уже запускаются сами."
fi

# ---------- 3. Backup and install configs ----------
mkdir -p "$CFG"
for dir in hypr waybar wofi mako; do
    if [[ -e "$CFG/$dir" ]]; then
        backup="$CFG/${dir}.bak-${STAMP}"
        mv -- "$CFG/$dir" "$backup"
        say "Резервная копия: $backup"
    fi
    cp -a -- "$SRC/$dir" "$CFG/$dir"
    say "Установлено: $CFG/$dir"
done

mkdir -p "$CFG/hypr/scripts"
if [[ -d "$SRC/scripts" ]]; then
    cp -a -- "$SRC/scripts/." "$CFG/hypr/scripts/"
    chmod +x "$CFG/hypr/scripts/"*.sh 2>/dev/null || true
    say "Скрипты установлены: $CFG/hypr/scripts"
fi

# ---------- 4. Wallpapers ----------
mkdir -p "$WALL_DIR"
for i in 1 2 3 4; do
    if [[ -f "$SRC/temporal/$i.png" && ! -f "$WALL_DIR/$i.png" ]]; then
        cp -- "$SRC/temporal/$i.png" "$WALL_DIR/$i.png"
    fi
done
say "Обои установлены в $WALL_DIR"

# ---------- 5. Finish ----------
printf '\n'
say "Black-White установлен."
cat <<'EOF'

Следующие шаги:
  1. Выйди из текущей сессии KDE/GNOME.
  2. На экране входа выбери сессию Hyprland.
  3. После входа проверь мониторы командой: hyprctl monitors
  4. Если нужно, настрой монитор в ~/.config/hypr/hyprland.lua
  5. Если скриншоты не работают, проверь: command -v hyprshot
  6. Mako запускается автоматически вместе с Hyprland; настройки уведомлений: ~/.config/mako/config

Важно:
  - Установщик НЕ удаляет KDE Plasma, GNOME или текущий дисплейный менеджер.
  - Hyprland появится как отдельная сессия, если пакет дистрибутива
    установил desktop-файл сессии.
  - Fedora использует COPR nett00n/hyprland для актуальной Lua-версии
    Hyprland; это сторонний репозиторий, а не официальный репозиторий Fedora.
  - Mako устанавливается из репозитория выбранного дистрибутива и запускается
    автоматически в Hyprland. Тема уведомлений Black-White находится в ~/.config/mako/config.
  - Установка Hyprland не гарантирует, что конфиг идеально подойдёт
    к любому монитору и оборудованию: проверь имя монитора и раскладку.
EOF
