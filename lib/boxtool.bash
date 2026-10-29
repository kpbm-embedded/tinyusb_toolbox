# shellcheck shell=bash disable=SC2015  # d_ok/d_fail/d_warn always return 0
# framework: boxtool 4
# boxtool.bash: the generic part of a Box tool launcher (bootstrap, pinned downloads,
# pixi env, clean/status/doctor/shell/run/test/new/examples/native/relocate/pack/where).
# Sourced by lib/<tool>.bash, which sets the TOOL_* variables and defines the hooks
# (functions named hook_*, extra commands named tool_cmd_<name>). Every ID keeps its own copy
# of this file (self-contained IDs). The reference copy is 00_09_meta/05_policy/templates/tool/lib/boxtool.bash:
# change it there, then `box lint --scripts --check framework_drift` lists the copies to update; run each ID's
# tests after copying. Nothing loads the reference at runtime.
#
# Environment from the launcher: BOXT_ROOT, BOXT_NAME (launcher name), BOXT_PIXI,
# BOXT_DRY_RUN, PIXI_HOME, PIXI_CACHE_DIR, RATTLER_CACHE_DIR.
# Exit codes: 0 ok, 1 failure (die), 2 usage error (usage_error), 3 not applicable here (not_applicable).
# BOX_INTEGRATION=0 forces standalone mode (no $BOX / $BOX_OUT lookup; output stays in this folder).
# NO_COLOR=1 (or output that is not a terminal, e.g. a `box test` log) prints plain text.
set -euo pipefail

ROOT=${BOXT_ROOT:?run through the launcher}
NAME=${BOXT_NAME:?run through the launcher}
PIXI=${BOXT_PIXI:-$ROOT/.bin/pixi}
DRY=${BOXT_DRY_RUN:-0}
CONFIG="$ROOT/config"
MANIFEST="$ROOT/pixi.toml"
PINS="$CONFIG/pins.tsv"
DL="$ROOT/cache/downloads"
INST="$ROOT/install"
ENV_DIR="$ROOT/.pixi/envs/default"
TRASH_LOG_NAME="2026_10_24_box_trash.tsv"
NET_TIMEOUT=${BOXT_NET_TIMEOUT:-3600}
: "${TOOL_TITLE:=$NAME}"
: "${TOOL_INSTALL_WHAT:=nothing more}"
: "${TOOL_HELP_USE:=}"
# Registry name of this tool (`box native enable <name>`): the ID folder name without its number.
TOOL_BOX_NAME=${ROOT##*/}; TOOL_BOX_NAME=${TOOL_BOX_NAME#[0-9][0-9]_[0-9][0-9]_}
NATIVE_OFF_VAR="BOX_NATIVE_OFF_$(tr '[:lower:]-' '[:upper:]_' <<<"$TOOL_BOX_NAME")"

# ---------- helpers ----------
# Colour only on a terminal and never with NO_COLOR set, so logs stay plain text.
GREEN="" YELLOW="" RED="" RESET=""
if [ -z "${NO_COLOR:-}" ] && [ -t 1 ] && [ -t 2 ]; then
  GREEN=$'\033[0;32m' YELLOW=$'\033[0;33m' RED=$'\033[0;31m' RESET=$'\033[0m'
fi
info() { printf '%s[%s]%s %s\n' "$GREEN" "$NAME" "$RESET" "$*"; }
warn() { printf '%s[%s] warning:%s %s\n' "$YELLOW" "$NAME" "$RESET" "$*" >&2; }
die()  { printf '%s[%s] error:%s %s\n' "$RED" "$NAME" "$RESET" "$*" >&2; exit 1; }
usage_error() { # wrong command line: say what is wrong, point at help, exit 2
  printf '%s[%s] error:%s %s\n' "$RED" "$NAME" "$RESET" "$*" >&2
  printf 'run ./%s help for the commands and options\n' "$NAME" >&2
  exit 2
}
no_args() { # COMMAND [ARGS...]: usage error when a command that takes no arguments gets some
  local cmd=$1; shift
  [ $# -eq 0 ] || usage_error "$cmd takes no arguments (got: $*)"
}
not_applicable() { # the command exists but does not apply to this tool or folder (fan-out shows "skip")
  printf '[%s] not applicable: %s\n' "$NAME" "$*" >&2
  exit 3
}
run() { # execute, or only print in dry-run mode
  if [ "$DRY" = 1 ]; then printf '+'; printf ' %q' "$@"; echo; return 0; fi
  "$@"
}
human_size() { if [ -e "$1" ]; then du -sh "$1" 2>/dev/null | cut -f1; else echo "-"; fi; }
have() { command -v "$1" >/dev/null 2>&1; }
is_fn() { declare -F "$1" >/dev/null 2>&1; }

sha_of() { # algo file
  case "$1" in
    sha256) if have sha256sum; then sha256sum "$2" | cut -d' ' -f1; else shasum -a 256 "$2" | cut -d' ' -f1; fi ;;
    sha1)   if have sha1sum; then sha1sum "$2" | cut -d' ' -f1; else shasum -a 1 "$2" | cut -d' ' -f1; fi ;;
    *) die "unknown digest algorithm $1" ;;
  esac
}

