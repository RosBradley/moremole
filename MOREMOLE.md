# moremole

moremole is a personal fork of [Mole](https://github.com/tw93/Mole). It keeps everything Mole does and changes four things:

- **The main menu lists every command** from Mole's More screen (M), not just the first five. Each command has its own row, with its preview (dry-run) and other variants beside it, and a line under the menu describes the highlighted item.
- **You can add your own commands to the menu** with "Edit my commands...". They get a section of their own.
- **Commands return to the menu** when they finish.
- **Update brings in Mole's latest changes and keeps moremole's.** Mole's own update would install the official release over this folder and erase them.

The moremole changes live in their own files, so Mole's updates merge cleanly:

| File | What it is |
|---|---|
| `lib/moremole/menu.sh` | The menu, the editor for your commands, and Update |
| `scripts/moremole-sync.sh` | Brings in Mole's latest changes |
| `tests/moremole_menu.bats` | Tests for the above |
| `mole` | A few lines that hook the new menu in |

## Running it

moremole runs straight from its folder. Add this line to `~/.zshrc`, then open a new Terminal window:

```sh
alias mm="$HOME/Developer/moremole/mole"
```

Type `mm` to open the menu. The official Mole, if installed, stays available as `mo`.

Analyze and Status are written in Go, so they need building once, and again when Mole changes them (the update tells you when):

```sh
brew install go
cd ~/Developer/moremole
make build
```

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
  Update from Mole
  ── My commands ──
  Edit my commands...
  Flush DNS

  Free up disk space
```

- Move with the arrow keys and press Enter. Preview shows what a command would do without doing it.
- 1 to 5 still start Clean, Uninstall, Optimize, Analyze and Status directly. M, V, T, U and Q work as before.
- When a command finishes, press Enter to come back to the menu. Analyze and Status come back as soon as you quit them. Ctrl-C stops the command and also comes back.
- Update from Mole is the exception: it ends the menu, because it may have changed moremole's files. Type `mm` to start the new version.
- A window too short for every row scrolls with the arrow keys, and says so under the list.

## Your own commands

Choose **Edit my commands...**, then:

- **A** adds one: type the name the menu shows, then the command to run.
- **R** removes one by its number, after you confirm.
- **Enter** goes back to the menu.

Your commands appear under "Edit my commands...", one per row. Each runs with your shell (`$SHELL -c`), in the folder you started moremole from. Aliases from `~/.zshrc` aren't loaded there, so use the full command. Commands that use `sudo` ask for your password as usual.

They're saved in `~/.config/mole/my_commands`, one per line as name, a Tab, then the command. You can edit that file directly; lines starting with `#` are ignored.

## Getting Mole's updates

Choose **Update from Mole** in the menu, press U when an update notice shows, or run:

```sh
bash scripts/moremole-sync.sh
```

It copies Mole's latest changes into `main`, merges them into the `moremole` branch, and pushes both to GitHub. It stops and says what to do if you have uncommitted changes, are on another branch, or if Mole changed the same lines as moremole.
