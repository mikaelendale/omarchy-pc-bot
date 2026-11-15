#!/bin/bash
# pc-bot security setup: hardens this PC and turns on root commands from the
# bot, protected by an authenticator app on your phone.
#
#   sudo ./root/setup.sh          set up (shows the plan first)
#   sudo ./root/setup.sh --undo   put everything back
#   sudo ./root/setup.sh --update reinstall the root helpers only
#
# Every file it adds is its own drop-in (95-pc-bot-*), so undo just removes
# them; nothing of Omarchy's is edited.

set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
LIB=/usr/local/lib/pc-bot
ETC=/etc/pc-bot
STATE=/var/lib/pc-bot
SUDOERS=/etc/sudoers.d/50-pc-bot
SYSCTL=/etc/sysctl.d/95-pc-bot-harden.conf
NMCONF=/etc/NetworkManager/conf.d/95-pc-bot-privacy.conf
DNSCONF=/etc/systemd/resolved.conf.d/95-pc-bot-dns.conf

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
step() { printf '\n\033[1m%s\033[0m\n' "$*"; }
ok()   { printf '  done: %s\n' "$*"; }

[[ $EUID -eq 0 ]] || { echo "Run it with sudo: sudo $0 $*"; exit 1; }
USER_NAME=${SUDO_USER:-}
[[ -n $USER_NAME && $USER_NAME != root ]] || { echo "Run it with sudo from your own account."; exit 1; }
USER_UID=$(id -u "$USER_NAME")

ask() {   # ask "question" default(y|n)
  local reply hint="[y/N]"
  [[ $2 == y ]] && hint="[Y/n]"
  read -r -p "$1 $hint " reply || true
  reply=${reply:-$2}
  [[ $reply =~ ^[Yy] ]]
}

# ------------------------------------------------------------------ undo
if [[ ${1:-} == "--undo" ]]; then
  bold "Undo pc-bot security setup"
  rm -f "$SYSCTL"; sysctl -q -e --system >/dev/null 2>&1 || true
  ok "kernel settings back to Omarchy's (fully after a reboot)"
  rm -f "$NMCONF"; nmcli general reload conf >/dev/null 2>&1 || true
  ok "Wi-Fi uses its real address again (next connect)"
  rm -f "$DNSCONF"; systemctl restart systemd-resolved || true
  ok "DNS back to plain"
  rm -f "$SUDOERS"; ok "bot can no longer ask for root"
  rm -rf "$LIB"; ok "root helper removed"
  if ask "Also delete the authenticator secret and the lock state?" n; then
    rm -rf "$ETC" "$STATE" && ok "secret and state deleted (remove 'pc-bot' from your authenticator app)"
  fi
  exit 0
fi

# ------------------------------------------------------------------ update
# Reinstall just the two root helpers (after a code change); keeps the
# authenticator, the lock state and everything else.
if [[ ${1:-} == "--update" ]]; then
  [[ -d $LIB && -f $SUDOERS ]] || { echo "Not set up yet; run it without --update first."; exit 1; }
  install -o root -g root -m 0755 "$HERE/pc-bot-root" "$LIB/pc-bot-root"
  install -o root -g root -m 0755 "$HERE/pc-bot-root-admin" "$LIB/pc-bot-root-admin"
  ok "root helpers updated in $LIB (authenticator and state kept)"
  exit 0
fi

# ------------------------------------------------------------------ plan
bold "pc-bot security setup"
cat <<EOF

This will:
  1. Tighten the kernel: hide kernel addresses, block swapping in a new kernel
     while running, no memory dumps from setuid programs, no ICMP redirects,
     log spoofed packets, harden the BPF compiler.
  2. Wi-Fi privacy: a different random hardware address for each network
     (stays the same on the same network, so logins and captive portals work).
  3. Encrypt DNS whenever the server supports it (Quad9 does).
  4. Firewall: keep it on, blocking everything incoming, and log blocked tries.
  5. Root commands from the bot: install a small root-owned helper and a sudo
     rule for it. It runs a command only with a fresh 6-digit code from an
     authenticator app on your phone; 5 wrong codes turn it off until you
     unlock it here with your password.

Nothing of Omarchy's is edited; undo with: sudo $0 --undo
EOF
echo
ask "Go ahead?" n || { echo "Nothing changed."; exit 0; }

# ------------------------------------------------------------------ 1 kernel
step "1. Kernel"
cat > "$SYSCTL" <<'EOF'
# pc-bot security setup (pc-bot's root/setup.sh --undo removes this)
kernel.kptr_restrict = 2
kernel.kexec_load_disabled = 1
fs.suid_dumpable = 0
dev.tty.ldisc_autoload = 0
net.core.bpf_jit_harden = 2
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.tcp_rfc1337 = 1
EOF
sysctl -q -e -p "$SYSCTL" >/dev/null || echo "  (some settings didn't apply now; they will after a reboot)"
ok "kernel settings in $SYSCTL"

# ------------------------------------------------------------------ 2 wifi
step "2. Wi-Fi privacy"
cat > "$NMCONF" <<'EOF'
# pc-bot security setup: a stable random hardware address per network.
[device]
wifi.scan-rand-mac-address=yes

[connection]
wifi.cloned-mac-address=stable
ethernet.cloned-mac-address=stable
EOF
nmcli general reload conf 2>/dev/null || true
ok "takes effect the next time Wi-Fi connects (no disconnect now)"