# Locate the Box root ($BOX) and this folder's output mirror ($BOX_MIRROR) without hard paths.
# BOX: the environment, else the folder holding the `.boxroot` marker above ROOT (older trees: the one holding
# 00_09_meta/00_system/00_01_box_env/box_env.sh). Output base: $BOX_OUT_<NN_NN> (the ID's own .box.toml [paths]
# out), else $BOX_OUT (the named location `out`), else $BOX_V3 (its old name); values missing from the
# environment come from the generated box_env.d/locations.sh. BOX_MIRROR = <base>/<path of ROOT inside Box>
# when the base exists. Outside Box, or with BOX_INTEGRATION=0, all stay empty (standalone).
box_vars() {
  BOX_MIRROR=""
  if [ "${BOX_INTEGRATION:-1}" = 0 ]; then BOX="" BOX_V3=""; return 0; fi
  local d kit=00_09_meta/00_system/00_01_box_env rel id sub base idvar=""
  if [ -z "${BOX:-}" ]; then
    d=$ROOT
    while [ "$d" != "/" ] && [ -n "$d" ]; do
      d=${d%/*}; [ -n "$d" ] || d=/
      if [ -e "$d/.boxroot" ] || [ -r "$d/$kit/box_env.sh" ]; then BOX=$d; break; fi
    done
  fi
  BOX=${BOX:-}; BOX_V3=${BOX_V3:-}
  [ -n "$BOX" ] || return 0
  rel=${ROOT#"$BOX"/}
  [ "$rel" != "$ROOT" ] || return 0                     # ROOT is not inside $BOX: no mirror
  id=${rel#*/}; id=${id#*/}; sub=${id#*/}; id=${id%%/*}; [ "$sub" = "$id" ] && sub=""
  case $id in [0-9][0-9]_[0-9][0-9]_*) idvar="BOX_OUT_${id:0:5}" ;; esac
  if [ -z "${BOX_OUT:-}" ] && [ -z "$BOX_V3" ]; then    # not started from a Box shell: the generated values
    if [ -r "$BOX/$kit/box_env.d/locations.sh" ]; then
      # shellcheck disable=SC1090,SC1091  # generated per host, path known only at run time
      eval "$(. "$BOX/$kit/box_env.d/locations.sh" >/dev/null 2>&1
              printf 'BOX_OUT=%q BOX_V3=%q' "${BOX_OUT:-}" "${BOX_V3:-}"
              [ -z "$idvar" ] || printf ' %s=%q' "$idvar" "${!idvar:-}")"
    elif [ -r "$BOX/$kit/box_env.sh" ]; then             # a tree from before locations.sh
      # shellcheck disable=SC2016,SC2097,SC2098  # BOX is for the child shell, which expands $1
      BOX_V3=$(BOX="$BOX" bash -c '. "$1" >/dev/null 2>&1; printf %s "${BOX_V3:-}"' _ "$BOX/$kit/box_env.sh")
    fi
  fi
  if [ -n "$idvar" ] && [ -n "${!idvar:-}" ]; then BOX_MIRROR=${!idvar}${sub:+/$sub}; return 0; fi
  base=${BOX_OUT:-$BOX_V3}
  if [ -n "$base" ] && [ -d "$base" ]; then BOX_MIRROR="$base/$rel"; fi
}

# ---------- portable helpers: GNU and BSD userland (Linux, FreeBSD, macOS, Git-Bash) ----------
p_nproc() { nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4; }
p_mem_avail_gb() { # MemAvailable in GB; prints nothing when the OS does not tell (callers then do not wait)
  if [ -r /proc/meminfo ]; then awk '/MemAvailable/ {print int($2/1048576)}' /proc/meminfo; return 0; fi
  local pg fr ia
  pg=$(sysctl -n hw.pagesize 2>/dev/null) && fr=$(sysctl -n vm.stats.vm.v_free_count 2>/dev/null) &&
    ia=$(sysctl -n vm.stats.vm.v_inactive_count 2>/dev/null) && echo $(((fr + ia) * pg / 1073741824))
  return 0
}
p_size_bytes() { # apparent size of a file or tree in bytes: GNU du -sb, else BSD du -sAk
  local n
  n=$(du -sb "$1" 2>/dev/null | cut -f1) && [ -n "$n" ] && { echo "$n"; return 0; }
  n=$(du -sAk "$1" 2>/dev/null | cut -f1) && [ -n "$n" ] && echo $((n * 1024))
  return 0
}
p_realpath() { realpath "$1" 2>/dev/null || readlink -f "$1" 2>/dev/null || printf '%s\n' "$1"; }
p_sed_i() { # sed -i for GNU and BSD sed: p_sed_i SED-ARGS... FILE (keeps the file's mode)
  local f=${!#} tmp
  tmp="$f.p_sed.$$"
  cp -p "$f" "$tmp" && sed "${@:1:$#-1}" "$f" >"$tmp" && mv -f "$tmp" "$f"
}
p_subdirs() { # names of the subfolders of $1, sorted (replaces find -printf '%f')
  local d
  for d in "$1"/*/; do [ -d "$d" ] || continue; d=${d%/}; printf '%s\n' "${d##*/}"; done
}
p_trash() { # one path to the Trash: trash-put, else the Box OS layer (freedesktop Trash in Python / Recycle Bin)
  if command -v trash-put >/dev/null 2>&1; then trash-put -- "$1"; return; fi
  local osal="${BOX:-}/00_09_meta/00_system/00_01_box_env/bin/boxlib/osal.py"
  if [ -n "${BOX:-}" ] && [ -r "$osal" ] && command -v python3 >/dev/null 2>&1; then
    python3 "$osal" trash "$1" >/dev/null; return
  fi
  echo "no trash-put and no Box OS layer: install trash-cli (never deleted: $1)" >&2
  return 1
}
p_can_trash() { command -v trash-put >/dev/null 2>&1 || { [ -n "${BOX:-}" ] && command -v python3 >/dev/null 2>&1; }; }
# Tool internals (pixi/conda envs, prebuilt toolchains) are Linux/macOS builds. Elsewhere the commands that need
# them say so and exit 3 (fan-out shows "skip") instead of failing somewhere inside.
require_supported() { # COMMAND
  case "$(uname -s)" in
    Linux|Darwin) return 0 ;;
    MINGW*|MSYS*|CYGWIN*) printf '[%s] not applicable: %s is not supported on Windows (tool internals are Linux/macOS builds): run it in WSL\n' "${NAME:-tool}" "$1" >&2 ;;
    *) printf '[%s] not applicable: %s is not supported on %s (tool internals such as pixi/conda envs and toolchains are Linux/macOS builds): use a Linux VM\n' "${NAME:-tool}" "$1" "$(uname -s)" >&2 ;;
  esac
  exit 3
}

# Output root. Order: env BOXT_OUT, config/local.env, the Box convention (same ID path under the
# `out` location, $BOX_OUT), else this folder. Build output = $OUT/build, logs = $OUT/log.
resolve_out() {
  if [ -r "$CONFIG/local.env" ]; then
    # shellcheck disable=SC1091
    . "$CONFIG/local.env"
  fi
  if [ -z "${BOXT_OUT:-}" ]; then
    box_vars
    if [ -n "$BOX_MIRROR" ]; then
      BOXT_OUT=$BOX_MIRROR
    else
      BOXT_OUT="$ROOT"
    fi
  fi
  OUT=$BOXT_OUT
  BUILD="$OUT/build"
  LOG_DIR="$OUT/log"
  export BOXT_OUT
}
resolve_out

