# moremole

moremole is a personal fork of [Mole](https://github.com/tw93/Mole) by tw93, modified since October 2026. Mole and moremole are licensed under GPL-3.0 (see `LICENSE`); moremole is not affiliated with or endorsed by the Mole project. It keeps everything Mole does and changes these things:

- **The banner says MoreMole** and points to this repository, on the menu and the help screen. The version screen (V) credits Mole and shows the moremole commit that is running.
- **The main menu lists every command** from Mole's More screen (M), not just the first five. Each command has its own row, with its preview (dry-run) and other variants beside it, and a line under the menu describes the highlighted item.
- **You can add your own commands to the menu,** and edit or remove them, right in the menu. They get a section of their own.
- **Commands return to the menu** when they finish.
- **Status fills the window:** its bars stretch with the window, it lists every CPU core, and it has a GPU card.
- **Update brings in Mole's latest changes and keeps moremole's.** Mole's own update would install the official release over this folder and erase them.

The moremole changes live in their own files, so Mole's updates merge cleanly:

| File | What it is |
|---|---|
| `lib/moremole/menu.sh` | The menu, your commands, and Update |
| `cmd/status/moremole.go` | Status: stretching bars and the GPU card |
| `scripts/moremole-sync.sh` | Brings in Mole's latest changes |
| `tests/moremole_menu.bats`, `cmd/status/moremole_test.go` | Tests for the above |
| `mole`, `cmd/status/*.go` | A few marked lines (`moremole`) that hook the above in |

## Running it

moremole runs straight from its folder. Set up the `moremole` command, with `mm` as a short name for it, once:

```sh
cd ~/Developer/moremole
bash scripts/moremole-install.sh
```

Then open a new Terminal window and type `moremole` or `mm`.

The installer:

- links `moremole` and `mm` in `~/.local/bin` to this folder, so updates take effect straight away, and adds `~/.local/bin` to `PATH` in `~/.zshrc` if it isn't there;
- replaces an older `alias mm=` line in `~/.zshrc`;
- builds Analyze and Status, which are written in Go, if they were never built (install Go first with `brew install go`); after that, the update rebuilds them whenever they change;
- offers Tab completion for `moremole` and `mm`, asking before it changes `~/.zshrc` (later: `moremole completion`);
- offers to remove the official Mole if Homebrew installed it, with `brew uninstall mole`, which keeps `~/.config/mole`. Don't use Mole's own `mo remove` for this: it also moves `~/.config/mole`, including your MoreMole commands, to the Trash.

It's safe to run again. To undo it, delete `~/.local/bin/moremole` and `~/.local/bin/mm`.

## The menu

```
➤ Clean                  Preview            Protected caches
  Uninstall              Preview
  Optimize               Preview            Protected items
  Analyze                External drives
  Status
  History                Export
  Purge                  Preview            Choose folders
  Installer files        Preview
  Slim Intel code        Preview
  Touch ID               Preview
  Shell completion       Preview
  Update MoreMole
  ── My commands ──
  + Add a command
  Flush DNS              Edit               Remove

  Free up disk space
```

- Move with the arrow keys and press Enter. Preview shows what a command would do without doing it.
- 1 to 5 still start Clean, Uninstall, Optimize, Analyze and Status directly. M (help) and V (version) show their screen and come back to the menu on Enter or Q; T, U and Q work as before.
- The help screen and update notices name commands `moremole ...` instead of `mo ...`.
- When a command finishes, press Enter or Q to come back to the menu. Analyze and Status come back as soon as you quit them. Ctrl-C stops the command and also comes back.
- Update MoreMole is the exception: it ends the menu, because it may have changed moremole's files. Type `mm` to start the new version.
- A window too short for every row scrolls with the arrow keys, and says so under the list.

## Your own commands

They're at the bottom of the menu:

- **+ Add a command** asks for the name the menu shows, then the command to run. Leave the name empty to cancel.
- **Enter on a command's name** runs it.
- **Edit**, beside it, changes the name or the command. Press Enter to keep what's shown in brackets.
- **Remove** takes it off the menu, after you confirm.

Each runs with your shell (`$SHELL -c`), in the folder you started moremole from. Aliases from `~/.zshrc` aren't loaded there, so use the full command. Commands that use `sudo` ask for your password as usual.

They're saved in `~/.config/mole/my_commands`, one per line as name, a Tab, then the command. You can edit that file directly; lines starting with `#` are ignored, and the menu keeps them.

## Status

- The bars stretch to fill the window; make the window wider for longer bars.
- **R** changes how often Status refreshes: 0.5, 1, 2, 5 or 10 seconds, starting at 1. It remembers your choice. A line at the bottom shows the current setting and the keys.
- Every CPU core is listed. **C** cycles through 2, 4, 8 and all cores and remembers your choice; a window too short for all of them shows fewer.
- The GPU card shows total GPU use, updated with every refresh like CPU use, plus the chip and its GPU core count. macOS reports GPU use for the GPU as a whole, not for each GPU core.

If you pull changes with `git pull`, the next update rebuilds Analyze and Status if needed, or run `make build` yourself.

## Getting Mole's updates

Choose **Update MoreMole** in the menu, press U when an update notice shows, or run:

```sh
bash scripts/moremole-sync.sh
```

It first brings down any moremole changes already on GitHub, then copies Mole's latest changes into `main`, merges them into the `moremole` branch, and pushes both to GitHub. When Analyze or Status is older than its code, including after a `git pull`, it rebuilds them (`make build`). It stops and says what to do if you have uncommitted changes, are on another branch, or if Mole changed the same lines as moremole.
