# moremole

moremole is a personal fork of [Mole](https://github.com/tw93/Mole) by tw93, modified since October 2026. Mole and moremole are licensed under GPL-3.0 (see `LICENSE`); moremole is not affiliated with or endorsed by the Mole project. It keeps everything Mole does and changes these things:

- **The banner says MoreMole** and points to this repository, on the menu and the help screen. Its tagline keeps Mole's line, "Deep clean and optimize your Mac.", and adds "Manage, update and remove apps." The version screen (V) credits Mole and shows the moremole commit that is running.
- **The main menu lists every command** from Mole's More screen (M), not just the first five. Each command has its own row, with its preview (dry-run) and other variants beside it, and a line under the menu describes the highlighted item.
- **You can add your own commands to the menu,** and edit or remove them, right in the menu. They get a section of their own.
- **Commands open on their own screen, and their results stay on a screen you scroll like the menu,** with Clean's file list one key away. A cancelled command returns to the menu straight away.
- **Status fills the window:** its bars stretch with the window, it lists every CPU core, and it has a GPU card.
- **Software updates** finds updates for Homebrew apps and tools, App Store apps and macOS, and installs the ones you pick.
- **Update brings in Mole's latest changes and keeps moremole's.** Mole's own update would install the official release over this folder and erase them.

The moremole changes live in their own files, so Mole's updates merge cleanly:

| File | What it is |
|---|---|
| `lib/moremole/menu.sh` | The menu, your commands, and Update |
| `cmd/status/moremole.go` | Status: stretching bars and the GPU card |
| `bin/moremole-updates.sh`, `cmd/moremole-updates/` | Software updates: the screen, and the Go helper that finds updates |
| `lib/moremole/commands.sh` | Adds `updates` to help and Tab completion |
| `lib/moremole/cancel.sh` | Lets a cancelled command tell the menu to come straight back |
| `cmd/moremole-view/` | The results screen |
| `scripts/moremole-sync.sh` | Brings in Mole's latest changes |
| `tests/moremole_*.bats`, `cmd/status/moremole_test.go`, `cmd/moremole-updates/*_test.go`, `cmd/moremole-view/*_test.go` | Tests for the above |
| `mole`, `Makefile`, `lib/core/commands.sh`, `lib/core/common.sh`, `cmd/status/*.go` | A few marked lines (`moremole`) that hook the above in |
| Mole's commands: `bin/clean.sh`, `bin/completion.sh`, `bin/installer.sh`, `bin/purge.sh`, `bin/slim.sh`, `bin/touchid.sh`, `bin/uninstall.sh`, `lib/uninstall/batch.sh`, `lib/manage/whitelist.sh` | One `moremole_note_cancel` line at each place the user cancels (`tests/moremole_cancel.bats` checks they're all there) |

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
- builds Analyze, Status, Software updates and the results screen, which are written in Go, if one of them was never built (install Go first with `brew install go`); after that, the update rebuilds them whenever they change;
- offers Tab completion for `moremole` and `mm`, asking before it changes `~/.zshrc` (later: `moremole completion`);
- offers to remove the official Mole if Homebrew installed it, with `brew uninstall mole`, which keeps `~/.config/mole`. Don't use Mole's own `mo remove` for this: it also moves `~/.config/mole`, including your MoreMole commands, to the Trash;
- links Mole's own names, `mo` and `mole`, to MoreMole too, so scripts written for Mole keep working. A name that already runs something else, such as an official Mole you kept, stays as it is; run the installer again after removing that Mole to take the name over.

It's safe to run again. To undo it, delete `moremole`, `mm`, `mo` and `mole` from `~/.local/bin`.

## Scripts and the command line

Every command works from the command line and in scripts as in Mole: same commands, options, output and exit codes, and `moremole status --json` is unchanged. The menu's additions (own screens, the results screen, cancel) only happen when a command runs from the menu. The differences:

- `moremole update` (and `mo update` once `mo` runs MoreMole) brings in Mole's latest changes and rebuilds, instead of installing a Mole release; the help screen leaves out Mole's `--force` and `--nightly`, which MoreMole's update does not use.
- `moremole updates` (Software updates) is new.
- The help screen names commands `moremole ...`; hints inside commands still say `mo ...`.
- `remove` is Mole's own and is not in the menu: it would move `~/.config/mole`, with your menu commands and protected lists, to the Trash.

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
  Software updates       Preview
  Update MoreMole
  ── My commands ──
  + Add a command
  Flush DNS              Edit               Remove

  Free up disk space
