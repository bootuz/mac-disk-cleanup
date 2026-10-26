---
name: mac-disk-cleanup
description: Free up disk space on a Mac safely. Surveys what is using storage in about a minute without walking the whole disk, proposes what can go with sizes and consequences, lets the user pick, removes it with each tool's own commands, and reports the space freed. Covers Xcode DerivedData, iOS simulator runtimes and devices, device support files, archives, Android emulators, npm/Homebrew/SwiftPM/pip/CocoaPods/Gradle/Docker caches, node_modules and other build folders, big downloads and installers, unused apps, and iPhone backups. Use this whenever someone says their Mac, disk or storage is full or low, can't install a macOS update for lack of space, asks what is taking up space, wants to clean up, free up or reclaim storage, or complains that Xcode, simulators, Docker or caches are eating their disk — even if they never say "cleanup".
---

# Mac disk cleanup

The job has five steps, in this order: **survey → propose → the user picks → clean up → report.** The order is the point. A cleanup frees space that's easy to get back, but one wrong deletion (an iPhone backup, the archive with the debug symbols of a shipped release, a Docker volume holding a database) costs more than all the space freed. So nothing is removed until the user has seen it in a proposal and picked it.

If the user only asks what is taking up space, or says not to delete anything yet, stop after the proposal.

**Start from the problem they actually have.** If they mention a symptom, such as an update that won't install or a "disk almost full" warning, check it while the survey runs.
- `softwareupdate --list` shows whether an update is pending.
- Major macOS upgrades want a few tens of GB free; minor updates need much less.

If there's already plenty of space, say that first, then offer the cleanup as optional. On a developer Mac, free space swings by tens of GB as Xcode runs tests and builds, so a warning can be stale by the time you look.

## Ground rules

- **Use the owning tool's command when there is one** (`xcrun simctl runtime delete`, `npm cache clean`, `brew cleanup`) rather than `rm`. The tool keeps its own records consistent: deleting a simulator runtime through simctl also removes its dyld cache and its registration, while `rm` leaves Xcode pointing at files that are gone.
- **Caches that rebuild themselves can be deleted outright. Anything the user made or can't easily get back goes to the Trash** with `/usr/bin/trash <path>` (on older macOS without it: `osascript -e 'tell application "Finder" to delete POSIX file "<path>"'`). Don't empty the Trash yourself: emptying it is the user's call. Tell them that the space only comes back once they empty it.
- **No `sudo`, `chmod` or `chflags` to get past a refusal.** "Operation not permitted" usually means macOS privacy protection or a sandbox. Report it, and tell the user how to do that one item themselves.
- **Report sizes in decimal GB**, the way Finder and System Settings do, so your numbers match what the user sees.

## 1. Survey

Run the bundled script. It only reads, and it usually takes 1–3 minutes:

```bash
bash <this skill's folder>/scripts/survey.sh
```

Run it in the background if your shell times out sooner, and tell the user in a line what you're doing while it runs.

It measures a fixed list of known hotspots in parallel. Then it lists the details you need to judge them: simulator runtimes with their last-used dates, simulator devices, DerivedData per project, device support folders, Android emulators, project build folders, big files, and apps with their last-opened dates.

Don't replace it with `du -sh ~/*` or `du` over `~/Library`. On a real Mac that takes over 10 minutes, and it overcounts. Online-only files in `~/Library/CloudStorage` and iCloud Drive get counted, and mounted simulator images under `/Library/Developer/CoreSimulator/Volumes` duplicate the runtimes. One run reported `~/Library` at 720 GB on a 494 GB disk. If the script's totals don't explain where the space went, drill into one folder at a time: `du -skx <folder>/* | sort -rn | head`.

How to read the output:
- **`[no access]`** means macOS privacy protection blocked the read. This happens for Mail, Messages, the Photos library, iPhone backups, the Trash and some app containers. It does not mean empty. Say you couldn't see inside, and point to where the user can look: System Settings → General → Storage, or Finder → their iPhone → Manage Backups.
- **`[partial]`** means the size is a lower bound.
- **"last opened unknown"** for an app means Spotlight has no date. It doesn't mean the app was never opened.
- **"Running now"** lists Xcode, booted simulators, Android emulators and Docker. Whatever those are using is off limits for this cleanup.
- **A size bigger than makes sense means APFS clones.** `du` and Finder count cloned data once per copy, so a folder of clones can claim more than the whole disk. Common cases:
  - Xcode's parallel-testing clones (the script reports how many there are rather than a size),
  - Chrome's `code_sign_clone` folders in `/private/var/folders`,
  - duplicated project folders.

  Don't write scripts to measure clones exactly: it takes many minutes, and the methods disagree by a factor of ten. Say "shows as X, really much less", and let the free space after removal give the true number.
