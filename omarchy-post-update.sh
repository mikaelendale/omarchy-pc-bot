#!/bin/bash
# Omarchy post-update hook: tell Telegram the update finished.
command -v pc-bot >/dev/null && pc-bot send "**Omarchy updated** · $(omarchy version 2>/dev/null | head -1)" >/dev/null 2>&1 || true
