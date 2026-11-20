#!/usr/bin/env bash
set -Eeuo pipefail

WALL_DIR="$HOME/Documents/wallpapers"
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/hyprpaper.conf"
FILE="${1:-}"

case "$FILE" in
    1.png|2.png|3.png|4.png) ;;
    *) echo "Usage: $0 {1.png|2.png|3.png|4.png}" >&2; exit 2 ;;
esac

IMAGE="$WALL_DIR/$FILE"
[[ -f "$IMAGE" ]] || { echo "Wallpaper not found: $IMAGE" >&2; exit 1; }

mkdir -p "$(dirname "$CONFIG")"
TMP="${CONFIG}.tmp.$$"
cat > "$TMP" <<EOF
wallpaper {
    monitor =
    path = $IMAGE
    fit_mode = cover
}
EOF
mv -- "$TMP" "$CONFIG"

# Recent hyprpaper releases use a separate IPC protocol. Restarting the daemon
# makes the updated config apply without relying on the removed hyprctl IPC.
pkill -x hyprpaper 2>/dev/null || true
sleep 0.2
nohup hyprpaper >/dev/null 2>&1 </dev/null &