- **`~/Library/Developer/CoreDevice`** is a live view of connected devices and booted simulators. It isn't stored on disk, so ignore its size.
- **Space the survey doesn't account for** is in places you couldn't read (Photos, Mail, Messages, backups, the Trash) or is macOS system data. Say that, and don't attribute the gap to some other item.

## 2. Decide what's safe

Judge each candidate by three things: how big it is, when it was last used, and what it costs the user to get it back. Below are the usual suspects and how to decide on each.

### Developer files

- **Simulator runtimes** (often the biggest win, 7–9 GB each). The script lists their size and last-used date. "Never" means the runtime was never booted. Propose removing runtimes that were never used, or not used in months. Keep:
  - any runtime a booted simulator uses,
  - anything used in the last few weeks,
  - the newest version of each major release.

  Each runtime's dyld cache (3–4 GB, under `/Library/Developer/CoreSimulator/Caches/dyld/`) goes away with it. Count that in the estimate.
- **Simulator devices.** The script shows each one's size and `lastUsedAt`. A device whose runtime is gone is marked `[unavailable]` and can be deleted. Deleting a device you still use costs every app and every bit of test data installed in it. So propose only devices unused for months, as their own option, listed by name.
- **Parallel-testing clones** (`~/Library/Developer/XCTestDevices`). Xcode makes copies of a simulator to run tests in parallel and often leaves them behind, sometimes with dozens of empty folders.
  - They're always safe to remove when no tests are running, because Xcode makes new ones when it needs them.
  - Present them as "shows as N GB in Finder, really a few GB", not as the biggest win.
- **SwiftUI preview simulators** (`~/Library/Developer/Xcode/UserData/Previews`, often 5–10 GB). Safe to remove; the next preview takes longer to start. Ask the user to close any open preview canvas first.
- **Claude Code scratch folders** (`/private/tmp/claude-<uid>/<project>/<session>`). These hold a session's working files, such as build copies and test output, and can reach tens of GB.
  - If the script marks one as changed in the last hour, a session is using it. Leave it alone, and never touch the scratch folder of the session you're running in.
  - Older ones can go. macOS also empties `/tmp` on restart.
- **Xcode's coding assistant** (`CodingAssistant`) holds model data. Mention it, but leave it unless the user says they don't use the feature.
- **DerivedData.** Always safe to delete. The only cost is a slower first build and a re-index. The script shows one folder per project; several folders for one project usually come from different checkouts or worktrees. If Xcode is open, it immediately recreates the folder for the open project. That's harmless; just expect a little to come back.
- **Device support** (`iOS DeviceSupport`, about 5–7 GB per iOS version). These are debug symbols copied from a connected device. Keep the newest folder for each device model. The others come back automatically if that device connects again on that iOS version.
- **Archives.** These hold the dSYMs for builds that shipped, and crash reports need them unless they were uploaded to App Store Connect or Crashlytics. Propose only old ones, list them by date, and move them to the Trash.
- **Android.** Emulators live in `~/.android/avd`: move both `<name>.avd` and `<name>.ini` to the Trash. SDK system images can be reinstalled with `sdkmanager`.
- **Package caches** (npm, Homebrew, Yarn, pnpm, pip, CocoaPods, SwiftPM, Gradle, Go, `~/.cache/<tool>`). These are safe to delete; tools download what they need again. Before you remove a folder under `~/.cache`, check what each one is.
- **Project build folders** (`node_modules`, `Pods`, `.build`). Safe in projects the user hasn't touched for a while, and they come back with `npm install`, `pod install` or `swift build`. For active projects, mention them but don't push. The script shows each project's last-changed date.
- **Docker.** Build cache and dangling images are safe. Volumes can hold databases, so never prune volumes without naming each one to the user.
- **Local AI models** (`~/.ollama`, LM Studio). These are the user's downloads. Propose them per model; remove with `ollama rm <model>`.

### Everyday files