host_platform() { # linux-x64 | linux-arm64 | darwin-x64 | darwin-arm64 | win-x64
  local os arch
  case "$(uname -s)" in
    Linux) os=linux ;; Darwin) os=darwin ;; FreeBSD) os=freebsd ;;
    MINGW*|MSYS*|CYGWIN*) os=win ;;
    *) os=unknown ;;
  esac
  case "$(uname -m)" in
    x86_64|amd64) arch=x64 ;; aarch64|arm64) arch=arm64 ;; *) arch=unknown ;;
  esac
  printf '%s-%s' "$os" "$arch"
}
PLATFORM=${BOXT_PLATFORM:-$(host_platform)}

# Shared machine (Yocto, Zephyr, ROS 2 builds run next to us): at most 8 jobs, and wait
# while MemAvailable < BOXT_MIN_FREE_GB (8).
MAX_JOBS=8
default_jobs() { # min(nproc, MAX_JOBS)
  local n; n=$(p_nproc)
  [ "$n" -gt "$MAX_JOBS" ] && n=$MAX_JOBS
  echo "$n"
}
JOBS=${BOXT_JOBS:-$(default_jobs)}
[ "$JOBS" -gt "$MAX_JOBS" ] && JOBS=$MAX_JOBS
wait_for_ram() {
  local need=${BOXT_MIN_FREE_GB:-8} waited=0 free
  [ "$DRY" = 1 ] && return 0
  [ -n "$(p_mem_avail_gb)" ] || return 0              # the OS does not say: do not wait
  while :; do
    free=$(p_mem_avail_gb)
    [ "$free" -ge "$need" ] && return 0
    [ "$waited" -ge "${BOXT_RAM_WAIT_MAX:-3600}" ] && die "only $free GB RAM free after ${waited}s (need $need; BOXT_MIN_FREE_GB)"
    [ "$waited" = 0 ] && warn "only $free GB RAM free (< $need GB): pausing until other builds finish"
    sleep 30; waited=$((waited + 30))
  done
}

trash_paths() { # reason path...   (never rm: trash-put, logged in the Box trash log)
  local reason=$1; shift
  box_vars
  local logf="" p size
  [ -n "$BOX" ] && logf="$BOX/00_09_meta/02_logs/$TRASH_LOG_NAME"
  p_can_trash || [ "$DRY" = 1 ] || die "trash-put not found (install trash-cli); $NAME never uses rm"
  for p in "$@"; do
    [ -e "$p" ] || [ -L "$p" ] || continue
    size=$(p_size_bytes "$p")
    if command -v trash-put >/dev/null 2>&1; then run trash-put -- "$p"; else run p_trash "$p"; fi
    if [ "$DRY" != 1 ] && [ -n "$logf" ] && [ -w "$(dirname "$logf")" ]; then
      printf '%s\t%s\t%s\t%s\t%s\n' "$p" "${size:-0}" "$NAME: $reason" "-" "$(date +%Y-%m-%dT%H:%M:%S)" >>"$logf"
    fi
  done
}

cachedir_tag() { # dir...  (marks regenerable dirs for backup tools)
  local d
  for d in "$@"; do
    [ "$DRY" = 1 ] && continue
    mkdir -p "$d"
    [ -e "$d/CACHEDIR.TAG" ] || printf 'Signature: 8a477f597d28d172789f06886806bc55\n# regenerable: created by %s\n' "$NAME" >"$d/CACHEDIR.TAG"
  done
}

# ---------- pinned downloads (config/pins.tsv) ----------
# Columns (tab separated): name version group platform kind digest url [upstream]
#   group    core (installed by bootstrap) | demo (install; skipped by --no-demos) | optional
#   platform linux-x64 | linux-arm64 | darwin-x64 | darwin-arm64 | win-x64 | any
#   kind     tar (any tar.*) | zip | appimage | file (download only, kept in cache/downloads)
#   digest   sha256:<hex> or sha1:<hex>
#   upstream github owner/repo (for `update --check`) or -
pins_all() { [ -r "$PINS" ] && sed -e '/^[[:space:]]*#/d' -e '/^[[:space:]]*$/d' "$PINS"; true; }
pin_line() { # name -> the line for this platform (or 'any')
  pins_all | awk -F'\t' -v n="$1" -v p="$PLATFORM" '
    $1==n && $4==p && e=="" {e=$0}
    $1==n && $4=="any" && a=="" {a=$0}
    END {if (e!="") print e; else if (a!="") print a}'
}
pin_get() { # name field-number
  pin_line "$1" | head -1 | cut -f"$2"
}
pin_names() { # [group] -> unique names
  pins_all | awk -F'\t' -v g="${1:-}" 'g=="" || $3==g {print $1}' | awk '!s[$0]++'
}
pin_file() { local u; u=$(pin_get "$1" 7); printf '%s/%s' "$DL" "$(basename "${u%%\?*}")"; }
pin_dir() { printf '%s/%s-%s' "$INST" "$1" "$(pin_get "$1" 2)"; }
pin_installed() { [ -e "$(pin_dir "$1")/.boxt-ok" ]; }

