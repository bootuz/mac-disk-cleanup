# mac-disk-cleanup

An agent skill that frees up disk space on a Mac without deleting anything you didn't pick.

Ask your agent something like *"my Mac is almost full"* or *"Xcode is eating my disk"*. It will:

1. **Survey** what is using space in a minute or two, with a read-only script that measures known hotspots in parallel instead of walking the whole disk.
2. **Propose** what can go, as a table with sizes and what happens if each item is removed, plus what it is leaving alone and why.
3. **Let you pick.** Nothing is removed until you choose.
4. **Clean up** only what you picked, using each tool's own command (`xcrun simctl runtime delete`, `brew cleanup`, `npm cache clean`, …) rather than `rm` where one exists.
5. **Report** the free space before and after, measured, not estimated.

It knows the usual developer hogs: Xcode DerivedData, simulator runtimes and devices, parallel-testing clones, SwiftUI preview simulators, device support files, archives, Instruments (`xctrace`) data left behind by killed recordings, Android emulators, package caches (npm, Homebrew, SwiftPM, pip, CocoaPods, Gradle, Go, Docker), `node_modules` and other build folders, local AI models. It also covers everyday ones: installers in Downloads, big files, apps you haven't opened in months, and iPhone backups.

## Safety

- The survey only reads. It changes nothing.
- Caches that rebuild themselves are deleted. Anything you made or can't easily get back (archives, emulators, downloads, apps) goes to the **Trash**, and the agent never empties the Trash for you.
- No `sudo`, `chmod` or `chflags`. When macOS privacy protection blocks something, the agent tells you how to do that item yourself.
- It leaves app data, the Photos library, Mail, System Data and anything currently in use (booted simulators, open Xcode projects) alone.
- Sizes are in decimal GB, so they match Finder and System Settings.

## Requirements

- **macOS.** The skill reads `~/Library` and runs macOS tools.
- **An agent that can run shell commands on your Mac**: [Claude Code](https://claude.com/claude-code) (terminal, desktop app, or IDE extension), or another agent supported by the [`skills` CLI](https://github.com/vercel-labs/skills).
- `python3` for the simulator runtime section. It comes with Xcode and the Command Line Tools. Xcode itself is optional; the developer sections are skipped without it.

## Install

Pick **one** method. Installing the same skill twice gives your agent two copies.

### Option 1: npx (any agent)

Uses the open [`skills` CLI](https://github.com/vercel-labs/skills) (Node.js 22.20 or later).

Install for Claude Code in all your projects:

```bash
npx skills add bootuz/mac-disk-cleanup -a claude-code -g
```

Or run it without flags to choose the agents (Claude Code, Codex, Cursor, …) and the scope interactively:

```bash
npx skills add bootuz/mac-disk-cleanup
```

Without `-g`, the skill goes into the current project only (`.claude/skills/` for Claude Code).

To update or remove it later:

```bash
npx skills update mac-disk-cleanup
```

```bash
npx skills remove mac-disk-cleanup -g
```

### Option 2: Claude Code plugin

This repository is also a Claude Code plugin marketplace. Inside Claude Code, run:

```
/plugin marketplace add bootuz/mac-disk-cleanup
/plugin install mac-disk-cleanup@mac-disk-cleanup
```

Or from a terminal:

```bash
claude plugin marketplace add bootuz/mac-disk-cleanup
```

```bash
claude plugin install mac-disk-cleanup@mac-disk-cleanup
```

Restart Claude Code (or start a new session) to load it. To update or remove it:

```bash
claude plugin marketplace update mac-disk-cleanup
```

```bash
claude plugin uninstall mac-disk-cleanup@mac-disk-cleanup
```

### Option 3: Manual copy

```bash
git clone https://github.com/bootuz/mac-disk-cleanup.git
```

```bash
mkdir -p ~/.claude/skills && cp -R mac-disk-cleanup/skills/mac-disk-cleanup ~/.claude/skills/
```

To install it for one project only, copy it into that project's `.claude/skills/` folder instead. To update it, pull and copy again. To remove it:

```bash
rm -rf ~/.claude/skills/mac-disk-cleanup
```

### Option 4: Upload the .skill file to the Claude app

Download `mac-disk-cleanup.skill` (or the same file as `mac-disk-cleanup.zip`) from the [latest release](https://github.com/bootuz/mac-disk-cleanup/releases/latest), or use [`dist/mac-disk-cleanup.skill`](dist/mac-disk-cleanup.skill) in this repository.

1. In Claude, turn on code execution: **Settings → Capabilities → Code execution and file creation**.
2. Go to **Customize → Skills**, click **+**, then **Create skill → Upload a skill**, and choose the file.

> **Note:** on claude.ai, code runs in a cloud sandbox, not on your Mac, so the skill can't see your disk there. Use it where the agent runs commands on your Mac itself, such as Claude Code (options 1–3 above).

## Usage

Once it's installed, just describe the problem. The skill triggers on its own:

- "My Mac says the disk is almost full. What can I delete?"
- "I can't install the macOS update, it needs 26 GB and I have 9."
- "What's taking up space on this Mac? Don't delete anything yet."
- "Xcode and the simulators are eating my disk, clean them up."

In Claude Code you can also call it by name: `/mac-disk-cleanup`, or `/mac-disk-cleanup:mac-disk-cleanup` when installed as a plugin.

If you just want the numbers, run the survey script on its own from a clone of this repository:

```bash
bash mac-disk-cleanup/skills/mac-disk-cleanup/scripts/survey.sh
```

## Repository layout

```
.claude-plugin/
  marketplace.json         Claude Code marketplace listing
  plugin.json              Claude Code plugin manifest
skills/mac-disk-cleanup/
  SKILL.md                 the skill's instructions
  scripts/survey.sh        read-only disk survey (bash 3.2 compatible)
dist/
  mac-disk-cleanup.skill   packaged skill (a zip) for uploading to the Claude app
```

## License

[MIT](LICENSE)
