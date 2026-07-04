#!/usr/bin/env bash
#
#   ██████╗ ██████╗  █████╗  ██████╗
#   ██╔══██╗██╔══██╗██╔══██╗██╔════╝
#   ██████╔╝██████╔╝███████║██║  ███╗   for Cursor, on macOS
#   ██╔══██╗██╔══██╗██╔══██║██║   ██║
#   ██████╔╝██║  ██║██║  ██║╚██████╔╝
#   ╚═════╝ ╚═════╝ ╚═╝  ╚═╝ ╚═════╝
#
# install-brag-cursor.sh — installer & uninstaller for /brag
# (https://github.com/latent-spaces/brag) in Cursor, on macOS.
#
# You built it. Now let Cursor brag about it.
#
# ─────────────────────────────────────────────────────────────────────────────────────
#  INSTALL
# ─────────────────────────────────────────────────────────────────────────────────────
#   1. Checks/installs Xcode Command Line Tools, Homebrew, Node.js 22+, FFmpeg
#   2. Lets you pick a target:
#        - Project  → <project>/.cursor/skills/         (this repo only)
#        - Global   → ~/.cursor/skills/                 (every Cursor project)
#        - Both
#   3. Clones latent-spaces/brag and installs the /brag skill to the target(s)
#   4. Installs the Hyperframes companion skills (a hard dependency of /brag's
#      hand-off step) via `npx hyperframes skills update`. That CLI ALWAYS
#      installs globally to ~/.claude/skills + ~/.agents/skills — there is no
#      project-scoped flag in the real tool (the --cursor/--claude flags on
#      the public docs page are stale). This script mirrors the relevant
#      packages (hyperframes, hyperframes-*, general-video) explicitly into
#      ~/.cursor/skills, and — for a project target — into the project too.
#   5. Drops a .cursor/rules/brag.mdc fallback for Cursor versions predating
#      native Skills support (< 2.4)
#   6. Warms up headless Chrome and runs `hyperframes doctor`
#   7. Offers `uv` (optional — only improves beat-sync for your own music)
#   8. Offers to store a HeyGen API key (optional — local rendering needs none)
#
# ─────────────────────────────────────────────────────────────────────────────────────
#  UNINSTALL
# ─────────────────────────────────────────────────────────────────────────────────────
#   Removes exactly what this script installed: the /brag skill, the mirrored
#   Hyperframes packages, and the fallback rule — from the target(s) you pick.
#   Always shows a manifest and asks for confirmation first (unless -y).
#   Homebrew/Node/FFmpeg and the global canonical Hyperframes store are left
#   alone by default, since other tools may depend on them — opt in with
#   --purge-hyperframes-global / --purge-heygen-key to remove those too.
#
# ─────────────────────────────────────────────────────────────────────────────────────
#  USAGE
# ─────────────────────────────────────────────────────────────────────────────────────
#   chmod +x install-brag-cursor.sh
#
#   ./install-brag-cursor.sh                          interactive install menu
#   ./install-brag-cursor.sh --project [DIR]          install into a project
#   ./install-brag-cursor.sh --global                  install globally
#   ./install-brag-cursor.sh --both [DIR]              both at once
#   ./install-brag-cursor.sh -y                        no prompts (project, cwd)
#
#   ./install-brag-cursor.sh --uninstall               interactive uninstall menu
#   ./install-brag-cursor.sh --uninstall --project [DIR]
#   ./install-brag-cursor.sh --uninstall --global
#   ./install-brag-cursor.sh --uninstall --both [DIR]
#   ./install-brag-cursor.sh --uninstall -y            no prompts, no purge
#
# Options:
#   --project [DIR]            target: this project (default: cwd)
#   --global                   target: global (~/.cursor/skills)
#   --both [DIR]                both targets at once
#   --uninstall                 switch to uninstall mode
#   --purge-hyperframes-global  (uninstall) also remove the shared global
#                                Hyperframes skill store — affects every tool
#                                and project that reads it, use with care
#   --purge-heygen-key          (uninstall) also delete ~/.heygen/credentials
#   --heygen-key KEY            (install) store a HeyGen API key non-interactively
#   -y, --yes                   no prompts / no confirmation gates
#   -h, --help                  show this help
#
# Safe to run more than once — install is idempotent, uninstall only ever
# touches what this script itself placed.