fetch_pin() { # name
  local n=$1 line url digest algo want f have_d
  line=$(pin_line "$n" | head -1)
  [ -n "$line" ] || die "no pin for '$n' on $PLATFORM in config/pins.tsv"
  url=$(cut -f7 <<<"$line"); digest=$(cut -f6 <<<"$line")
  algo=${digest%%:*}; want=${digest#*:}
  f=$(pin_file "$n")
  if [ -f "$f" ] && [ "$(sha_of "$algo" "$f")" = "$want" ]; then return 0; fi
  info "download $n $(cut -f2 <<<"$line"): $url"
  if [ "$DRY" = 1 ]; then printf '+ curl %s -> %s (%s)\n' "$url" "$f" "$digest"; return 0; fi
  mkdir -p "$DL"; cachedir_tag "$ROOT/cache"
  if have curl; then
    local prog=(-sS); [ -t 2 ] && prog=(--progress-bar)
    curl -fL "${prog[@]}" --retry 3 --connect-timeout 30 --max-time "$NET_TIMEOUT" -o "$f.part" "$url" || die "download failed: $url"
  else
    wget -q --tries=3 --timeout=60 -O "$f.part" "$url" || die "download failed: $url"
  fi
  have_d=$(sha_of "$algo" "$f.part")
  [ "$have_d" = "$want" ] || die "$n: $algo mismatch ($have_d != $want); kept $f.part for inspection"
  mv "$f.part" "$f"
}

unpack() { # archive kind dest-dir
  local a=$1 kind=$2 d=$3
  mkdir -p "$d"
  case "$kind" in
    tar) tar -xf "$a" -C "$d" ;;
    zip)
      if have unzip; then unzip -q "$a" -d "$d"
      elif have bsdtar; then bsdtar -xf "$a" -C "$d"
      elif have python3; then python3 -I -m zipfile -e "$a" "$d"
      else tar -xf "$a" -C "$d"; fi ;;
    appimage) cp "$a" "$d/"; chmod +x "$d/$(basename "$a")" ;;
    *) die "unpack: unknown kind $kind" ;;
  esac
}

install_pin() { # name   -> install/<name>-<version>/ (single top-level folder flattened) + install/<name> symlink
  local n=$1 kind dir tmp entries
  kind=$(pin_get "$n" 5)
  fetch_pin "$n"
  [ "$kind" = file ] && return 0
  dir=$(pin_dir "$n")
  if [ -e "$dir/.boxt-ok" ]; then return 0; fi
  info "install $n -> ${dir#"$ROOT"/}"
  if [ "$DRY" = 1 ]; then printf '+ unpack %s -> %s\n' "$(pin_file "$n")" "$dir"; return 0; fi
  [ -e "$dir" ] && trash_paths "incomplete install of $n" "$dir"
  tmp="$INST/.tmp-$n"
  [ -e "$tmp" ] && trash_paths "stale unpack dir" "$tmp"
  unpack "$(pin_file "$n")" "$kind" "$tmp"
  entries=$(find "$tmp" -mindepth 1 -maxdepth 1 | wc -l)
  if [ "$entries" = 1 ] && [ -d "$(find "$tmp" -mindepth 1 -maxdepth 1)" ]; then
    mv "$(find "$tmp" -mindepth 1 -maxdepth 1)" "$dir"; rmdir "$tmp"
  else
    mv "$tmp" "$dir"
  fi
  ln -sfn "$(basename "$dir")" "$INST/$n"
  # the post-install step runs before the "installed" mark, so a failure leaves it unmarked (retried next time)
  if is_fn hook_post_install_pin && ! hook_post_install_pin "$n" "$dir"; then
    die "post-install step of $n failed; $dir is not marked installed (rerun ./$NAME install)"
  fi
  printf 'name=%s\nversion=%s\nurl=%s\ndigest=%s\ndate=%s\n' "$n" "$(pin_get "$n" 2)" "$(pin_get "$n" 7)" "$(pin_get "$n" 6)" "$(date -Iseconds)" >"$dir/.boxt-ok"
  return 0
}

install_group() { # group
  local n
  cachedir_tag "$INST"
  for n in $(pin_names "$1"); do
    [ -n "$(pin_line "$n")" ] || { warn "$n: no pin for $PLATFORM (skipped)"; continue; }
    install_pin "$n"
  done
}

# ---------- pixi env ----------
have_env() { [ -x "$ENV_DIR/bin/python" ] || [ -x "$ENV_DIR/python.exe" ] || [ -d "$ENV_DIR/conda-meta" ]; }
pixi_install() {
  [ -r "$MANIFEST" ] || return 0
  local lock=()
  # --locked only while pixi.lock is at least as new as pixi.toml; after a manifest edit pixi re-solves
  # (and rewrites pixi.lock) instead of failing.
  if [ -r "$ROOT/pixi.lock" ]; then
    if [ "$MANIFEST" -nt "$ROOT/pixi.lock" ]; then warn "pixi.toml is newer than pixi.lock: re-solving (pixi.lock is rewritten)"
    else lock=(--locked); fi
  fi
  wait_for_ram
  run timeout "$NET_TIMEOUT" "$PIXI" install --manifest-path "$MANIFEST" "${lock[@]+"${lock[@]}"}"
  [ "$DRY" = 1 ] || { mkdir -p "$INST"; printf '%s\n' "$ROOT" >"$INST/.boxt-prefix"; }
}
clean_host_env() { # anything from a host toolchain/python that could leak in
  local v
  for v in PYTHONPATH PYTHONHOME LD_LIBRARY_PATH PKG_CONFIG_PATH CFLAGS CXXFLAGS CPPFLAGS LDFLAGS CC CXX \
           MAKEFLAGS CONDA_PREFIX VIRTUAL_ENV CMAKE_PREFIX_PATH; do
    unset "$v"
  done
}
activate() { # pixi env + tool paths (hook_env)
  clean_host_env
  if [ -r "$MANIFEST" ]; then
    if have_env; then
      local hook
      hook=$("$PIXI" shell-hook --manifest-path "$MANIFEST" --frozen --shell bash) || die "pixi shell-hook failed"
      local keep_build=$BUILD   # conda compiler activation exports BUILD=<host triple>
      set +u; eval "$hook"; set -u   # activation scripts are not nounset-safe
      BUILD=$keep_build
      export PYTHONNOUSERSITE=1
    elif [ "$DRY" = 1 ]; then printf '+ (pixi env not installed; dry run continues)\n'
    else die "pixi env missing: run ./$NAME bootstrap"; fi
  fi
  export BOXT_ROOT="$ROOT" BOXT_BUILD="$BUILD" BOXT_JOBS="$JOBS"
  is_fn hook_env && hook_env
  return 0
}

# ---------- commands ----------
template_kinds() { local k; for k in $(p_subdirs "$ROOT/templates"); do printf '%s ' "$k"; done; true; }

