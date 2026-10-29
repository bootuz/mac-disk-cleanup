#!/bin/bash
# Read-only survey of where disk space goes on a Mac. It changes nothing.
#
# Measures a fixed list of known hotspots in parallel instead of walking the
# whole home folder, which on a real Mac is slow and overcounts (online-only
# cloud files, mounted simulator images). Sizes are decimal GB/MB, like Finder.
#
# Usage: survey.sh            full survey (usually 1-3 minutes)
#        survey.sh --measure <path>   internal: size of one path

set -u
export LC_ALL=C
SELF="$0"
H="$HOME"

# One path -> "kilobytes<TAB>status<TAB>path". Status is "ok", "partial"
# (some subfolders unreadable) or "no access" (macOS privacy protection).
if [ "${1:-}" = "--measure" ]; then
  p="$2"
  [ -e "$p" ] || exit 0
  err=$(mktemp "${TMPDIR:-/tmp}/survey-err.XXXXXX")
  kb=$(du -skx "$p" 2>"$err" | cut -f1)
  status=ok
  if grep -qE "Operation not permitted|Permission denied" "$err"; then
    if [ -z "$kb" ] || [ "$kb" -lt 1024 ]; then status="no access"; else status="partial"; fi
  fi
  rm -f "$err"
  printf '%s\t%s\t%s\n' "${kb:-0}" "$status" "$p"
  exit 0
fi

section() { printf '\n== %s\n' "$1"; }

# Sizes of many paths at once, biggest first. Hides readable entries under
# 20 MB; always shows unreadable ones, because "no access" is not "empty".
measure_all() {
  for p in "$@"; do [ -e "$p" ] && printf '%s\0' "$p"; done |
    xargs -0 -n1 -P8 /bin/bash "$SELF" --measure |
    sort -t "$(printf '\t')" -k1,1rn
}
print_sizes() {
  awk -F'\t' '
    { b = $1 * 1024 }
    $2 == "ok" && b < 20e6 { next }
    {
      if ($2 == "no access") s = "?"
      else if (b >= 1e9) s = sprintf("%.1f GB", b / 1e9)
      else s = sprintf("%.0f MB", b / 1e6)
      note = ($2 == "ok") ? "" : "   [" $2 "]"
      printf "%9s  %s%s\n", s, $3, note
    }'
}
gb() { awk -v k="$1" 'BEGIN { b = k * 1024; if (b >= 1e9) printf "%.1f GB", b / 1e9; else printf "%.0f MB", b / 1e6 }'; }
plist() { [ -f "$1" ] && /usr/libexec/PlistBuddy -c "Print :$2" "$1" 2>/dev/null; }
mdate() { stat -f %Sm -t %Y-%m-%d "$1" 2>/dev/null; }

has_simctl=0
xcrun --find simctl >/dev/null 2>&1 && has_simctl=1

section "Disk (data volume, same numbers as Finder)"
df -k /System/Volumes/Data | awk 'NR == 2 { printf "total %.0f GB, free %.0f GB\n", $2 * 1024 / 1e9, $4 * 1024 / 1e9 }'
snaps=$(tmutil listlocalsnapshots / 2>/dev/null | grep -c com.apple)
[ "$snaps" -gt 0 ] && echo "Time Machine local snapshots: $snaps (macOS frees these by itself when space runs low)"
swap=$(sysctl -n vm.swapusage 2>/dev/null | awk '{ for (i = 1; i < NF; i++) if ($i == "used") { v = $(i + 2); sub(/M$/, "", v); if (v * 1048576 >= 1e9) printf "%.1f", v * 1048576 / 1e9 } }')
[ -n "$swap" ] && echo "macOS swap in use: $swap GB (shrinks after you quit memory-heavy apps such as Xcode and simulators)"

section "Running now (don't remove what these are using)"
pgrep -xq Xcode && echo "Xcode is open"
[ $has_simctl = 1 ] && xcrun simctl list devices booted 2>/dev/null | grep Booted | sed 's/^ */Booted simulator: /'
pgrep -f qemu-system >/dev/null && echo "An Android emulator is running"
pgrep -xq Docker && echo "Docker Desktop is running"
pgrep -xq xctrace && echo "An Instruments recording (xctrace) is running"
true