set -euo pipefail

# ============================================================================
#  Look & feel
# ============================================================================

TTY_OK=false
[[ -t 1 ]] && TTY_OK=true

if [[ -n "${NO_COLOR:-}" ]] || ! $TTY_OK; then
  BOLD="" DIM="" ITAL="" RESET=""
  RED="" GREEN="" YELLOW="" BLUE="" MAGENTA="" CYAN="" WHITE="" GRAY=""
  C_GRAD=()
else
  BOLD=$'\033[1m'; DIM=$'\033[2m'; ITAL=$'\033[3m'; RESET=$'\033[0m'
  RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[0;33m'
  BLUE=$'\033[0;34m'; MAGENTA=$'\033[0;35m'; CYAN=$'\033[0;36m'
  WHITE=$'\033[0;37m'; GRAY=$'\033[0;90m'
  # A little pink → violet → cyan gradient for the wordmark and spinner.
  C_GRAD=($'\033[38;5;213m' $'\033[38;5;207m' $'\033[38;5;171m' $'\033[38;5;135m' \
          $'\033[38;5;99m'  $'\033[38;5;93m'  $'\033[38;5;63m'  $'\033[38;5;51m')
fi

COLS=76
if $TTY_OK && command -v tput >/dev/null 2>&1; then
  COLS="$(tput cols 2>/dev/null || echo 76)"
  [[ "$COLS" -gt 92 ]] && COLS=92
  [[ "$COLS" -lt 48 ]] && COLS=48
fi

repeat_char() {
  local ch="$1" n="$2" line="" i=0
  while [[ $i -lt $n ]]; do line+="$ch"; i=$((i + 1)); done
  printf "%s" "$line"
}

hr()  { printf "%b%s%b\n" "${DIM}" "$(repeat_char '─' "$COLS")" "${RESET}"; }
hr2() { printf "%b%s%b\n" "${DIM}" "$(repeat_char '·' "$COLS")" "${RESET}"; }

# A small rounded box, used for the intro card and the closing receipt.
box_open()  { printf "%b╭%s╮%b\n" "${DIM}" "$(repeat_char '─' $((COLS - 2)))" "${RESET}"; }
box_close() { printf "%b╰%s╯%b\n" "${DIM}" "$(repeat_char '─' $((COLS - 2)))" "${RESET}"; }
_ESC=$'\033'
box_line() {
  local text="$1"
  # Strip ANSI for length accounting (rough — good enough for our own strings).
  local stripped
  stripped="$(printf "%s" "$text" | sed -E "s/${_ESC}\[[0-9;]*m//g")"
  if [[ ${#stripped} -gt $((COLS - 4)) ]]; then
    # Content too wide for a clean box (e.g. a long path) — degrade to a
    # simple prefixed line instead of breaking the border alignment.
    printf "%b│%b %s\n" "${DIM}" "${RESET}" "$text"
    return
  fi
  local space=$((COLS - 4 - ${#stripped}))
  printf "%b│%b %s%*s %b│%b\n" "${DIM}" "${RESET}" "$text" "$space" "" "${DIM}" "${RESET}"
}

gradient_text() {
  # Cycles the C_GRAD palette across each character. Falls back to plain
  # bold text when colors are disabled.
  local text="$1"
  if [[ ${#C_GRAD[@]} -eq 0 ]]; then
    printf "%s" "$text"
    return
  fi
  local i=0 n=${#C_GRAD[@]} out="" ch
  local len=${#text}
  local idx=0
  while [[ $idx -lt $len ]]; do
    ch="${text:$idx:1}"
    if [[ "$ch" == " " ]]; then
      out+=" "
    else
      out+="${C_GRAD[$((i % n))]}${ch}"
      i=$((i + 1))
    fi
    idx=$((idx + 1))
  done
  printf "%s%b" "$out" "${RESET}"
}

banner() {
  echo ""
  hr
  printf "  %s\n" "$(gradient_text '██████╗ ██████╗  █████╗  ██████╗ ')"
  printf "  %s\n" "$(gradient_text '██╔══██╗██╔══██╗██╔══██╗██╔════╝ ')"
  printf "  %s\n" "$(gradient_text '██████╔╝██████╔╝███████║██║  ███╗')"
  printf "  %s\n" "$(gradient_text '██╔══██╗██╔══██╗██╔══██║██║   ██║')"
  printf "  %s\n" "$(gradient_text '██████╔╝██║  ██║██║  ██║╚██████╔╝')"
  printf "  %s\n" "$(gradient_text '╚═════╝ ╚═════╝ ╚═╝  ╚═╝ ╚═════╝ ')"
  echo ""
  if [[ "$MODE" == "uninstall" ]]; then
    printf "  %b%s%b\n" "${BOLD}" "for Cursor, on macOS  ·  ${RED}uninstaller${RESET}${BOLD}" "${RESET}"
  else
    printf "  %b%s%b\n" "${BOLD}${DIM}" "You built it. Now let Cursor brag about it." "${RESET}"
  fi
  hr
}

STEP_TOTAL=0
STEP_CUR=0
step() {
  STEP_CUR=$((STEP_CUR + 1))
  local icon="${2:-▸}"
  printf "\n%b[%d/%d]%b %b%s %s%b\n" "${BOLD}${CYAN}" "$STEP_CUR" "$STEP_TOTAL" "${RESET}" "${BOLD}" "$icon" "$1" "${RESET}"
}

info() { printf "  %b→%b %s\n" "${BLUE}"    "${RESET}" "$1"; }
ok()   { printf "  %b✔%b %s\n" "${GREEN}"   "${RESET}" "$1"; }
warn() { printf "  %b⚠%b %s\n" "${YELLOW}"  "${RESET}" "$1"; }
err()  { printf "  %b✘%b %s\n" "${RED}"     "${RESET}" "$1"; }
skip() { printf "  %b◦%b %s\n" "${GRAY}"    "${RESET}" "$1"; }

# Run a command, show a gradient spinner while it works, report ✔ / ✘. On
# failure, dumps the tail of the captured log so nothing gets swallowed.
run_with_spinner() {
  local label="$1"; shift
  local logfile; logfile="$(mktemp)"

  "$@" >"$logfile" 2>&1 &
  local pid=$!

  if $TTY_OK; then
    local frames=('⠰' '⠹' '⠷' '⠼' '⠴' '⠦' '⠥' '⠧' '⠇' '⠏')
    local i=0 n=${#frames[@]} gn=${#C_GRAD[@]}
    while kill -0 "$pid" 2>/dev/null; do
      local color="${CYAN}"
      [[ $gn -gt 0 ]] && color="${C_GRAD[$((i % gn))]}"
      printf "\r  %b%s%b %s" "$color" "${frames[$((i % n))]}" "${RESET}" "$label"
      i=$((i + 1))
      sleep 0.09
    done
  fi

  local status=0
  wait "$pid" || status=$?

  if [[ $status -eq 0 ]]; then
    printf "\r  %b✔%b %s%*s\n" "${GREEN}" "${RESET}" "$label" 12 ""
  else
    printf "\r  %b✘%b %s%*s\n" "${RED}" "${RESET}" "$label" 12 ""
    printf "    %b┈ log (last 20 lines) ┈%b\n" "${DIM}" "${RESET}"
    tail -n 20 "$logfile" | sed 's/^/    /'
    printf "    %b┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈%b\n" "${DIM}" "${RESET}"
  fi
  rm -f "$logfile"
  return $status
}

confirm() {
  # confirm "question" -> 0 (yes) / 1 (no). Always yes under -y/non-interactive.
  local question="$1"
  if $NONINTERACTIVE || ! $TTY_OK; then return 0; fi
  local answer=""
  read -r -p "  ${question} [j/N]: " answer
  case "$answer" in
    [jJyY]*) return 0 ;;
    *) return 1 ;;
  esac
}

# ============================================================================
#  Argument parsing
# ============================================================================

MODE="install"
INSTALL_PROJECT=false
INSTALL_GLOBAL=false
PROJECT_DIR=""
NONINTERACTIVE=false
HEYGEN_KEY_ARG=""
PURGE_HYPERFRAMES_GLOBAL=false
PURGE_HEYGEN_KEY=false

print_help() {
  grep '^#' "$0" | sed -n '11,80p' | sed 's/^# \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --uninstall) MODE="uninstall" ;;
    --project)
      INSTALL_PROJECT=true
      if [[ -n "${2:-}" && "$2" != --* ]]; then PROJECT_DIR="$2"; shift; fi
      ;;
    --global) INSTALL_GLOBAL=true ;;
    --both)
      INSTALL_PROJECT=true
      INSTALL_GLOBAL=true
      if [[ -n "${2:-}" && "$2" != --* ]]; then PROJECT_DIR="$2"; shift; fi
      ;;
    --heygen-key) HEYGEN_KEY_ARG="${2:-}"; shift ;;
    --purge-hyperframes-global) PURGE_HYPERFRAMES_GLOBAL=true ;;
    --purge-heygen-key) PURGE_HEYGEN_KEY=true ;;
    -y|--yes) NONINTERACTIVE=true ;;
    -h|--help) print_help; exit 0 ;;
    *)
      if [[ -d "$1" ]]; then
        INSTALL_PROJECT=true
        PROJECT_DIR="$1"
      else
        warn "Ignoring unknown option: $1"
      fi
      ;;
  esac
  shift
done

banner

if [[ "$(uname)" != "Darwin" ]]; then
  err "This script targets macOS only."
  exit 1
fi
info "macOS $(sw_vers -productVersion 2>/dev/null || echo unknown)"

# ---------- Target selection (shared by install & uninstall) ----------
if ! $INSTALL_PROJECT && ! $INSTALL_GLOBAL; then
  if $NONINTERACTIVE || ! $TTY_OK; then
    INSTALL_PROJECT=true
  else
    echo ""
    if [[ "$MODE" == "uninstall" ]]; then
      printf "  %bWhere should /brag be removed from?%b\n" "${BOLD}" "${RESET}"
    else
      printf "  %bWhere should /brag be installed?%b\n" "${BOLD}" "${RESET}"
    fi
    echo "    1) This project only    (.cursor/skills in the target folder)"
    echo "    2) Global for Cursor     (~/.cursor/skills — every project)"
    echo "    3) Both"
    echo ""
    choice=""
    while [[ -z "$choice" ]]; do
      read -r -p "  Choice [1-3]: " choice
      case "$choice" in
        1) INSTALL_PROJECT=true ;;
        2) INSTALL_GLOBAL=true ;;
        3) INSTALL_PROJECT=true; INSTALL_GLOBAL=true ;;
        *) warn "Please enter 1, 2 or 3."; choice="" ;;
      esac
    done
  fi