```

- Move with the arrow keys and press Enter. Preview shows what a command would do without doing it.
- 1 to 5 still start Clean, Uninstall, Optimize, Analyze and Status directly. M (help) and V (version) show their screen and come back to the menu on Enter or Q; T, U and Q work as before.
- The help screen and update notices name commands `moremole ...` instead of `mo ...`.
- Each command opens on a clear screen. Touch ID, Installer files, Slim, Shell completion and Software updates show their name at the top; the others already show their own.
- When a command finishes, its output moves to the results screen, named after the menu item (for example "Clean · Preview") and opened at the end, where the summary is. Scroll with the arrow keys, PgUp and PgDn, or Home and End; in most terminals the trackpad scrolls it too. Enter, Q or ESC returns to the menu.
- After Clean's Preview, **F** on the results screen shows the list of files Clean would remove (`~/.config/mole/clean-list.txt`, which stays where Mole puts it), long paths wrapped in full; Q goes back to the results.
- The results screen keeps the colors and drops what was only on screen for a moment: progress spinners, pick lists, and screens a command cleared. The menu also clears the terminal's scrollback before and after each command, so output never piles up behind the menu.
- Analyze and Status come back as soon as you quit them. Ctrl-C stops a command and shows what it printed so far.
- If you cancel instead (Q or ESC in a pick list, or at the final "Enter confirm, ESC cancel" step), the menu comes back straight away, with nothing to dismiss. This covers Clean's password step, Uninstall, Purge, Installer files, Slim, Touch ID, Shell completion, Software updates and the Protected caches and Protected items lists.
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

If you pull changes with `git pull`, the next update rebuilds the Go parts if needed, or run `make build` yourself.

## Software updates

Choose **Software updates** in the menu, or run `moremole updates`. **Preview** (`moremole updates --dry-run`) only lists what's available.

It checks four places, then shows one list you pick from with the arrow keys and Space (A selects all), Enter to continue:

| Source | Starts selected | Installs with |
|---|---|---|
| Homebrew apps | yes | `brew upgrade --cask --greedy` |
| Homebrew apps that update themselves | no, marked "updates itself" | `brew upgrade --cask --greedy` |
| Move to Homebrew: apps you installed yourself that Homebrew has a newer version of | no | `brew install --cask --force`, which replaces your copy; settings stay |
| App Store apps | yes | `mas upgrade`, which may ask for your password |
| Command-line tools (Homebrew formulae) | no | `brew upgrade --formula` |
| macOS updates | no | `softwareupdate --install`, after your password |
| macOS updates that restart the Mac | no | opens Software Update in System Settings |

- A confirm screen lists your picks and warns about what they do (apps quit, your copy is replaced, a password is needed). Enter installs; any other key cancels.
- Each update runs with its own output on screen, then a summary says what updated and what didn't, and why. Each one is recorded in History.
- Checking can take a minute: Homebrew refreshes its version list first, and macOS is slowest to answer.
- No Homebrew: Homebrew apps and tools are skipped, with a note. No `mas` (the App Store tool): it offers to install it with Homebrew.
- Pinned formulae (`brew pin`) are left out. Apps that report no version number (`latest`) start unselected, since they always reinstall.
- An app joins "Move to Homebrew" only when exactly one Homebrew app matches its name, that app doesn't update itself, and its version is clearly newer. App Store and Apple apps never do.
- Software updates is a moremole addition. Mole leaves package management out on purpose, so this part won't be offered to Mole.

## Getting Mole's updates

Choose **Update MoreMole** in the menu, press U when an update notice shows, or run:

```sh
bash scripts/moremole-sync.sh
```

It first brings down any moremole changes already on GitHub, then copies Mole's latest changes into `main`, merges them into the `moremole` branch, and pushes both to GitHub. When one of the Go parts (Analyze, Status, Software updates, the results screen) is older than its code, including after a `git pull`, it rebuilds them (`make build`). It stops and says what to do if you have uncommitted changes, are on another branch, or if Mole changed the same lines as moremole.