section "Developer hotspots"
measure_all \
  "$H/Library/Developer/Xcode/DerivedData" \
  "$H/Library/Developer/Xcode/Archives" \
  "$H/Library/Developer/Xcode/iOS DeviceSupport" \
  "$H/Library/Developer/Xcode/watchOS DeviceSupport" \
  "$H/Library/Developer/Xcode/tvOS DeviceSupport" \
  "$H/Library/Developer/Xcode/visionOS DeviceSupport" \
  "$H/Library/Developer/Xcode/macOS DeviceSupport" \
  "$H/Library/Developer/CoreSimulator/Devices" \
  "$H/Library/Developer/CoreSimulator/Caches" \
  "$H/Library/Developer/Xcode/UserData/Previews" \
  "$H/Library/Developer/Xcode/CodingAssistant" \
  "$H/Library/Developer/Xcode/DocumentationCache" \
  "/Library/Developer/CoreSimulator/Caches" \
  "$H/Library/Logs/Xcode" \
  "$H/Library/Logs/CoreSimulator" \
  "$H/Library/Caches/com.apple.dt.Xcode" \
  "$H/Library/Caches/org.swift.swiftpm" \
  "$H/.android/avd" \
  "$H/Library/Android/sdk" \
  "$H/.gradle" \
  "$H/.m2" \
  "$H/.npm" \
  "$H/Library/Caches/Yarn" \
  "$H/Library/pnpm" \
  "$H/.bun/install/cache" \
  "$H/Library/Caches/pip" \
  "$H/.cache" \
  "$H/Library/Caches/Homebrew" \
  "$H/.cocoapods" \
  "$H/Library/Caches/CocoaPods" \
  "$H/.cargo/registry" \
  "$H/.rustup" \
  "$H/go/pkg/mod" \
  "$H/.ollama" \
  "$H/.lmstudio" \
  "$H/.docker" \
  "$H/Library/Containers/com.docker.docker" \
  "$H/.colima" \
  "$H/.orbstack" | print_sizes

section "Everyday hotspots"
measure_all \
  "$H/Downloads" "$H/Desktop" "$H/Documents" "$H/Movies" "$H/Music" "$H/Pictures" \
  "$H/Library/Caches" \
  "$H/Library/Application Support" \
  "$H/Library/Application Support/MobileSync/Backup" \
  "$H/Library/Containers/com.apple.mail/Data/Library/Mail Downloads" \
  "$H/Library/Mail" \
  "$H/Library/Messages" \
  "$H/Library/Logs" \
  "$H/.Trash" \
  "/Applications" | print_sizes

section "Largest folders in ~/Library/Caches and ~/Library/Application Support"
measure_all "$H/Library/Caches"/* "$H/Library/Application Support"/* | head -12 | print_sizes

section "Other folders in ~/Library and hidden folders in your home folder"
# Skips what the lists above already cover, and iCloud/cloud folders whose
# online-only files would be counted as if they were on this Mac.
others=()
for p in "$H/Library"/* "$H"/.[!.]*; do
  [ -d "$p" ] || continue
  case "$(basename "$p")" in
    Developer|CloudStorage|"Mobile Documents"|Caches|"Application Support"|Mail|Messages|Logs) continue ;;
    .Trash|.android|.npm|.gradle|.m2|.cache|.cocoapods|.cargo|.rustup|.ollama|.lmstudio|.docker|.colima|.orbstack|.bun) continue ;;
  esac
  others+=("$p")
done
[ ${#others[@]} -gt 0 ] && measure_all "${others[@]}" | head -10 | print_sizes

section "Temporary files in /private/tmp over 500 MB (Claude Code sessions keep scratch files here)"
measure_all /private/tmp/* /private/tmp/claude-"$(id -u)"/*/* | while IFS="$(printf '\t')" read -r kb status path; do
  [ "$kb" -lt 512000 ] && continue
  flag=""
  [ -n "$(find "$path" -type f -mmin -60 -print -quit 2>/dev/null)" ] && flag="   [changed in the last hour: probably in use]"
  printf '%9s  %s%s\n' "$(gb "$kb")" "$path" "$flag"
done