fi

if $INSTALL_PROJECT && [[ -z "$PROJECT_DIR" ]]; then
  if $NONINTERACTIVE || ! $TTY_OK; then
    PROJECT_DIR="$(pwd)"
  else
    read -r -e -p "  Project path [$(pwd)]: " PROJECT_DIR
    PROJECT_DIR="${PROJECT_DIR:-$(pwd)}"
  fi
fi

if $INSTALL_PROJECT; then
  if [[ ! -d "$PROJECT_DIR" ]]; then
    err "No such directory: $PROJECT_DIR"
    exit 1
  fi
  PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
fi

echo ""
printf "  %bTarget(s):%b\n" "${BOLD}" "${RESET}"
$INSTALL_PROJECT && printf "    %b•%b Project  %s/.cursor/skills\n" "${MAGENTA}" "${RESET}" "$PROJECT_DIR"
$INSTALL_GLOBAL  && printf "    %b•%b Global   %s/.cursor/skills\n" "${MAGENTA}" "${RESET}" "$HOME"

# The set of skill package names this script ever places or mirrors.
# Shared by install (what to copy) and uninstall (what it's safe to delete).
hf_relevant_skill_dirs() {
  local store="$1"
  [[ -d "$store" ]] || return 0
  for d in "$store"/*/; do
    [[ -e "$d" ]] || continue
    local name; name="$(basename "$d")"
    if [[ "$name" == "hyperframes" || "$name" == hyperframes-* || "$name" == "general-video" ]]; then
      echo "$name"
    fi
  done
}

# ============================================================================
#  INSTALL
# ============================================================================
run_install() {
  STEP_TOTAL=15

  step "Xcode Command Line Tools" "🛠"
  if ! xcode-select -p >/dev/null 2>&1; then
    info "Kicking off the installer (a dialog will pop up)..."
    xcode-select --install || true
    echo ""
    warn "Finish the Command Line Tools install in the popup, then re-run this script."
    exit 1
  else
    ok "present"
  fi

  step "Homebrew" "🍺"
  if ! command -v brew >/dev/null 2>&1; then
    run_with_spinner "Installing Homebrew" /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    if [[ -x /opt/homebrew/bin/brew ]]; then eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -x /usr/local/bin/brew ]]; then eval "$(/usr/local/bin/brew shellenv)"; fi
  else
    ok "found ($(brew --version | head -1))"
  fi

  step "Node.js 22+" "⬢"
  NEED_NODE=true
  if command -v node >/dev/null 2>&1; then
    NODE_MAJOR="$(node -v | sed 's/^v//' | cut -d. -f1)"
    if [[ "$NODE_MAJOR" -ge 22 ]]; then
      NEED_NODE=false
      ok "Node.js $(node -v) found"
    else
      warn "Node.js $(node -v) found, but >= 22 is required"
    fi
  fi
  if $NEED_NODE; then
    run_with_spinner "Installing Node.js 22" brew install node@22
    brew link --overwrite --force node@22 >/dev/null 2>&1 || true
    hash -r
    ok "Node.js $(node -v 2>/dev/null || echo installed)"
  fi

  step "FFmpeg" "🏞"
  if ! command -v ffmpeg >/dev/null 2>&1; then
    run_with_spinner "Installing FFmpeg" brew install ffmpeg
  else
    ok "found ($(ffmpeg -version | head -1))"
  fi

  step "git" "🌱"
  if ! command -v git >/dev/null 2>&1; then
    err "git not found — should ship with the Xcode Command Line Tools."
    exit 1
  else
    ok "present ($(git --version))"
  fi

  step "Checking for Cursor.app" "🖥"
  if [[ -d "/Applications/Cursor.app" ]]; then
    ok "found in /Applications"
  else
    warn "Cursor.app not found in /Applications (ignore if installed elsewhere)"
  fi

  step "Cloning latent-spaces/brag" "📦"
  WORK_DIR="$(mktemp -d)"
  trap 'rm -rf "$WORK_DIR"' EXIT
  run_with_spinner "Cloning repository" git clone --depth 1 --quiet https://github.com/latent-spaces/brag.git "$WORK_DIR/brag"
  ok "cloned to a scratch directory"

  step "Installing Hyperframes companion skills (global dependency)" "🧩"
  if run_with_spinner "Installing/updating Hyperframes skills" npx --yes hyperframes@latest skills update; then
    :
  else
    warn "Automatic install failed — retry later with: npx hyperframes skills update"
    warn "Usual cause: anonymous GitHub rate limit — 'gh auth login' or a GITHUB_TOKEN helps"
  fi

  HF_UNIVERSAL_STORE="$HOME/.agents/skills"
  HF_CLAUDE_STORE="$HOME/.claude/skills"
  HF_SOURCE_STORE=""
  if [[ -d "$HF_UNIVERSAL_STORE" ]]; then HF_SOURCE_STORE="$HF_UNIVERSAL_STORE"
  elif [[ -d "$HF_CLAUDE_STORE" ]]; then HF_SOURCE_STORE="$HF_CLAUDE_STORE"; fi

  if [[ -n "$HF_SOURCE_STORE" ]]; then
    ok "source store: $HF_SOURCE_STORE"
  else
    warn "No Hyperframes skill store found — /brag's hand-off step will be incomplete"
  fi

  step "Making Hyperframes skills global for Cursor" "🔗"
  if [[ -n "$HF_SOURCE_STORE" ]]; then
    mkdir -p "$HOME/.cursor/skills"
    HF_COUNT=0
    while IFS= read -r name; do
      [[ -z "$name" ]] && continue
      rm -rf "$HOME/.cursor/skills/$name"
      cp -R "$HF_SOURCE_STORE/$name" "$HOME/.cursor/skills/$name"
      HF_COUNT=$((HF_COUNT + 1))
    done < <(hf_relevant_skill_dirs "$HF_SOURCE_STORE")
    ok "$HF_COUNT Hyperframes package(s) mirrored to ~/.cursor/skills"
  else
    warn "skipped — no source store found"
  fi

  step "Installing /brag itself" "🎬"
  deploy_brag_to() {
    local dest="$1"
    mkdir -p "$dest"
    rm -rf "$dest/brag"
    cp -R "$WORK_DIR/brag/skills/brag" "$dest/brag"
  }
  if $INSTALL_PROJECT; then
    deploy_brag_to "$PROJECT_DIR/.cursor/skills"
    ok "/brag → $PROJECT_DIR/.cursor/skills/brag"
    if [[ -n "$HF_SOURCE_STORE" ]]; then
      HF_COUNT=0
      while IFS= read -r name; do
        [[ -z "$name" ]] && continue
        rm -rf "$PROJECT_DIR/.cursor/skills/$name"
        cp -R "$HF_SOURCE_STORE/$name" "$PROJECT_DIR/.cursor/skills/$name"
        HF_COUNT=$((HF_COUNT + 1))
      done < <(hf_relevant_skill_dirs "$HF_SOURCE_STORE")
      ok "$HF_COUNT Hyperframes package(s) also copied into the project (self-contained)"
    fi
  fi
  if $INSTALL_GLOBAL; then
    deploy_brag_to "$HOME/.cursor/skills"
    ok "/brag → $HOME/.cursor/skills/brag"
  fi

  step "Fallback rule for older Cursor versions" "📜"
  if $INSTALL_PROJECT; then
    RULES_DIR="$PROJECT_DIR/.cursor/rules"
    mkdir -p "$RULES_DIR"
    cat > "$RULES_DIR/brag.mdc" <<'EOF'
---
description: Turn the current project into a short, shareable launch video with /brag
alwaysApply: false
---

When the user writes "/brag", "let's brag about this", "make a launch video",
or anything to that effect:

1. Read `.cursor/skills/brag/SKILL.md` in full and follow its steps and
   reference files (`.cursor/skills/brag/references/*.md`) exactly.
2. For the composition step, everything from the installed Hyperframes
   skills under `.cursor/skills/` also applies (read the `/hyperframes`
   entry skill first).
3. Requirements: Node.js 22+, FFmpeg on PATH, `npx hyperframes doctor`
   should run clean.

This rule is a compatibility fallback for Cursor versions without native
Skills support (< 2.4). If Cursor already auto-discovers
`.cursor/skills/brag/`, this rule simply applies in addition — no harm done.
EOF
    ok "written: $RULES_DIR/brag.mdc"
  else
    skip "no project target selected — .cursor/rules is project-local"
  fi

  step "Warming up headless Chrome" "🌐"
  CHECK_DIR="$PROJECT_DIR"
  [[ -z "$CHECK_DIR" ]] && CHECK_DIR="$HOME"
  (cd "$CHECK_DIR" && run_with_spinner "Fetching/verifying Chrome" npx --yes hyperframes browser ensure) \
    || warn "skipped — will be fetched automatically on first render"

  step "Environment check" "🩺"
  (cd "$CHECK_DIR" && npx --yes hyperframes doctor) || warn "hyperframes doctor flagged something — see output above"

  step "uv for richer beat-sync (optional)" "🎵"
  if command -v uv >/dev/null 2>&1; then
    ok "uv already present ($(uv --version))"
  else
    if $NONINTERACTIVE || ! $TTY_OK; then
      skip "non-interactive — /brag falls back to 'npx hyperframes beats' automatically"
    elif confirm "Install uv for more precise beat-sync on your own music?"; then
      run_with_spinner "Installing uv" brew install uv
    else
      skip "skipped — the built-in fallback covers this just fine"
    fi
  fi

  step "HeyGen API key (optional)" "🔑"
  HEYGEN_KEY="$HEYGEN_KEY_ARG"
  if [[ -z "$HEYGEN_KEY" ]] && ! $NONINTERACTIVE && $TTY_OK; then
    read -r -p "  Store a HeyGen API key now? (Enter to skip): " HEYGEN_KEY
  fi
  if [[ -n "$HEYGEN_KEY" ]]; then
    echo "$HEYGEN_KEY" | npx --yes hyperframes auth login --api-key && ok "saved to ~/.heygen/credentials"
  else
    skip "skipped — local rendering works without a HeyGen account"
  fi

  echo ""
  box_open
  box_line "$(printf "%b✔ You're brag-ready.%b" "${BOLD}${GREEN}" "${RESET}")"
  box_line ""
  $INSTALL_GLOBAL  && box_line "$(printf "/brag is now available in %bevery%b Cursor project on this machine" "${BOLD}" "${RESET}")"
  box_line "$(printf "Try a tone: %b/brag --tone chaotic%b" "${DIM}" "${RESET}")"
  box_close
  if $INSTALL_PROJECT; then
    echo ""
    info "$(printf "Open %b%s%b in Cursor, then type: %blet's /brag%b" "${CYAN}" "$PROJECT_DIR" "${RESET}" "${BOLD}" "${RESET}")"
  fi
  echo ""
  hr2
  printf "  %bMore projects / uninstall:%b\n" "${DIM}" "${RESET}"
  echo "    ./install-brag-cursor.sh --project /path/to/other/project"
  echo "    ./install-brag-cursor.sh --global"
  echo "    ./install-brag-cursor.sh --uninstall"
  hr2
}

# ============================================================================
#  UNINSTALL
# ============================================================================
run_uninstall() {
  STEP_TOTAL=3

  step "Scanning what's installed" "🔍"

  declare -a FOUND_PATHS=()
  scan_target() {
    local base="$1" label="$2"
    [[ -d "$base/brag" ]] && FOUND_PATHS+=("$base/brag")
    while IFS= read -r name; do
      [[ -z "$name" ]] && continue
      FOUND_PATHS+=("$base/$name")
    done < <(hf_relevant_skill_dirs "$base")
    if [[ "$label" == "project" ]]; then
      local rule_file; rule_file="$(dirname "$base")/rules/brag.mdc"
      [[ -f "$rule_file" ]] && FOUND_PATHS+=("$rule_file")
    fi
  }
  $INSTALL_PROJECT && scan_target "$PROJECT_DIR/.cursor/skills" "project"
  $INSTALL_GLOBAL  && scan_target "$HOME/.cursor/skills" "global"

  if [[ ${#FOUND_PATHS[@]} -eq 0 ]]; then
    ok "nothing here to remove — already squeaky clean"
  else
    info "found ${#FOUND_PATHS[@]} item(s):"
    for p in "${FOUND_PATHS[@]}"; do printf "    %b✘%b %s\n" "${RED}" "${RESET}" "$p"; done
  fi

  if $PURGE_HYPERFRAMES_GLOBAL; then
    warn "also selected: purge the SHARED global Hyperframes store (~/.claude/skills, ~/.agents/skills, and mirrors — affects other tools/projects too)"
  fi
  if $PURGE_HEYGEN_KEY; then
    warn "also selected: delete ~/.heygen/credentials (shared with the 'heygen' CLI, if installed)"
  fi

  step "Confirmation" "❓"
  if [[ ${#FOUND_PATHS[@]} -eq 0 ]] && ! $PURGE_HYPERFRAMES_GLOBAL && ! $PURGE_HEYGEN_KEY; then
    ok "nothing to confirm"
  elif ! confirm "Remove everything listed above?"; then
    err "aborted — nothing was removed"
    exit 1
  else
    ok "confirmed"
  fi

  step "Removing" "🧹"
  for p in "${FOUND_PATHS[@]}"; do
    rm -rf "$p"
    ok "removed $p"
  done

  # Tidy up now-empty directories we may have created (never touches
  # anything that still has content — i.e. the user's own skills/rules).
  for d in \
    "${PROJECT_DIR:-}/.cursor/skills" "${PROJECT_DIR:-}/.cursor/rules" "${PROJECT_DIR:-}/.cursor" \
    "$HOME/.cursor/skills"
  do
    [[ -n "$d" && -d "$d" ]] && rmdir "$d" 2>/dev/null && info "cleaned up empty $d" || true
  done

  if $PURGE_HYPERFRAMES_GLOBAL; then
    HF_NAMES=()
    for store in "$HOME/.agents/skills" "$HOME/.claude/skills"; do
      while IFS= read -r name; do
        [[ -z "$name" ]] && continue
        [[ " ${HF_NAMES[*]:-} " == *" $name "* ]] || HF_NAMES+=("$name")
      done < <(hf_relevant_skill_dirs "$store")
    done
    if [[ ${#HF_NAMES[@]} -gt 0 ]]; then
      if command -v npx >/dev/null 2>&1 && run_with_spinner "Removing shared Hyperframes packages via 'skills remove'" \
           npx --yes skills remove "${HF_NAMES[@]}" -g --yes; then
        :
      else
        warn "'skills remove' failed — falling back to direct delete"
        for store in "$HOME/.agents/skills" "$HOME/.claude/skills" "$HOME/.cursor/skills" "$HOME/.codex/skills" "$HOME/.gemini/skills"; do
          for name in "${HF_NAMES[@]}"; do
            rm -rf "${store:?}/${name:?}" 2>/dev/null || true
          done
        done
      fi
      ok "shared Hyperframes store purged"
    else
      skip "no shared Hyperframes packages found"
    fi
  fi

  if $PURGE_HEYGEN_KEY; then
    if [[ -f "$HOME/.heygen/credentials" ]]; then
      rm -f "$HOME/.heygen/credentials"
      ok "HeyGen credentials removed"
    else
      skip "no HeyGen credentials found"
    fi
  fi

  echo ""
  box_open
  box_line "$(printf "%b✔ /brag has left the building.%b" "${BOLD}${GREEN}" "${RESET}")"
  box_line ""
  box_line "$(printf "Node, Homebrew, FFmpeg and Cursor itself were left untouched.")"
  $PURGE_HYPERFRAMES_GLOBAL || box_line "$(printf "Shared Hyperframes skills kept — rerun with %b--purge-hyperframes-global%b to remove those too" "${DIM}" "${RESET}")"
  box_close
}

if [[ "$MODE" == "uninstall" ]]; then
  run_uninstall
else
  run_install
fi