cmd_help() {
  cat <<EOF
$TOOL_TITLE
usage: ./$NAME [--dry-run|-n] <command> [options]

setup
  bootstrap               pinned pixi (.bin/) + pixi env + core downloads (sha-checked)
  install [--no-demos]    bootstrap + demo downloads + $TOOL_INSTALL_WHAT
  update [--check|--env]  --check (default): pinned vs newest upstream releases;
                          --env: re-solve the pixi env within pixi.toml (rewrites pixi.lock)
  clean [--all] [--yes]   build/log output (--all: + install/, .pixi, native/, downloads);
                          dry run unless --yes; moves to the Trash (trash-put, logged)
info
  status                  pinned versions, what is installed, sizes (read-only, no network)
  where                   key paths: root, output, install, env, cache, native file
  doctor                  host and install checks: ok/warn/FAIL lines, exit 1 on any FAIL
use
  shell [-- cmd ...]      bash (or cmd) with the tools on PATH
  run <cmd> [args]        one command inside the environment
$TOOL_HELP_USE
  test [--all]            tests/test_smoke.sh (--all: + dry-run test and examples test)
  new <kind> <name> [--dir D] [--force]   from templates/: $(template_kinds)
  examples list | run <ex> [args] | build [ex...] | test [ex...]
portability
  native [--print]        write native/{native.zsh,native.bash,bin/}: only the tool CLIs on PATH
                          (every shell: box native enable $TOOL_BOX_NAME --apply; $NATIVE_OFF_VAR=1 skips one)
  relocate                after moving the folder: re-create the pixi env, rewrite native/
  pack [--with-cache] [--out F]   tarball of this folder (minus envs/build) for another machine
  help | -h | --help      this text

examples
  ./$NAME install && ./$NAME doctor      first setup on a new machine
  ./$NAME examples test                  build and check every example
  ./$NAME --dry-run clean --all          show what clean would move to the Trash

environment
  BOXT_OUT           output root (build/, log/); default: same ID path on idisk03, else here
  BOXT_JOBS          parallel jobs (default and maximum $MAX_JOBS)
  BOXT_MIN_FREE_GB   pause builds while less RAM is free (8); BOXT_RAM_WAIT_MAX: give up after s (3600)
  BOXT_NET_TIMEOUT   seconds for one download (3600)
  BOXT_PLATFORM      override the detected platform ($PLATFORM)
  GITHUB_TOKEN       optional, lifts the GitHub API rate limit for update --check
  BOX_INTEGRATION    0 = standalone: ignore \$BOX/\$BOX_OUT, keep output in this folder
  NO_COLOR           set to print plain text (colour is only used on a terminal anyway)
EOF
  if is_fn hook_help; then hook_help; fi   # tool-specific examples, environment and notes from lib/<tool>.bash
  printf '\nBuild output: %s   (BOXT_OUT or config/local.env to change)\n' "$BUILD"
  echo "Exit codes: 0 ok, 1 failure, 2 usage error, 3 not applicable"
}

cmd_where() {
  printf '%-10s %s\n' root "$ROOT" platform "$PLATFORM" out "$OUT" build "$BUILD" log "$LOG_DIR" \
    install "$INST" env "$ENV_DIR" cache "$ROOT/cache" pixi "$PIXI" native "$ROOT/native/native.zsh"
  local n
  for n in $(pin_names); do
    [ "$(pin_get "$n" 5)" = file ] && continue
    printf '%-10s %s\n' "$n" "$(pin_dir "$n")"
  done
}

cmd_bootstrap() {
  [ -x "$PIXI" ] || [ "$DRY" = 1 ] || die "pixi missing: run through ./$NAME (it bootstraps .bin/pixi)"
  cachedir_tag "$ROOT/cache"
  pixi_install
  install_group core
  is_fn hook_bootstrap && hook_bootstrap
  [ "$DRY" = 1 ] || info "bootstrap done ($PLATFORM)"
}

cmd_install() {
  local demos=1
  while [ $# -gt 0 ]; do
    case "$1" in --no-demos) demos=0 ;; --with-demos|--all) demos=1 ;; *) usage_error "install: unknown option $1" ;; esac; shift
  done
  cmd_bootstrap
  [ "$demos" = 1 ] && install_group demo
  is_fn hook_install && hook_install "$demos"
  [ "$DRY" = 1 ] || info "install done: ./$NAME doctor && ./$NAME examples test"
}

cmd_update() {
  local mode="check"
  while [ $# -gt 0 ]; do
    case "$1" in --check) mode="check" ;; --env) mode="env" ;; *) usage_error "update: unknown option $1" ;; esac; shift
  done
  if [ "$mode" = env ]; then
    info "re-solving the pixi env within pixi.toml (rewrites pixi.lock)"
    run timeout "$NET_TIMEOUT" "$PIXI" update --manifest-path "$MANIFEST"
    run timeout "$NET_TIMEOUT" "$PIXI" install --manifest-path "$MANIFEST"
    return 0
  fi
  info "pinned vs newest upstream release (change config/pins.tsv deliberately, then ./$NAME install)"
  local n up ver latest
  for n in $(pin_names); do
    up=$(pin_get "$n" 8); ver=$(pin_get "$n" 2)
    [ -n "$up" ] && [ "$up" != - ] || continue
    if [ "$DRY" = 1 ]; then printf '+ curl https://api.github.com/repos/%s/releases/latest\n' "$up"; continue; fi
    local auth=()   # optional: GITHUB_TOKEN from the environment lifts the 60 requests/hour limit
    [ -n "${GITHUB_TOKEN:-}" ] && auth=(-H "Authorization: Bearer $GITHUB_TOKEN")
    latest=$(curl -fsS --connect-timeout 20 --max-time 60 "${auth[@]+"${auth[@]}"}" "https://api.github.com/repos/$up/releases/latest" 2>/dev/null \
      | sed -n 's/^ *"tag_name": *"\([^"]*\)".*/\1/p' | head -1) || true
    printf '  %-14s pinned %-16s latest %-16s %s\n' "$n" "$ver" "${latest:-? (offline or API rate limit)}" "$up"
  done
  is_fn hook_update_check && hook_update_check
  return 0
}

