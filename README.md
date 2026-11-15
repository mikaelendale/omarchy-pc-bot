# pc-bot

Your Omarchy PC on Telegram, through a bot that's yours alone. It tells you what
the PC is doing while you're away, lets you talk to Claude Code on it from your
phone, runs root commands behind an authenticator code, and can answer your own
Telegram chats in your voice.

Everything runs on your PC and talks only to your bot. There's no server in the
middle and nothing shared with anyone else.

## What you need

- [Omarchy](https://omarchy.org) (Arch + Hyprland) and a Telegram account.
- Optional: [Claude Code](https://claude.com/claude-code), for talking to Claude
  and drafting replies; Superwhisper, for voice notes; Chrome or Chromium, to draw
  status cards as images.

The installer checks the rest (grim, inotify-tools, bubblewrap, qrencode,
imagemagick...) and offers to install what's missing.

## Install

```
git clone https://github.com/mikaelendale/omarchy-pc-bot ~/.local/share/pc-bot-app
~/.local/share/pc-bot-app/install.sh
```

The installer sets up the `pc-bot` command and a background service, then connects
your bot:

1. In Telegram, open @BotFather, send `/newbot`, and pick a name. You get a token.
2. Paste the token when asked. It's hidden, and stored readable only by you.
3. Open your new bot and press Start. That chat is now the only one it listens to.

Then lock it down. The security setup shows its plan and asks before changing anything:

```
sudo ~/.local/share/pc-bot-app/root/setup.sh
```

Update with `pc-bot update`. Remove with `install.sh --uninstall` (and
`sudo root/setup.sh --undo` for the security part).

## Talk to Claude

In the bot's chat, type, send a voice note, or send a photo. Claude Code answers
from your PC. Its reply streams in live (Telegram rich-message drafts, with a
stop button) and lands as a formatted message: headings, tables, code.

- **Voice notes** are transcribed with Superwhisper; what it heard is quoted above the answer.
- **Photos** go to Claude with their caption ("What is this?" if none).
- **Visuals:** when a chart or card helps, Claude adds a `widget` block. The bot sends it
  as a Telegram widget, or, while Telegram hasn't enabled widgets for the bot (they're
  rolling out in steps), draws it with headless Chrome (network blocked) and sends a photo.
- `/look` (default): Claude can read files and search the web, but can't change anything.
- `/work`: Claude Code in auto mode, as in your terminal; its safety check blocks risky actions.
- `/new` starts a fresh conversation (it also resets after 12 quiet hours); `/stop` or the
  stop button cuts an answer short.

Claude works in your home folder; point it at your projects folder with
`pc-bot claude-dir ~/Work` so it picks up that folder's CLAUDE.md and memory.
Its own replies never trigger the "Claude finished" event.

## Your own chats

The bot can answer messages people send to your own Telegram account, through
Telegram Business. Set up once:

1. In @BotFather: `/mybots`, pick the bot, Bot Settings, turn on Business Mode
   (the docs now call it Secretary Mode).
2. In Telegram: Settings, Telegram Business, Chatbots (Chat Automation on the desktop
   app). Enter the bot's username, pick which chats it gets, and allow it to reply.

From then on, a new message in one of those chats shows up in the bot's chat as a
card, with a reply Claude wrote in your voice (your language, length and style in
that chat):

- **Send** sends it as you. **Another** writes a different one. **Skip** leaves it for
  you, and those messages don't come back on the next card.
- **Reply to the card** (text or a voice note) to say what to answer, like "say I can't
  make it, maybe Sunday". Claude writes that up in the chat's language and your style.
- **Unsend** takes a sent reply back.
- **Auto-reply to <name>** (per person) sends Claude's replies right away; you still
  get a card for each. It holds off after 6 replies to one person in 10 minutes, so two
  auto-repliers can't ping-pong forever.
- If you answer in Telegram yourself, the card goes away.
- Every message gets a draft, even "ok" or a sticker; you decide with Skip. Only
  auto-reply leaves out messages that need no answer (and tells you).
- **If someone sincerely asks whether you're using AI,** Claude never says no for you.
  It answers the rest of their message and leaves that question to you, and the card
  notifies you. If the question is all they wrote, the card is yours to answer.
  Auto-reply holds that message for you instead of sending.
- **`/style`** tells Claude how you text someone, on top of what it picks up from the
  chat: `/style Sam short, lowercase, no full stops`. `/style all ...` is for
  everyone; `/style Sam -` clears it. Drafts are short and casual by default, since the
  bot only sees your messages from after you connected it.

`/inbox` shows the connection, who has auto-reply, and pauses it all. Lockdown pauses
it too. Bursts are answered together, a few seconds after the last message.

Limits from Telegram: private chats only (no groups or channels); the bot only sees
messages from after you connected it; it can reply only within 24 hours of the
other person's last message.

The Claude that writes these replies is separate from the one you talk to: it has
no tools, no MCP servers, no memory and no saved transcript, and runs in an empty
folder. It only sees that chat's last 30 messages. Anyone can text you, so what they
write must never reach a Claude that can read files or run commands. For the same
reason, the chat logs (`~/.local/share/pc-bot/inbox/`, readable only by you) are off
limits to the Claude you talk to. If anyone else connects the bot to their own
account, it's ignored and you're told.

## /status

A live card (battery, heat, memory, disk, Wi-Fi, the window in front) that refreshes
every 6 seconds while it's on screen, once widgets are available to the bot. Until
then it arrives as an image of the same card.

## What it tells you

No emojis; every message is formatted text.

Always (important): a wrong password on the lock screen, sudo or a system prompt
(counted); battery at 10% and 5% while not charging; the PC turning on or shutting
down; someone else messaging the bot; the disk nearly full; a USB device or the
camera turning on while you're away.

Only while you're away (screen locked or screensaver on), unless you pick /all:
Claude finished or needs you; locked and unlocked; sleep and wake; charger in and
out, battery full, 20%; Wi-Fi changes; downloads finishing in ~/Downloads; app
crashes; Omarchy updates.

Messages sent while offline are kept and delivered later, stamped with the time.

## Commands

`/menu` gives buttons for everything. Typing `/` in the chat lists every command.

`/status` `/screen` `/apps` `/lock` `/say text` `/new` `/stop` `/look` `/work` `/sudo command`
`/logout` `/inbox` `/style name note` `/lockdown` `/away` `/all` `/quiet` `/help`

## Security

One-time setup at the PC (shows the plan and asks first; `--undo` puts it all back):

```
sudo <pc-bot folder>/root/setup.sh
```

It hardens the PC (kernel settings, a random Wi-Fi hardware address per network,
encrypted DNS when available, firewall logging) and links an authenticator app on
your phone by QR code. After that:

- **The bot is locked by default.** Claude, screenshots, windows and `/say` need the
  6-digit code from your authenticator app; one code unlocks it for an hour after you
  last use it (12 hours at most). Change it with `/session 90` or `pc-bot session 90`.
  `/logout` locks it right away. The timer counts time asleep, so a suspended laptop
  doesn't stay unlocked.
- **It fails closed.** Once the root helper is installed, a helper that stops answering
  means locked, not open. A code sent when nothing is waiting is deleted, never passed
  to Claude.
- **Root (`/sudo`) needs a fresh code for every command.** The code is checked by
  `pc-bot-root`, a root-owned helper that alone holds the secret (`/etc/pc-bot/totp.key`),
  so neither the bot nor anything running as you can fake one. Codes work once.
- **Five wrong codes lock everything down.** So does `/lockdown` (or `pc-bot lockdown`
  at the PC). Only `pc-bot unlock` at the PC, with your sudo password, turns it back on.
- **In look mode Claude's tools can't read or change** SSH and GPG keys, keyrings, cloud
  and Git credentials, browser profiles, Telegram's session, other Claude transcripts
  or this bot's token. In work mode it can run commands, so that rests on its safety check.
- Code messages are deleted from the chat once used. Only your account and chat are
  listened to; anyone else is reported. Every root command is in `journalctl -t pc-bot-root`.

After an update that changes `root/`, `pc-bot update` tells you to reinstall the
helpers (keeps the authenticator): `sudo <pc-bot folder>/root/setup.sh --update`

Also worth doing: Telegram's Two-Step Verification (a cloud password), and Secure Boot
with your own keys.

### How it holds up

- The root helper resets the resource limits sudo passes through, counts every attempt
  as a wrong code on disk before it compares the code, and answers every failure the
  same way. So no crash, full disk or limit can give free guesses or reveal whether a
  guess was right. A damaged state file means remote root is off.
- A /sudo card shows exactly the command that will run. Two code requests arriving
  together cancel each other, so nobody can swap in their own request for your code.
- A code sent when nothing is waiting is deleted, never passed to Claude.
- Buttons only trigger a fixed set of actions; a button's data is never run as a command.
- Claude's replies can't make Telegram fetch URLs or draw bot buttons. Cards are drawn
  by Chrome in a sandbox with no network and no access to your files.
- /work starts a fresh conversation, so nothing read in look mode carries over.

### What it can't protect against

- **Anything running as you.** Malware (or Claude in /work mode, if a web page or file
  talks it into it) can read the bot token, read Telegram's messages before the bot
  does, and use your next code itself. That's the same line as sudo: code running as
  you can also capture your sudo password. The bot warns you if its messages start
  going to another program; don't send codes after that warning.
- **Your phone.** Telegram plus your authenticator app on one unlocked phone is
  everything. Keep the phone locked; `pc-bot lockdown` at the PC cuts it off.
- **Your Telegram account while unlocked.** The unlock is per chat, so anyone else
  signed in to your Telegram can use the bot during that hour too.
- **Telegram itself.** Bot chats aren't end-to-end encrypted: commands, root output,
  screenshots and Claude's answers are stored on Telegram's servers.
- **Prompt injection in look mode.** Claude can still read your files (except the
  blocked ones) and fetch web pages, so a hostile page could get it to send file
  contents to a URL with its web fetch.
- **The bot token, once your chats are connected.** Whoever holds it can read new
  messages in the chats you picked and reply as you there (within 24 hours of their
  last message). Keep the list of chats short; disconnecting in Telegram cuts it off.
- **The phone's clock.** Codes depend on both clocks; if the PC's clock drifts more
  than 30 seconds, real codes count as wrong ones.

## Files

- `pc-bot` the bot (Python, standard library only)
- `install.sh` install, update wiring, uninstall
- `root/setup.sh` the security setup; `root/pc-bot-root` and `root/pc-bot-root-admin`
  are the root helpers it installs in `/usr/local/lib/pc-bot`
- `~/.config/pc-bot/config.json` your token, chat and settings (readable only by you)

## License

MIT