# Tools keep working data in the per-user folders under /private/var/folders,
# and a run that is killed (often because the disk filled up) leaves it behind.
UT=$(getconf DARWIN_USER_TEMP_DIR 2>/dev/null)
UC=$(getconf DARWIN_USER_CACHE_DIR 2>/dev/null)
if [ -n "$UT" ] && [ -n "$UC" ]; then
  section "macOS per-user temp and cache folders (in /private/var/folders)"
  # Deleting-* folders are simulators that CoreSimulator removes in the
  # background after `simctl delete`. They are APFS clones, so du overcounts.
  tmpitems=()
  for p in "$UT"* "$UC"*; do
    case "$(basename "$p")" in Deleting-*) continue ;; esac
    tmpitems+=("$p")
  done
  [ ${#tmpitems[@]} -gt 0 ] && measure_all "${tmpitems[@]}" | head -8 | print_sizes
  deleting=0; busy=0
  for d in "$UT"Deleting-*; do
    [ -d "$d" ] || continue
    deleting=$((deleting + 1))
    [ -n "$(ls -A "$d" 2>/dev/null)" ] && busy=$((busy + 1))
  done
  if [ "$deleting" -gt 0 ]; then
    echo "$deleting Deleting-* folders: simulators macOS is deleting in the background ($busy not empty yet)."
    echo "Not measured (APFS clones). Leave them; they empty themselves, and free space catches up gradually."
  fi

  # Each xctrace run works in path_manager/xrtmp__<pid>.* and Instruments
  # records into instruments*.ktrace; both should vanish when the run ends.
  pm="${UC}com.apple.dt.InstrumentsCLI/path_manager"
  found=""
  for d in "$pm"/xrtmp__* "$UT"instruments*.ktrace; do [ -e "$d" ] && found=1; done
  if [ -n "$found" ]; then
    section "Instruments (xctrace) working data (left behind when a recording is killed)"
    for d in "$pm"/xrtmp__* "$UT"instruments*.ktrace; do
      [ -e "$d" ] || continue
      name=$(basename "$d")
      state="leftover: nothing is using it"
      case "$name" in
        xrtmp__*)
          pid=$(printf '%s' "$name" | sed 's/^xrtmp__\([0-9]*\)\..*/\1/')
          ps -p "$pid" >/dev/null 2>&1 && state="in use: xctrace run $pid is active" ;;
        *)
          [ -n "$(lsof -t "$d" 2>/dev/null)" ] && state="in use: open in Instruments or Xcode" ;;
      esac
      printf '%9s  %s  %s  [%s]\n' "$(gb "$(du -skx "$d" 2>/dev/null | cut -f1)")" "$(mdate "$d")" "$d" "$state"
    done
  fi
fi

if [ $has_simctl = 1 ]; then
  section "Simulator runtimes (size, last used, simulators using it; 'never' = never booted)"
  # Mounted copies of these images under /Library/Developer/CoreSimulator/Volumes
  # are the same bytes; don't add them to the total. simctl prints binary
  # gigabytes, converted here to decimal GB like the rest of this report.
  {
    xcrun simctl runtime list -v 2>/dev/null
    echo "@@MAIN@@"
    xcrun simctl list -j 2>/dev/null
    echo "@@TESTING@@"
    xcrun simctl --set testing list -j devices 2>/dev/null
  } | python3 -c '
import json, re, sys

verbose, rest = sys.stdin.read().split("@@MAIN@@", 1)
main, testing = rest.split("@@TESTING@@", 1)

def load(s):
    try:
        return json.loads(s)
    except ValueError:
        return {}

main, testing = load(main), load(testing)
build_of = {r["identifier"]: r.get("buildversion") for r in main.get("runtimes", [])}

def count(devices):
    used, booted = {}, {}
    for rid, devs in devices.items():
        b = build_of.get(rid)
        for d in devs:
            used[b] = used.get(b, 0) + 1
            if d.get("state") == "Booted":
                booted[b] = booted.get(b, 0) + 1
    return used, booted

used, booted = count(main.get("devices", {}))
clones, _ = count(testing.get("devices", {}))

def gb(s):
    m = re.match(r"([\d.]+)\s*([KMGT])", s or "")
    if not m:
        return "?"
    n = float(m.group(1)) * 1024 ** "KMGT".index(m.group(2)) * 1024 / 1e9
    return "%.1f GB" % n

rows, cur, total = [], None, 0.0
for line in verbose.splitlines():
    m = re.match(r"^(\S.*?) \((\w+)\) - ([0-9A-F-]{36})", line)
    if m:
        cur = {"name": m.group(1), "build": m.group(2), "id": m.group(3), "last": "never", "size": "?"}
        rows.append(cur)
    elif cur and "Last Used At:" in line:
        cur["last"] = line.split("Last Used At:")[1].strip()[:10]
    elif cur and line.strip().startswith("Size:"):
        cur["size"] = gb(line.split("Size:")[1].strip())
for r in rows:
    b = r["build"]
    use = "used by %d simulator%s" % (used.get(b, 0), "" if used.get(b, 0) == 1 else "s")
    if booted.get(b):
        use += ", %d booted" % booted[b]
    if clones.get(b):
        use += ", %d test clones" % clones[b]
    print("%9s  last used %-10s  %-36s %s (%s)  %s" % (r["size"], r["last"], use, r["name"], b, r["id"]))
    if r["size"] != "?":
        total += float(r["size"].split()[0])