- **Installers in Downloads** (`.dmg`, `.pkg`, `.xip`, `.zip`) for apps that are already installed can go to the Trash.
- **Other big files.** List them with dates and let the user decide. Never guess that a video or document is junk.
- **Apps.** Big apps not opened in 6+ months, and leftover `Install macOS …` apps, can go to the Trash. Tell the user that the app's data in `~/Library` stays behind.
- **iPhone/iPad backups** are usually blocked from reading. Point to Finder → the device → Manage Backups.
- **App caches** in `~/Library/Caches/<app>` are safe to delete while the app is closed. Usually these are small wins.

### Leave alone, and say so

- `~/Library/Application Support/<app>` is app data and settings. For example, `Claude/vm_bundles` is the Claude app's Cowork virtual machine. These should only be removed from inside the app.
- The Photos library is managed by Photos (Settings → iCloud → Optimize Mac Storage), and mail by Mail's settings.
- System Data, `/System` and `/private/var` are managed by macOS. The same goes for Time Machine local snapshots: macOS frees them by itself when space runs low.
- Anything the current session is running from.

## 3. Propose

Show the current free space. Then show one table, biggest first, with what can go, how big it is, and what happens if it's removed. Each row says concretely what stays, so the user can trust that the cleanup is selective. Give the total, then a short list of what you're deliberately leaving alone. Give sizes there too, so the user can see the whole picture add up.

Then let the user pick. Use a multi-select question if your tools have one. Group the rows into 4–6 options and put the size in each label. Don't remove anything until they answer.

Example from a real run:

> Your disk is 494 GB with about **31 GB free**, and almost all of the space goes to Xcode and simulator files.
>
> | What | Size | What happens if it's removed |
> |---|---|---|
> | **5 simulator runtimes you've never used** (iOS 18.0, 18.1, 18.2, 18.4, a 27.2 beta) plus their caches | ~53 GB | Nothing you use changes. Keeps 18.5, 27.0, 27.1 and the 27.2 versions you've used recently. |
> | **Xcode DerivedData** (including 5 copies of one project) | 44 GB | The next build of each project is slower, once. |
> | **Old iPhone debug symbols** (26.6.1, 26.7, 27.0; keeps 27.0.1) | ~18 GB | Xcode downloads them again if a phone on those versions connects. |
> | **2 Android emulators** last used in 2023 and 2024 | 8.7 GB | They're gone; they'd go to the Trash so you can still get them back. |
> | **Package caches** (npm, Swift packages, Homebrew, Xcode logs) | ~7 GB | Tools download things again as needed. |
>
> That's about **130 GB**. I'm leaving your recent simulators' data (51 GB) and the Claude app's own data alone.

## 4. Clean up

First, check "Running now" again. Don't delete a runtime that a booted simulator uses. Ask the user to quit an app before you clear its cache. Then do only what they picked:

| Item | Command |
|---|---|
| Simulator runtime | `xcrun simctl runtime delete <id>`, then `xcrun simctl delete unavailable` |
| Simulator device | `xcrun simctl delete <udid>` |
| Parallel-testing clones | `xcrun simctl --set testing delete all`, then `rm -rf ~/Library/Developer/XCTestDevices/*` for the empty leftovers |
| SwiftUI preview simulators | `xcrun simctl --set previews delete all` |
| Old Claude Code scratch folders | `rm -rf <session folder>`, only for folders not changed recently |
| DerivedData | `rm -rf ~/Library/Developer/Xcode/DerivedData/<folder>` |
| Device support | `rm -rf "<folder>"` |
| Archives, emulators, downloads, apps | `/usr/bin/trash <paths>` |
| npm / Yarn / pnpm | `npm cache clean --force` / `yarn cache clean` / `pnpm store prune` |
| Homebrew | `brew cleanup -s --prune=all` |
| pip / CocoaPods / Go | `pip3 cache purge` / `pod cache clean --all` / `go clean -modcache` |
| SwiftPM / Gradle | `rm -rf ~/Library/Caches/org.swift.swiftpm` / `rm -rf ~/.gradle/caches` |
| Docker | `docker builder prune -f`, `docker image prune -f` |

After each step, measure the item again so the report uses real numbers rather than estimates. If a command fails, carry on with the rest and collect the failures for the report.

## 5. Report

Lead with the free space before and after, using `df -k /System/Volumes/Data` and the same decimal GB as the survey. Then:

- a short table of what was freed, per category;
- what to expect: a slower first build, and free space drifting down a few GB while Xcode re-indexes;
- how much is waiting in the Trash, and that it only counts once they empty the Trash;
- anything that failed, with the manual way to do it, e.g. "delete it in Xcode → Window → Devices and Simulators";
- what's still available if they want more space later, in a line or two.