# ------------------------------------------------------------------ 3 dns
step "3. DNS"
mkdir -p "$(dirname "$DNSCONF")"
cat > "$DNSCONF" <<'EOF'
# pc-bot security setup: encrypt DNS when the server supports it.
[Resolve]
DNSOverTLS=opportunistic
EOF
systemctl restart systemd-resolved && ok "encrypted DNS when available"

# ------------------------------------------------------------------ 4 firewall
step "4. Firewall"
if command -v ufw >/dev/null; then
  ufw --force enable >/dev/null
  ufw logging low >/dev/null
  ok "on, blocked tries are logged"
  ufw status verbose | sed 's/^/    /'
else
  echo "  ufw isn't installed; skipped."
fi

# ------------------------------------------------------------------ 5 root helper
step "5. Root commands from the bot"
install -d -o root -g root -m 0755 "$LIB"
install -o root -g root -m 0755 "$HERE/pc-bot-root" "$LIB/pc-bot-root"
install -o root -g root -m 0755 "$HERE/pc-bot-root-admin" "$LIB/pc-bot-root-admin"
install -d -o root -g root -m 0700 "$ETC" "$STATE"
printf '{"user": "%s", "uid": %s}\n' "$USER_NAME" "$USER_UID" > "$ETC/root.json"
chmod 0600 "$ETC/root.json"
ok "helper installed in $LIB (owned by root, you can't change it)"

tmp=$(mktemp)
printf '# pc-bot: the bot may run its root helper without a password, with no arguments.\n# The helper itself demands a fresh authenticator code for every command.\n%s ALL=(root) NOPASSWD: %s/pc-bot-root ""\n' "$USER_NAME" "$LIB" > "$tmp"
if visudo -cqf "$tmp"; then
  install -o root -g root -m 0440 "$tmp" "$SUDOERS"
  ok "sudo rule added ($SUDOERS)"
else
  rm -f "$tmp"; echo "  The sudo rule didn't validate; stopped before touching sudo."; exit 1
fi
rm -f "$tmp"

verify_code() {   # verify_code SECRET CODE -> exit 0 if valid now
  # The secret goes through the environment, never the command line: any
  # process can read other processes' command lines in /proc.
  PCB_SECRET="$1" PCB_CODE="$2" python3 -I - <<'PY'
import base64, hashlib, hmac, os, struct, sys, time
s = os.environ["PCB_SECRET"].upper(); key = base64.b32decode(s + "=" * (-len(s) % 8)); code = os.environ["PCB_CODE"]
def totp(step):
    m = hmac.new(key, struct.pack(">Q", step), hashlib.sha1).digest(); o = m[-1] & 15
    return "%06d" % ((struct.unpack(">I", m[o:o+4])[0] & 0x7FFFFFFF) % 1000000)
now = int(time.time()) // 30
sys.exit(0 if any(hmac.compare_digest(totp(t), code) for t in (now - 1, now, now + 1)) else 1)
PY
}

if [[ -s $ETC/totp.key ]] && ask "An authenticator is already linked. Keep it?" y; then
  ok "kept the existing authenticator"
else
  secret=$(python3 -I -c 'import base64,secrets;print(base64.b32encode(secrets.token_bytes(20)).decode().rstrip("="))')
  host=$(hostname)
  uri="otpauth://totp/pc-bot:${USER_NAME}@${host}?secret=${secret}&issuer=pc-bot&algorithm=SHA1&digits=6&period=30"
  echo
  bold "Scan this with your authenticator app (Aegis, 2FAS, Google Authenticator, 1Password...):"
  echo
  if command -v qrencode >/dev/null; then printf '%s' "$uri" | qrencode -t ansiutf8 -m 2; fi
  echo "  Or type this key by hand: $(echo "$secret" | sed 's/.\{4\}/& /g')"
  echo
  linked=0
  for try in 1 2 3; do
    read -r -p "Type the 6-digit code your app shows now: " code || true
    if [[ $code =~ ^[0-9]{6}$ ]] && verify_code "$secret" "$code"; then linked=1; break; fi
    echo "  That code didn't match. Check the phone's clock and try again."
  done
  if (( ! linked )); then
    echo "  Not linked. Run this script again to retry; root commands stay off until then."
    exit 1
  fi
  umask 077
  printf '%s\n' "$secret" > "$ETC/totp.key"
  chmod 0600 "$ETC/totp.key"
  unset secret uri
  ok "authenticator linked; the secret is readable by root only"
fi
printf '{"last_step": 0, "fails": 0, "disabled": false}' > "$STATE/root-state.json"
chmod 0600 "$STATE/root-state.json"

# ------------------------------------------------------------------ done
step "All set."
cat <<EOF
  Root from Telegram:   /sudo <command>, then send the code from your app.
  Turn it off anytime:  /lockdown in the bot (or 5 wrong codes).
  Turn it back on:      pc-bot unlock   (here at the PC, asks your password)
  Audit trail:          journalctl -t pc-bot-root

Worth doing too (not automated, they need you):
  - Telegram: Settings > Privacy and Security > Two-Step Verification (a cloud password).
  - Secure Boot with your own keys (sbctl), so nobody can swap the boot files
    while the laptop is off. Ask Claude to walk you through it; it touches firmware.
  - Install the pending updates: omarchy update
EOF
