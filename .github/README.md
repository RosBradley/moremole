# MoreMole

MoreMole is a macOS cleanup and maintenance tool for the terminal, built on [Mole](https://github.com/tw93/Mole) by tw93. It does everything Mole does, from one menu, and adds software updates and AI model management.

```
➤ Clean                  Preview            Protected caches
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
  Software removal       Preview
  AI models              Preview            Download
  AI model removal       Preview
  Update MoreMole
───────────────────────── My commands ─────────────────────────
  Add a command
```

## What it adds to Mole

- **One menu for everything.** Every Mole command has its own row, with its preview (see what it would do, without doing it) beside it.
- **Your own commands** in the menu: add, edit and remove them without leaving it.
- **A results screen.** Commands run inside a fixed frame. When they finish, you can scroll back through everything they printed and search it with `/`.
- **Software updates.** Finds updates for Homebrew apps and tools, App Store apps, macOS and apps with their own updater, and installs the ones you pick.
- **AI models.** Checks your [Ollama](https://ollama.com) models for updates, downloads new ones from Ollama's library (with a check of whether they fit your Mac's memory), and removes the ones you pick.
- **Lists you can search** and sort by name, size or date. Nothing is ever selected for you.
- **A Status screen that fills the window,** with every CPU core and a GPU card.

## Install

Paste this into Terminal:

```sh
curl -fsSL https://raw.githubusercontent.com/RosBradley/moremole/moremole/moremole-get.sh | bash
```

Then open a new Terminal window and type `moremole`, or `mm` for short.

It needs macOS 12 or newer, on Apple silicon or Intel. It installs in your home folder and asks for no password. Every download is checked against the checksums published with its release.

## Update

When a new MoreMole release is out, the menu says so. Choose **Update MoreMole** to install it; your own commands and settings stay.

## Uninstall

Delete the `~/.local/share/moremole` folder, and the links MoreMole made in `~/.local/bin`: `moremole` and `mm`, and `mo` and `mole` if it made those. Your settings stay in `~/.config/mole` until you delete that too.

## Mole and MoreMole

MoreMole follows Mole closely: Mole's changes are brought in regularly, and Mole's commands, options and output work the same, so scripts written for Mole keep working. If you'd rather have the official Mole, get it at [github.com/tw93/Mole](https://github.com/tw93/Mole).

The full list of changes, and how each part works, is in [MOREMOLE.md](https://github.com/RosBradley/moremole/blob/moremole/MOREMOLE.md).

MoreMole is not affiliated with or endorsed by the Mole project. Like Mole, it is licensed under [GPL-3.0](https://github.com/RosBradley/moremole/blob/moremole/LICENSE).