cmd_clean() {
  local all=0 yes=0
  while [ $# -gt 0 ]; do
    case "$1" in --all) all=1 ;; --yes|-y) yes=1 ;; *) usage_error "clean: unknown option $1" ;; esac; shift
  done
  local targets=("$BUILD" "$LOG_DIR")
  [ "$all" = 1 ] && targets+=("$INST" "$ROOT/.pixi" "$ROOT/native" "$DL")
  local t any=0
  for t in "${targets[@]}"; do
    [ -e "$t" ] || continue
    any=1; printf '  %-8s %s\n' "$(human_size "$t")" "$t"
  done
  [ "$any" = 1 ] || { info "nothing to clean"; return 0; }
  if [ "$yes" != 1 ]; then info "dry run: re-run with --yes to move these to the Trash"; return 0; fi
  trash_paths "clean$([ "$all" = 1 ] && echo ' --all')" "${targets[@]}"
  info "moved to Trash (restore with trash-restore)"
}

cmd_status() {
  echo "$TOOL_TITLE"
  echo "platform: $PLATFORM   pixi: $([ -x "$PIXI" ] && "$PIXI" --version 2>/dev/null || echo 'not bootstrapped')"
  local n
  for n in $(pin_names); do
    [ -n "$(pin_line "$n")" ] || { printf '  %-22s (no pin for %s)\n' "$n" "$PLATFORM"; continue; }
    if [ "$(pin_get "$n" 5)" = file ]; then
      printf '  %-22s %-12s %-6s %s\n' "$n" "$(pin_get "$n" 2)" "$(pin_get "$n" 3)" "$([ -f "$(pin_file "$n")" ] && echo cached || echo '-')"
    else
      printf '  %-22s %-12s %-6s %s\n' "$n" "$(pin_get "$n" 2)" "$(pin_get "$n" 3)" "$(pin_installed "$n" && echo "installed $(human_size "$(pin_dir "$n")")" || echo 'not installed')"
    fi
  done
  if [ -r "$MANIFEST" ]; then
    printf '  %-22s %s\n' pixi-env "$(have_env && echo "installed $(human_size "$ROOT/.pixi")" || echo 'not installed')"
  fi
  is_fn hook_status && hook_status
  printf 'sizes: install %s | env %s | cache %s | build %s | log %s\n' "$(human_size "$INST")" "$(human_size "$ROOT/.pixi")" \
    "$(human_size "$ROOT/cache")" "$(human_size "$BUILD")" "$(human_size "$LOG_DIR")"
  [ -r "$ROOT/native/native.zsh" ] && echo "native: $ROOT/native/native.zsh"
  return 0
}

DOC_OK=0; DOC_FAIL=0; DOC_WARN=0
d_ok()   { printf '  ok    %s\n' "$*"; DOC_OK=$((DOC_OK+1)); }
d_fail() { printf '  FAIL  %s\n' "$*"; DOC_FAIL=$((DOC_FAIL+1)); }
d_warn() { printf '  warn  %s\n' "$*"; DOC_WARN=$((DOC_WARN+1)); }
cmd_doctor() {
  echo "doctor: $TOOL_TITLE on $PLATFORM"
  [ -x "$PIXI" ] && d_ok "pixi $("$PIXI" --version 2>/dev/null | cut -d' ' -f2) in .bin/" || d_fail "pixi not bootstrapped (./$NAME bootstrap)"
  if [ -r "$MANIFEST" ]; then
    if have_env; then d_ok "pixi env $(human_size "$ROOT/.pixi")"; else d_fail "pixi env missing (./$NAME bootstrap)"; fi
    if [ -r "$INST/.boxt-prefix" ] && [ "$(cat "$INST/.boxt-prefix")" != "$ROOT" ]; then
      d_fail "folder moved since the env was made ($(cat "$INST/.boxt-prefix")): ./$NAME relocate"
    fi
  fi
  local n
  for n in $(pin_names core); do
    [ -n "$(pin_line "$n")" ] || { d_warn "$n: not available for $PLATFORM"; continue; }
    if [ "$(pin_get "$n" 5)" = file ]; then
      [ -f "$(pin_file "$n")" ] && d_ok "$n cached" || d_fail "$n not downloaded"
    elif pin_installed "$n"; then d_ok "$n $(pin_get "$n" 2)"
    else d_fail "$n $(pin_get "$n" 2) not installed (./$NAME bootstrap)"; fi
  done
  local free
  free=$(df -Pk "$ROOT" 2>/dev/null | awk 'NR==2 {print int($4/1048576)}')
  [ "${free:-0}" -ge 5 ] && d_ok "disk: ${free} GB free at $ROOT" || d_warn "disk: only ${free:-?} GB free at $ROOT"
  if [ -d "$OUT" ] || mkdir -p "$OUT" 2>/dev/null; then
    [ -w "$OUT" ] && d_ok "output dir writable: $OUT" || d_fail "output dir not writable: $OUT"
  else d_fail "cannot create output dir $OUT"; fi
  have trash-put && d_ok "trash-put (clean)" || d_warn "trash-put missing: clean cannot run"
  if is_fn hook_doctor; then
    if have_env || [ ! -r "$MANIFEST" ]; then
      # the tool checks run in a subshell (activate changes the env), so their counters are
      # lost: count the result lines of their output instead
      local tool_checks
      tool_checks=$( ( activate >/dev/null 2>&1 || true; hook_doctor ) )
      [ -n "$tool_checks" ] && printf '%s\n' "$tool_checks"
      DOC_OK=$((DOC_OK + $(grep -c '^  ok' <<<"$tool_checks" || true)))
      DOC_FAIL=$((DOC_FAIL + $(grep -c '^  FAIL' <<<"$tool_checks" || true)))
      DOC_WARN=$((DOC_WARN + $(grep -c '^  warn' <<<"$tool_checks" || true)))
    else d_fail "tool checks skipped: env not installed"; fi
  fi
  echo "doctor: $DOC_OK ok, $DOC_WARN warnings, $DOC_FAIL failed"
  [ "$DOC_FAIL" -eq 0 ]
}