if rows:
    print("%9s  total for %d runtimes" % ("%.1f GB" % total, len(rows)))
'
  for d in /Library/Developer/CoreSimulator/Caches/dyld/*/*SimRuntime*; do
    [ -d "$d" ] && printf '%s\n' "$d"
  done | while IFS= read -r d; do printf '%9s  dyld cache %s\n' "$(gb "$(du -skx "$d" 2>/dev/null | cut -f1)")" "${d##*SimRuntime.}"; done

  section "Simulator devices (size, last used, runtime, name)"
  unavailable=$(xcrun simctl list devices unavailable 2>/dev/null)
  measure_all "$H/Library/Developer/CoreSimulator/Devices"/*/ | while IFS="$(printf '\t')" read -r kb status path; do
    pl="${path%/}/device.plist"
    [ -f "$pl" ] || continue
    udid=$(basename "${path%/}")
    name=$(plist "$pl" name)
    rt=$(plist "$pl" runtime | sed 's/.*SimRuntime\.//')
    last=$(plist "$pl" lastUsedAt | awk 'NF >= 6 { print $2, $3, $6 }')
    flag=""
    [ "$(plist "$pl" state)" = 3 ] && flag=" [booted]"
    printf '%s' "$unavailable" | grep -q "$udid" && flag="$flag [unavailable: runtime missing]"
    printf '%9s  last used %-11s  %-22s %s (%s)%s\n' "$(gb "$kb")" "${last:-unknown}" "$rt" "$name" "$udid" "$flag"
  done

  tc="$H/Library/Developer/XCTestDevices"
  if [ -d "$tc" ] && [ -n "$(ls "$tc" 2>/dev/null)" ]; then
    section "Parallel-testing clones (~/Library/Developer/XCTestDevices)"
    n=$(xcrun simctl --set testing list devices 2>/dev/null | grep -c "(")
    folders=$(ls "$tc" | wc -l | tr -d ' ')
    first=$(ls -tr "$tc" | head -1)
    last=$(ls -t "$tc" | head -1)
    echo "$n clones registered, $folders folders, created $(mdate "$tc/$first") to $(mdate "$tc/$last")."
    echo "Not measured on purpose: these are APFS clones of your simulators, so du and Finder count the shared"
    echo "data once per clone and can report more than the whole disk. Real use is usually a few GB (careful"
    echo "measurements of 45 clones found 2-14 GB). Xcode recreates clones when it runs tests in parallel, so"
    echo "they're safe to remove whenever no tests are running; the true number shows up in free space afterwards."
  fi

  if [ -d "$H/Library/Developer/Xcode/UserData/Previews" ]; then
    section "SwiftUI preview simulators"
    xcrun simctl --set previews list devices 2>/dev/null | grep "(" | sed 's/^ */  /'
  fi
fi

