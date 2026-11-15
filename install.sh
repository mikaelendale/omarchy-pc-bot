#!/bin/bash
# Install pc-bot for the current user, from wherever this folder lives.
#
#   ./install.sh               install, then connect your Telegram bot
#   ./install.sh --no-setup    install only (run `pc-bot setup` later)
#   ./install.sh --uninstall   remove it (asks before deleting your settings)
#
# Safe to run again: it only adds what's missing.

set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
BIN="$HOME/.local/bin/pc-bot"
UNIT_DIR="$HOME/.config/systemd/user"
UNIT="$UNIT_DIR/pc-bot.service"
HOOK="$HOME/.config/omarchy/hooks/post-update.d/pc-bot"
CLAUDE_SETTINGS="$HOME/.claude/settings.json"

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
ok()   { printf '  done: %s\n' "$*"; }
ask() {
  local reply hint="[y/N]"; [[ $2 == y ]] && hint="[Y/n]"
  read -r -p "$1 $hint " reply || true
  reply=${reply:-$2}; [[ $reply =~ ^[Yy] ]]
}

[[ $EUID -ne 0 ]] || { echo "Run it as yourself, not with sudo."; exit 1; }

# ------------------------------------------------------------------ uninstall
if [[ ${1:-} == "--uninstall" ]]; then
  bold "Removing pc-bot"
  systemctl --user disable --now pc-bot 2>/dev/null || true
  rm -f "$UNIT"; systemctl --user daemon-reload; ok "service removed"
  [[ -L $BIN ]] && rm -f "$BIN" && ok "command removed"
  rm -f "$HOOK"
  if [[ -f $CLAUDE_SETTINGS ]] && command -v jq >/dev/null; then
    tmp=$(mktemp)
    jq '(.hooks.Stop, .hooks.Notification) |= (if . then map(select(any(.hooks[]?; .command == "pc-bot claude") | not)) else . end)' \
      "$CLAUDE_SETTINGS" > "$tmp" && mv "$tmp" "$CLAUDE_SETTINGS" && ok "Claude Code hooks removed"
  fi
  if [[ -e /usr/local/lib/pc-bot ]]; then
    echo "  The root helper and security settings are still installed. Remove them with:"
    echo "    sudo $HERE/root/setup.sh --undo"
  fi
  if ask "Delete your settings and bot token (${XDG_CONFIG_HOME:-$HOME/.config}/pc-bot) and Inbox logs?" n; then
    rm -rf "${XDG_CONFIG_HOME:-$HOME/.config}/pc-bot" "${XDG_DATA_HOME:-$HOME/.local/share}/pc-bot" && ok "settings deleted"
  fi
  echo "This folder ($HERE) is left alone; delete it yourself if you like."
  exit 0
fi

bold "Installing pc-bot"

# ------------------------------------------------------------------ what it needs
command -v python3 >/dev/null || { echo "python3 is required."; exit 1; }
command -v hyprctl >/dev/null || echo "  Note: pc-bot is made for Omarchy (Hyprland); some features won't work elsewhere."

# Needed: what the core features call. Optional: features that switch off without them.
declare -A need=([grim]=grim [nmcli]=networkmanager [inotifywait]=inotify-tools [fuser]=psmisc
                 [bwrap]=bubblewrap [qrencode]=qrencode [magick]=imagemagick [notify-send]=libnotify [jq]=jq)