cmd_shell() {
  [ "${1:-}" = -- ] && shift
  activate
  if [ $# -eq 0 ]; then
    [ "$DRY" = 1 ] && { echo "+ bash -i"; return 0; }
    info "shell with $TOOL_TITLE (exit to leave)"
    export PS1="($NAME) \\w \\$ "
    exec bash --norc -i
  fi
  [ "$DRY" = 1 ] && { printf '+'; printf ' %q' "$@"; echo; return 0; }
  exec "$@"
}
cmd_run() { [ $# -gt 0 ] || usage_error "usage: ./$NAME run <cmd> [args]"; cmd_shell -- "$@"; }

cmd_test() {
  local all=0
  case "${1:-}" in "") ;; --all) all=1 ;; *) usage_error "test: unknown option $1" ;; esac
  local rc=0
  run bash "$ROOT/tests/test_smoke.sh" || rc=1
  if [ "$all" = 1 ]; then
    run bash "$ROOT/tests/test_dry_run.sh" || rc=1
    cmd_examples test || rc=1
  fi
  return "$rc"
}

# new <kind> <name>: copy templates/<kind>, replacing @NAME@ / @NAME_UPPER@ in files and
# __name__ in file names.
cmd_new() {
  local kind=${1:-} nm=${2:-} dir=$PWD force=0
  [ -n "$kind" ] && [ -n "$nm" ] || usage_error "usage: ./$NAME new <kind> <name> [--dir D] [--force]; kinds: $(template_kinds)"
  shift 2
  local rest=()   # options this function does not know go to hook_new
  while [ $# -gt 0 ]; do
    case "$1" in --dir) dir=${2:?}; shift ;; --force) force=1 ;; *) rest+=("$1") ;; esac; shift
  done
  set -- "${rest[@]+"${rest[@]}"}"
  local src="$ROOT/templates/$kind" dst="$dir/$nm"
  [ -d "$ROOT/templates" ] || not_applicable "this tool has no templates/"
  [ -d "$src" ] || usage_error "no template '$kind' (templates/: $(template_kinds))"
  [[ "$nm" =~ ^[A-Za-z][A-Za-z0-9_-]*$ ]] || usage_error "name must be [A-Za-z][A-Za-z0-9_-]*"
  [ -e "$dst" ] && [ "$force" != 1 ] && die "$dst exists (--force to overwrite files)"
  if [ "$DRY" = 1 ]; then printf '+ copy %s -> %s\n' "$src" "$dst"; return 0; fi
  mkdir -p "$dst"
  (cd "$src" && find . -type f ! -name '*.pyc') | while IFS= read -r f; do
    local out="$dst/${f#./}"; out=${out//__name__/$nm}
    mkdir -p "$(dirname "$out")"
    sed -e "s/@NAME@/$nm/g" -e "s/@NAME_UPPER@/$(tr '[:lower:]-' '[:upper:]_' <<<"$nm")/g" "$src/$f" >"$out"
    if [ -x "$src/$f" ]; then chmod +x "$out"; fi
  done
  if is_fn hook_new; then hook_new "$kind" "$nm" "$dst" "$@"; fi
  info "created $dst (see its README.md)"
}

# examples/<ex>/example.sh <build|run|test> [args]: called inside the environment with
# EX_OUT=$BUILD/examples/<ex>. The first '# about:' line is the description.
ex_list() { local d; for d in $(p_subdirs "$ROOT/examples"); do [ -e "$ROOT/examples/$d/example.sh" ] && echo "$d"; done; true; }
ex_about() { sed -n 's/^# about: //p' "$ROOT/examples/$1/example.sh" | head -1; }
ex_call() { # ex action [args]
  local ex=$1 act=$2; shift 2
  [ -r "$ROOT/examples/$ex/example.sh" ] || die "no example '$ex' (./$NAME examples list)"
  export EX_OUT="$BUILD/examples/$ex" EX_DIR="$ROOT/examples/$ex"
  if [ "$DRY" = 1 ]; then printf '+ (cd %s && bash example.sh %s %s)\n' "$EX_DIR" "$act" "$*"; return 0; fi
  mkdir -p "$EX_OUT"
  (cd "$EX_DIR" && bash ./example.sh "$act" "$@")
}
cmd_examples() {
  [ -d "$ROOT/examples" ] || not_applicable "this tool has no examples/"
  local sub=${1:-list}; [ $# -gt 0 ] && shift
  case "$sub" in
    list)
      local ex
      for ex in $(ex_list); do printf '  %-22s %s\n' "$ex" "$(ex_about "$ex")"; done ;;
    run)
      [ $# -gt 0 ] || usage_error "usage: ./$NAME examples run <example> [args]"
      local ex=$1; shift
      activate; cachedir_tag "$BUILD"; ex_call "$ex" run "$@" ;;
    build|test)
      local list=("$@") ex rc=0 t0 res=() logf
      [ ${#list[@]} -gt 0 ] || mapfile -t list < <(ex_list)
      activate; cachedir_tag "$BUILD"
      [ "$DRY" = 1 ] || mkdir -p "$LOG_DIR"
      logf="$LOG_DIR/examples_${sub}_$(date +%Y_%m_%d_%H%M%S).log"
      for ex in "${list[@]}"; do
        wait_for_ram
        t0=$(date +%s)
        info "examples $sub: $ex"
        if [ "$DRY" = 1 ]; then ex_call "$ex" "$sub"; continue; fi
        if ex_call "$ex" "$sub" > >(tee -a "$logf") 2>&1; then res+=("ok    $ex ($(( $(date +%s) - t0 ))s)")
        else res+=("FAIL  $ex ($(( $(date +%s) - t0 ))s)"); rc=1; fi
      done
      [ "$DRY" = 1 ] && return 0
      echo "examples $sub summary ($PLATFORM):"; printf '  %s\n' "${res[@]}" | tee -a "$logf"
      echo "log: $logf"
      return "$rc" ;;
    *) usage_error "usage: ./$NAME examples list | run <ex> [args] | build [ex...] | test [ex...]" ;;
  esac
}