if [ -d "$H/Library/Developer/Xcode/DerivedData" ]; then
  section "DerivedData by project (size, last opened, workspace)"
  # Xcode names each folder <project>-<28-letter hash>; one project opened from
  # several checkouts or worktrees gets several folders.
  dupes=$(ls "$H/Library/Developer/Xcode/DerivedData" | sed -n 's/-[a-z]\{28\}$//p' | sort | uniq -d)
  measure_all "$H/Library/Developer/Xcode/DerivedData"/*/ | while IFS="$(printf '\t')" read -r kb status path; do
    info="${path%/}/info.plist"
    ws=$(plist "$info" WorkspacePath)
    last=$(plist "$info" LastAccessedDate | awk 'NF >= 6 { print $2, $3, $6 }')
    flag=""
    [ -n "$ws" ] && [ ! -e "$ws" ] && flag=" [workspace no longer exists]"
    base=$(basename "${path%/}" | sed 's/-[a-z]\{28\}$//')
    printf '%s\n' "$dupes" | grep -qx "$base" && flag="$flag [one of several folders for $base]"
    if [ -z "$ws" ]; then
      case "$(basename "${path%/}")" in
        *.noindex|SDK*) ws="(shared cache)" ;;
        *) ws="(project path unknown)" ;;
      esac
    fi
    printf '%9s  %-12s %s  %s%s\n' "$(gb "$kb")" "${last:--}" "$(basename "${path%/}")" "$ws" "$flag"
  done
fi

ds=$(ls -d "$H/Library/Developer/Xcode/"*DeviceSupport/*/ 2>/dev/null)
if [ -n "$ds" ]; then
  section "Device support folders (debug symbols per device OS; date = when copied)"
  measure_all "$H/Library/Developer/Xcode/"*DeviceSupport/*/ | while IFS="$(printf '\t')" read -r kb status path; do
    printf '%9s  %s  %s\n' "$(gb "$kb")" "$(mdate "$path")" "${path#"$H"/Library/Developer/Xcode/}"
  done
fi

if ls -d "$H/Library/Developer/Xcode/Archives"/*/ >/dev/null 2>&1; then
  section "Xcode archives by date (hold dSYMs for builds you shipped)"
  measure_all "$H/Library/Developer/Xcode/Archives"/*/ | head -15 | print_sizes
fi

if ls -d "$H/.android/avd"/*.avd >/dev/null 2>&1; then
  section "Android emulators (size, last activity)"
  measure_all "$H/.android/avd"/*.avd | while IFS="$(printf '\t')" read -r kb status path; do
    newest=$(ls -t "$path" 2>/dev/null | head -1)
    printf '%9s  %s  %s\n' "$(gb "$kb")" "$(mdate "$path/$newest")" "$(basename "$path" .avd)"
  done
fi
if ls -d "$H/Library/Android/sdk/system-images"/*/*/* >/dev/null 2>&1; then
  section "Android system images"
  measure_all "$H/Library/Android/sdk/system-images"/*/*/* | print_sizes
fi

section "Dependency and build folders in projects (size, project last changed)"
roots=""
for r in Developer Projects code Code src dev repos workspace GitHub Documents/GitHub; do
  [ -d "$H/$r" ] && roots="$roots$H/$r
"
done
if [ -n "$roots" ]; then
  printf '%s' "$roots" | while IFS= read -r r; do
    find "$r" -maxdepth 5 -type d \( -name node_modules -o -name Pods -o -name .build \) -prune -print 2>/dev/null
  done | tr '\n' '\0' | xargs -0 -n1 -P8 /bin/bash "$SELF" --measure | sort -t "$(printf '\t')" -k1,1rn |
    while IFS="$(printf '\t')" read -r kb status path; do
      [ "$kb" -lt 51200 ] && continue
      proj=$(dirname "$path")
      changed=$(find "$proj" -maxdepth 1 -type f -exec stat -f '%m' {} + 2>/dev/null | sort -rn | head -1)
      [ -n "$changed" ] && changed=$(date -r "$changed" +%Y-%m-%d)
      printf '%9s  %s  %s\n' "$(gb "$kb")" "${changed:--}" "$path"
    done
else
  echo "(no usual project folders found)"
fi

section "Large files (over 500 MB) and installers in Downloads (over 20 MB)"
# du gives space actually on disk; iCloud files that are online-only show ~0.
{
  find "$H/Downloads" "$H/Desktop" "$H/Documents" "$H/Movies" -xdev -type f -size +500M 2>/dev/null
  find "$H/Downloads" -maxdepth 2 -type f -size +20M \( -iname '*.dmg' -o -iname '*.pkg' -o -iname '*.xip' -o -iname '*.zip' -o -iname '*.iso' \) 2>/dev/null
} | sort -u | while IFS= read -r f; do
  kb=$(du -k "$f" 2>/dev/null | cut -f1)
  note=""
  [ "${kb:-0}" -lt 1024 ] && note="  [in iCloud, not on this Mac]"
  printf '%s\t%9s  %s  %s%s\n' "${kb:-0}" "$(gb "${kb:-0}")" "$(mdate "$f")" "$f" "$note"
done | sort -rn | cut -f2- | head -25

section "Apps over 500 MB (size, last opened per Spotlight; 'unknown' is not 'never')"
for a in /Applications/*.app "$H/Applications"/*.app; do
  [ -d "$a" ] || continue
  bytes=$(mdls -raw -name kMDItemPhysicalSize "$a" 2>/dev/null)
  case "$bytes" in ''|*null*) continue ;; esac
  [ "$bytes" -lt 500000000 ] && continue
  used=$(mdls -raw -name kMDItemLastUsedDate "$a" 2>/dev/null | cut -c1-10)
  case "$used" in ''|*null*) used=unknown ;; esac
  printf '%s\t%9s  last opened %-10s  %s\n' "$bytes" "$(gb $((bytes / 1024)))" "$used" "$a"
done | sort -rn | cut -f2-

if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  section "Docker"
  docker system df 2>/dev/null
fi

printf '\nDone. Nothing was changed.\n'