missing=()
for cmd in "${!need[@]}"; do command -v "$cmd" >/dev/null || missing+=("${need[$cmd]}"); done
if (( ${#missing[@]} )); then
  echo "  Missing packages: ${missing[*]}"
  if ask "Install them now (asks for your password)?" y; then
    if command -v omarchy >/dev/null; then omarchy pkg add "${missing[@]}"; else sudo pacman -S --needed "${missing[@]}"; fi
  else
    echo "  Skipped; the features that use them will stay off."
  fi
fi
command -v claude >/dev/null || echo "  Optional: Claude Code isn't installed, so talking to Claude from the bot is off."
command -v superwhisper >/dev/null || echo "  Optional: Superwhisper isn't installed, so voice notes are off."
command -v google-chrome-stable >/dev/null || command -v chromium >/dev/null \
  || echo "  Optional: no Chrome or Chromium, so cards come as text instead of images."

# ------------------------------------------------------------------ command
mkdir -p "$(dirname "$BIN")"
chmod +x "$HERE/pc-bot" "$HERE/root/"* "$HERE/omarchy-post-update.sh"
if [[ -e $BIN && ! -L $BIN ]]; then
  echo "  $BIN exists and isn't a link; left alone."
else
  ln -sfn "$HERE/pc-bot" "$BIN" && ok "command: pc-bot"
fi
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) echo "  Note: add ~/.local/bin to your PATH to run pc-bot by name.";; esac

# ------------------------------------------------------------------ service
mkdir -p "$UNIT_DIR"
[[ -L $UNIT ]] && rm -f "$UNIT"      # older installs linked the unit into the repo
cat > "$UNIT" <<EOF
[Unit]
Description=pc-bot: your PC on Telegram
PartOf=graphical-session.target
After=graphical-session.target network-online.target

[Service]
ExecStart=$HERE/pc-bot run
Environment=PATH=%h/.local/bin:/usr/share/omarchy/bin:/usr/local/bin:/usr/bin
Environment=PYTHONUNBUFFERED=1
Restart=on-failure
RestartSec=10

[Install]
WantedBy=graphical-session.target
EOF
systemctl --user daemon-reload
ok "background service (starts with your desktop once set up)"

# ------------------------------------------------------------------ hooks
if [[ -d $HOME/.config/omarchy ]]; then
  mkdir -p "$(dirname "$HOOK")"
  install -m 0755 "$HERE/omarchy-post-update.sh" "$HOOK" && ok "tells you when an Omarchy update finishes"
fi
if command -v claude >/dev/null && command -v jq >/dev/null; then
  mkdir -p "$(dirname "$CLAUDE_SETTINGS")"
  [[ -f $CLAUDE_SETTINGS ]] || echo '{}' > "$CLAUDE_SETTINGS"
  if jq -e '[.hooks.Stop[]?.hooks[]?.command] | index("pc-bot claude")' "$CLAUDE_SETTINGS" >/dev/null; then
    ok "Claude Code hooks already in place"
  else
    cp "$CLAUDE_SETTINGS" "$CLAUDE_SETTINGS.bak.$(date +%s)"
    tmp=$(mktemp)
    jq '.hooks.Stop = ((.hooks.Stop // []) + [{"hooks":[{"type":"command","command":"pc-bot claude","timeout":10}]}])
        | .hooks.Notification = ((.hooks.Notification // []) + [{"hooks":[{"type":"command","command":"pc-bot claude","timeout":10}]}])' \
      "$CLAUDE_SETTINGS" > "$tmp" && mv "$tmp" "$CLAUDE_SETTINGS"
    ok "Claude Code tells the bot when it finishes or needs you (settings backed up)"
  fi
fi

# ------------------------------------------------------------------ connect
if [[ ${1:-} == "--no-setup" ]]; then
  echo; echo "Installed. Connect your bot with: pc-bot setup"
  exit 0
fi
if [[ -s ${XDG_CONFIG_HOME:-$HOME/.config}/pc-bot/config.json ]]; then
  systemctl --user enable pc-bot >/dev/null 2>&1 || true
  systemctl --user restart pc-bot
  ok "already connected; restarted"
else
  echo
  "$HERE/pc-bot" setup
fi
echo
bold "Recommended next: lock it down"
echo "  Root commands from Telegram, an authenticator code for sensitive actions, and"
echo "  PC hardening. It shows the plan and asks first:"
echo "    sudo $HERE/root/setup.sh"