# native mode: hook_native_bins prints "<command> <path relative to ROOT>" lines; each gets
# a small wrapper in native/bin. native.zsh / native.bash only add native/bin to PATH.
cmd_native() {
  local print=0
  case "${1:-}" in "") ;; --print) print=1 ;; *) usage_error "native: unknown option $1" ;; esac
  is_fn hook_native_bins || not_applicable "no native commands defined for $NAME"
  local nd="$ROOT/native" line c t
  if [ "$print" = 1 ]; then hook_native_bins; return 0; fi
  if [ "$DRY" = 1 ]; then printf '+ write %s/{native.zsh,native.bash,bin/*}\n' "$nd"; hook_native_bins | sed 's/^/+   /'; return 0; fi
  mkdir -p "$nd/bin"
  while IFS= read -r line; do
    c=${line%% *}; t=${line#* }
    if [ "${t#@}" != "$t" ]; then   # "@sub args": through the launcher (needs the env)
      cat >"$nd/bin/$c.part" <<EOF
#!/bin/sh
# $c: written by ./$NAME native; runs ./$NAME ${t#@} (relative, survives moves)
h=\$(cd -P "\$(dirname "\$0")/../.." && pwd -P)
exec "\$h/$NAME" ${t#@} "\$@"
EOF
    else
      [ -e "$ROOT/$t" ] || { warn "native: $t missing (install first); $c skipped"; continue; }
      cat >"$nd/bin/$c.part" <<EOF
#!/bin/sh
# $c: written by ./$NAME native; runs $t from this folder (relative, survives moves)
h=\$(cd -P "\$(dirname "\$0")/../.." && pwd -P)
exec "\$h/$t" "\$@"
EOF
    fi
    chmod +x "$nd/bin/$c.part"; mv "$nd/bin/$c.part" "$nd/bin/$c"
  done < <(hook_native_bins)
  local sh self var
  var="BOXT_$(tr '[:lower:]-' '[:upper:]_' <<<"${NAME%-box}")_HOME"
  for sh in zsh bash; do
    # shellcheck disable=SC2016  # written literally into the generated file
    self='${0:A:h:h}'
    # shellcheck disable=SC2016
    [ "$sh" = bash ] && self='$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)'
    cat >"$nd/native.$sh.part" <<EOF
# native.$sh written by ./$NAME native. Source it: puts $(hook_native_bins | cut -d' ' -f1 | paste -sd' ' -) on PATH.
# Only native/bin is added to PATH; nothing from the pixi env or toolchains leaks in.
# In Box, \`box native enable $TOOL_BOX_NAME --apply\` sources it in every shell ($NATIVE_OFF_VAR=1 skips one).
$var=$self
export $var
case ":\$PATH:" in *":\$$var/native/bin:"*) ;; *) export PATH="\$$var/native/bin:\$PATH" ;; esac
EOF
    mv "$nd/native.$sh.part" "$nd/native.$sh"
  done
  info "wrote $nd/native.zsh, native.bash and bin/ ($(find "$nd/bin" -type f | wc -l) commands)"
  info "every shell: box native enable $TOOL_BOX_NAME --apply (skip one shell: $NATIVE_OFF_VAR=1); without Box: source $nd/native.zsh"
}

cmd_relocate() {
  local was=""
  [ -r "$INST/.boxt-prefix" ] && was=$(cat "$INST/.boxt-prefix")
  if [ -r "$MANIFEST" ] && [ "$was" != "$ROOT" ]; then
    info "folder moved (${was:-unknown} -> $ROOT): re-creating the pixi env (conda prefixes are absolute)"
    [ -d "$ROOT/.pixi" ] && trash_paths "relocate: stale pixi env" "$ROOT/.pixi"
    pixi_install
  else
    info "pixi env already matches $ROOT"
  fi
  is_fn hook_relocate && hook_relocate
  [ -d "$ROOT/native" ] && cmd_native
  return 0
}

cmd_pack() {
  local with_cache=0 out=""
  while [ $# -gt 0 ]; do
    case "$1" in --with-cache) with_cache=1 ;; --out) out=${2:?--out needs a file}; shift ;; *) usage_error "pack: unknown option $1" ;; esac; shift
  done
  local parent base ext=zst comp=(--zstd)
  have zstd || { ext=gz; comp=(-z); }
  out=${out:-$OUT/dist/${NAME}_${PLATFORM}_$(date +%Y_%m_%d).tar.$ext}
  parent=$(dirname "$ROOT"); base=$(basename "$ROOT")
  local ex=(--exclude="$base/.pixi" --exclude="$base/native" --exclude="$base/config/local.env" --exclude='__pycache__'
            --exclude="$base/build" --exclude="$base/log" --exclude="$base/install/.tmp-*")
  [ "$with_cache" = 1 ] || ex+=(--exclude="$base/cache")
  info "packing -> $out (install/ included: portable tarballs need no rebuild)"
  run mkdir -p "$(dirname "$out")"
  run tar "${comp[@]}" -cf "$out" "${ex[@]}" -C "$parent" "$base"
  [ "$DRY" = 1 ] || info "$(du -h "$out" | cut -f1) written. Target: tar xf; ./$NAME bootstrap; ./$NAME doctor"
}

boxt_main() {
  local c=${1:-help}; [ $# -gt 0 ] && shift
  case "$c" in   # tool internals are Linux/macOS builds: exit 3 elsewhere (unknown commands stay exit 2)
    bootstrap|install|update|shell|run|test|examples|native|relocate|pack|doctor) require_supported "$c" ;;
    *) if declare -F "tool_cmd_$c" >/dev/null 2>&1; then require_supported "$c"; fi ;;
  esac
  case "$c" in
    help|-h|--help) cmd_help ;;
    where) no_args "$c" "$@"; cmd_where ;;
    bootstrap) no_args "$c" "$@"; cmd_bootstrap ;;
    install) cmd_install "$@" ;;
    update) cmd_update "$@" ;;
    clean) cmd_clean "$@" ;;
    status) no_args "$c" "$@"; cmd_status ;;
    doctor) no_args "$c" "$@"; cmd_doctor ;;
    shell) cmd_shell "$@" ;;
    run) cmd_run "$@" ;;
    test) cmd_test "$@" ;;
    new) cmd_new "$@" ;;
    examples) cmd_examples "$@" ;;
    native) cmd_native "$@" ;;
    relocate) no_args "$c" "$@"; cmd_relocate ;;
    pack) cmd_pack "$@" ;;
    *)
      if is_fn "tool_cmd_$c"; then "tool_cmd_$c" "$@"
      else usage_error "unknown command: $c"; fi ;;
  esac
}
