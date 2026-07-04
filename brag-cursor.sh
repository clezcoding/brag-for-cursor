#!/usr/bin/env bash
#
#   ███████╗ ███████╗  █████╗  ███████╗
#   ██╔══██╗██╔══██╗██╔══██╗██╔════╝
#   ██████╔╝██████╔╝███████║██║  ███╗
#   ██╔══██╗██╔══██╗██╔══██║██║   ██║
#   ██████╔╝██║  ██║██║  ██║╚██████╔╝
#   ╚═════╝ █║  ██╝█║  ██╝ ╚═════╝
#
# brag-cursor.sh — installer & uninstaller for /brag in Cursor, on macOS.
# https://github.com/latent-spaces/brag
#
# You built it. Now brag. This script gets Cursor ready to do that for you.
#
# WHAT IT INSTALLS
#   - Xcode Command Line Tools, Homebrew, Node.js 22+, FFmpeg (if missing)
#   - The /brag skill, cloned from latent-spaces/brag
#   - The Hyperframes companion skills /brag depends on for video composition
#     (installed globally by the Hyperframes CLI itself — see comments below
#     — then mirrored to wherever you asked for: this project, global, or both)
#   - A .cursor/rules/brag.mdc fallback for older Cursor versions
#   - Optionally: uv (nicer beat-sync for custom music) and a HeyGen API key
#
# USAGE
#   chmod +x brag-cursor.sh
#   ./brag-cursor.sh                          interactive menu
#   ./brag-cursor.sh install --project        this folder only
#   ./brag-cursor.sh install --project /path   a specific project
#   ./brag-cursor.sh install --global          every Cursor project on this Mac
#   ./brag-cursor.sh install --both /path      both at once
#   ./brag-cursor.sh uninstall                 interactive removal menu
#   ./brag-cursor.sh uninstall --both /path --purge   remove everything, no prompts
#   ./brag-cursor.sh -y                        no prompts (defaults to install --project, cwd)
#
# OPTIONS
#   install | uninstall   Mode. Default: install.
#   --project [DIR]       Target: <DIR>/.cursor/skills (default DIR: cwd)
#   --global              Target: ~/.cursor/skills
#   --both [DIR]          Both of the above
#   --purge               (uninstall) also remove the Hyperframes companion
#                         skills and skip confirmation prompts
#   --heygen-key KEY      Store a HeyGen API key non-interactively
#   -y, --yes             No prompts at all
#   -h, --help            Show this help
#
# Safe to re-run. Idempotent. Nothing here touches Node/FFmpeg/Homebrew on
# uninstall — those are your machine's, not this script's, to remove.

set -euo pipefail

# ============================================================================
#  THEME — colors, glyphs, and small UI helpers
# ============================================================================

TTY_OK=false
[[ -t 1 ]] && TTY_OK=true

COLOR_OK=true
[[ -n "${NO_COLOR:-}" ]] && COLOR_OK=false
$TTY_OK || COLOR_OK=false

TERM_COLORS=8
if $TTY_OK && command -v tput >/dev/null 2>&1; then
  TERM_COLORS="$(tput colors 2>/dev/null || echo 8)"
fi

if $COLOR_OK && [[ "$TERM_COLORS" -ge 256 ]]; then
  RESET=$'\033[0m'; BOLD=$'\033[1m'; DIM=$'\033[2m'
  RED=$'\033[38;5;203m'; GREEN=$'\033[38;5;114m'; YELLOW=$'\033[38;5;221m'
  BLUE=$'\033[38;5;75m'; CYAN=$'\033[38;5;80m'; MAGENTA=$'\033[38;5;170m'
  PINK=$'\033[38;5;212m'; GRAY=$'\033[38;5;244m'; ORANGE=$'\033[38;5;215m'
elif $COLOR_OK; then
  RESET=$'\033[0m'; BOLD=$'\033[1m'; DIM=$'\033[2m'
  RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[0;33m'
  BLUE=$'\033[0;34m'; CYAN=$'\033[0;36m'; MAGENTA=$'\033[0;35m'
  PINK=$'\033[0;35m'; GRAY=$'\033[0;90m'; ORANGE=$'\033[0;33m'
else
  RESET=""; BOLD=""; DIM=""
  RED=""; GREEN=""; YELLOW=""; BLUE=""; CYAN=""; MAGENTA=""; PINK=""; GRAY=""; ORANGE=""
fi

COLS=80
if $TTY_OK && command -v tput >/dev/null 2>&1; then
  COLS="$(tput cols 2>/dev/null || echo 80)"
fi
RULE_WIDTH=$COLS
[[ "$RULE_WIDTH" -gt 78 ]] && RULE_WIDTH=78
[[ "$RULE_WIDTH" -lt 40 ]] && RULE_WIDTH=40

rule() {
  local ch="${1:-─}" line="" i=0
  while [[ $i -lt $RULE_WIDTH ]]; do line+="$ch"; i=$((i + 1)); done
  printf "%b%s%b\n" "${GRAY}" "$line" "${RESET}"
}

banner() {
  local mode_label="$1"
  echo ""
  printf "%b" "${MAGENTA}${BOLD}"
  rule "═"
  printf "%b  🎬  %b/brag%b%b  %b·%b  %bCursor Edition%b\n" \
    "${MAGENTA}${BOLD}" "${PINK}" "${RESET}${MAGENTA}${BOLD}" "" "${GRAY}" "${MAGENTA}${BOLD}" "${CYAN}" "${RESET}"
  printf "  %bYou built it. Now brag — this just gets Cursor ready to do it.%b\n" "${DIM}" "${RESET}"
  printf "%b" "${MAGENTA}"
  rule "═"
  printf "  %b%s%b\n" "${BOLD}${ORANGE}" "$mode_label" "${RESET}"
  rule "─"
}

# Step counter with a little progress bar, because plain numbers are boring.
STEP_TOTAL=1
STEP_CUR=0
step() {
  STEP_CUR=$((STEP_CUR + 1))
  local barlen=16
  local filled=$(( STEP_CUR * barlen / STEP_TOTAL ))
  [[ $filled -gt $barlen ]] && filled=$barlen
  local bar="" i=0
  while [[ $i -lt $barlen ]]; do
    if [[ $i -lt $filled ]]; then bar+="▰"; else bar+="▱"; fi
    i=$((i + 1))
  done
  printf "\n%b[%02d/%02d]%b %b%s%b  %b%s%b\n" \
    "${BOLD}${CYAN}" "$STEP_CUR" "$STEP_TOTAL" "${RESET}" \
    "${MAGENTA}" "$bar" "${RESET}" \
    "${BOLD}" "$1" "${RESET}"
}

info() { printf "   %b→%b  %s\n" "${BLUE}" "${RESET}" "$1"; }
ok()   { printf "   %b✔%b  %s\n" "${GREEN}" "${RESET}" "$1"; }
warn() { printf "   %b⚠%b  %s\n" "${YELLOW}" "${RESET}" "$1"; }
err()  { printf "   %b✘%b  %s\n" "${RED}" "${RESET}" "$1"; }
skip() { printf "   %b·%b  %s\n" "${GRAY}" "${RESET}" "$1"; }

section() {
  echo ""
  printf "%b%s%b\n" "${BOLD}${PINK}" "── $1 ──" "${RESET}"
}

# Runs a command with a spinner (real TTY) and reports ✔/✘. Output is hidden
# unless the command fails, in which case the tail of its log is shown.
run_with_spinner() {
  local label="$1"; shift
  local logfile
  logfile="$(mktemp)"

  "$@" >"$logfile" 2>&1 &
  local pid=$!

  if $TTY_OK; then
    local frames=('⠠b' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local i=0
    while kill -0 "$pid" 2>/dev/null; do
      printf "\r   %b%s%b  %s" "${CYAN}" "${frames[$((i % 10))]}" "${RESET}" "$label"
      i=$((i + 1))
      sleep 0.1
    done
  fi

  local status=0
  wait "$pid" || status=$?

  if [[ $status -eq 0 ]]; then
    printf "\r   %b✔%b  %s%*s\n" "${GREEN}" "${RESET}" "$label" 12 ""
  else
    printf "\r   %b✘%b  %s%*s\n" "${RED}" "${RESET}" "$label" 12 ""
    printf "   %b┊ last 20 log lines%b\n" "${DIM}" "${RESET}"
    tail -n 20 "$logfile" | sed 's/^/   ┊ /'
  fi
  rm -f "$logfile"
  return $status
}

confirm() {
  # confirm "question" default(y/n) -> returns 0 for yes
  local question="$1" default="${2:-n}" answer
  local hint="y/N"
  [[ "$default" == "y" ]] && hint="Y/n"
  if $NONINTERACTIVE || ! $TTY_OK; then
    [[ "$default" == "y" ]] && return 0 || return 1
  fi
  read -r -p "   ${question} [${hint}]: " answer
  answer="${answer:-$default}"
  [[ "$answer" =~ ^[jJyY] ]]
}

# ============================================================================
#  ARGUMENTS
# ============================================================================

MODE=""
INSTALL_PROJECT=false
INSTALL_GLOBAL=false
PROJECT_DIR=""
NONINTERACTIVE=false
PURGE=false
HEYGEN_KEY_ARG=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    install|uninstall) MODE="$1" ;;
    --project)
      INSTALL_PROJECT=true
      if [[ -n "${2:-}" && "$2" != --* ]]; then PROJECT_DIR="$2"; shift; fi
      ;;
    --global) INSTALL_GLOBAL=true ;;
    --both)
      INSTALL_PROJECT=true; INSTALL_GLOBAL=true
      if [[ -n "${2:-}" && "$2" != --* ]]; then PROJECT_DIR="$2"; shift; fi
      ;;
    --purge) PURGE=true ;;
    --heygen-key) HEYGEN_KEY_ARG="${2:-}"; shift ;;
    -y|--yes) NONINTERACTIVE=true ;;
    -h|--help)
      grep '^#' "$0" | sed 's/^# \{0,1\}//' | sed -n '2,50p'
      exit 0
      ;;
    *)
      if [[ -d "$1" ]]; then
        INSTALL_PROJECT=true
        PROJECT_DIR="$1"
      else
        warn "Ignoring unknown argument: $1"
      fi
      ;;
  esac
  shift
done

# ---------- macOS check ----------
if [[ "$(uname)" != "Darwin" ]]; then
  echo "✘ This script is macOS-only."
  exit 1
fi

# ---------- mode ----------
if [[ -z "$MODE" ]]; then
  if $NONINTERACTIVE || ! $TTY_OK; then
    MODE="install"
  else
    banner "Choose your adventure"
    echo "   1) Install /brag for Cursor"
    echo "   2) Uninstall /brag from Cursor"
    echo ""
    choice=""
    while [[ -z "$choice" ]]; do
      read -r -p "   Choice [1-2]: " choice
      case "$choice" in
        1) MODE="install" ;;
        2) MODE="uninstall" ;;
        *) warn "Type 1 or 2."; choice="" ;;
      esac
    done
  fi
fi

# ---------- target selection (shared by install & uninstall) ----------
choose_targets() {
  if ! $INSTALL_PROJECT && ! $INSTALL_GLOBAL; then
    if $NONINTERACTIVE || ! $TTY_OK; then
      INSTALL_PROJECT=true
    else
      echo ""
      printf "   %bWhere?%b\n" "${BOLD}" "${RESET}"
      echo "   1) Just this project      (.cursor/skills in the target folder)"
      echo "   2) Global, every project  (~/.cursor/skills)"
      echo "   3) Both"
      echo ""
      choice=""
      while [[ -z "$choice" ]]; do
        read -r -p "   Choice [1-3]: " choice
        case "$choice" in
          1) INSTALL_PROJECT=true ;;
          2) INSTALL_GLOBAL=true ;;
          3) INSTALL_PROJECT=true; INSTALL_GLOBAL=true ;;
          *) warn "Type 1, 2 or 3."; choice="" ;;
        esac
      done
    fi
  fi

  if $INSTALL_PROJECT && [[ -z "$PROJECT_DIR" ]]; then
    if $NONINTERACTIVE || ! $TTY_OK; then
      PROJECT_DIR="$(pwd)"
    else
      read -r -e -p "   Project path [$(pwd)]: " PROJECT_DIR
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
  printf "   %bTarget(s):%b\n" "${BOLD}" "${RESET}"
  $INSTALL_PROJECT && echo "     • Project  $PROJECT_DIR/.cursor/skills"
  $INSTALL_GLOBAL  && echo "     • Global   $HOME/.cursor/skills"
}

# Only the packages /brag actually needs, out of everything Hyperframes ships:
# the entry skill, every hyperframes-* sub-package, and the general-video
# fallback workflow /brag's own docs point to.
hf_relevant_skill_dirs() {
  local store="$1"
  [[ -d "$store" ]] || return 0
  for d in "$store"/*/; do
    [[ -e "$d" ]] || continue
    local name
    name="$(basename "$d")"
    if [[ "$name" == "hyperframes" || "$name" == hyperframes-* || "$name" == "general-video" ]]; then
      echo "$name"
    fi
  done
}

# ============================================================================
#  INSTALL
# ============================================================================
do_install() {
  banner "Installing"
  info "macOS $(sw_vers -productVersion 2>/dev/null || echo "(version unknown)")"
  choose_targets

  STEP_TOTAL=15

  section "Dependencies"

  step "Xcode Command Line Tools"
  if ! xcode-select -p >/dev/null 2>&1; then
    info "Kicking off the install (a dialog will pop up)..."
    xcode-select --install || true
    echo ""
    warn "Finish that install, then run this script again."
    exit 1
  else
    ok "present"
  fi

  step "Homebrew"
  if ! command -v brew >/dev/null 2>&1; then
    run_with_spinner "Installing Homebrew" /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    if [[ -x /opt/homebrew/bin/brew ]]; then eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -x /usr/local/bin/brew ]]; then eval "$(/usr/local/bin/brew shellenv)"; fi
  else
    ok "found ($(brew --version | head -1))"
  fi

  step "Node.js 22+"
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

  step "FFmpeg"
  if ! command -v ffmpeg >/dev/null 2>&1; then
    run_with_spinner "Installing FFmpeg" brew install ffmpeg
  else
    ok "found ($(ffmpeg -version | head -1))"
  fi

  step "git"
  if ! command -v git >/dev/null 2>&1; then
    err "git not found - should ship with the Xcode Command Line Tools."
    exit 1
  else
    ok "found ($(git --version))"
  fi

  step "Cursor.app"
  if [[ -d "/Applications/Cursor.app" ]]; then
    ok "found in /Applications"
  else
    warn "not found in /Applications (fine if installed elsewhere)"
  fi

  section "The skill itself"

  step "Cloning latent-spaces/brag"
  WORK_DIR="$(mktemp -d)"
  trap 'rm -rf "$WORK_DIR"' EXIT
  run_with_spinner "Cloning" git clone --depth 1 --quiet https://github.com/latent-spaces/brag.git "$WORK_DIR/brag"
  ok "cloned to a scratch directory"

  # --------------------------------------------------------------------------
  # Hyperframes companion skills — a global install, by design.
  #
  # Verified against the heygen-com/hyperframes source: `npx hyperframes
  # skills --cursor` does NOT exist (the public docs describing per-agent
  # flags are stale). The real command is `hyperframes skills update`, it
  # takes no target flags, and it always writes to ~/.claude/skills +
  # ~/.agents/skills — Cursor reads the latter globally. The CLI *also*
  # mirrors into ~/.cursor/skills, but only if ~/.cursor already exists
  # (i.e. Cursor has run at least once) — so this script does that mirroring
  # itself too, unconditionally, to not depend on install order.
  # --------------------------------------------------------------------------
  step "Hyperframes companion skills (global — that's how upstream ships it)"
  if run_with_spinner "Installing/updating via Hyperframes CLI" npx --yes hyperframes@latest skills update; then
    :
  else
    warn "Automatic install failed — retry later with: npx hyperframes skills update"
    warn "Usual cause: anonymous GitHub rate limit. Fix: 'gh auth login' or export GITHUB_TOKEN"
  fi

  HF_UNIVERSAL_STORE="$HOME/.agents/skills"
  HF_CLAUDE_STORE="$HOME/.claude/skills"
  HF_SOURCE_STORE=""
  if [[ -d "$HF_UNIVERSAL_STORE" ]]; then HF_SOURCE_STORE="$HF_UNIVERSAL_STORE"
  elif [[ -d "$HF_CLAUDE_STORE" ]]; then HF_SOURCE_STORE="$HF_CLAUDE_STORE"; fi

  if [[ -n "$HF_SOURCE_STORE" ]]; then
    ok "found companion skills in $HF_SOURCE_STORE"
  else
    warn "no Hyperframes skill store found — the video-composition handoff will be incomplete"
  fi

  step "Making sure Cursor sees them globally (~/.cursor/skills)"
  if [[ -n "$HF_SOURCE_STORE" ]]; then
    mkdir -p "$HOME/.cursor/skills"
    HF_COUNT=0
    while IFS= read -r name; do
      [[ -z "$name" ]] && continue
      rm -rf "$HOME/.cursor/skills/$name"
      cp -R "$HF_SOURCE_STORE/$name" "$HOME/.cursor/skills/$name"
      HF_COUNT=$((HF_COUNT + 1))
    done < <(hf_relevant_skill_dirs "$HF_SOURCE_STORE")
    ok "mirrored $HF_COUNT Hyperframes package(s) into $HOME/.cursor/skills"
  else
    skip "nothing to mirror"
  fi

  step "Installing /brag"
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
      ok "+ $HF_COUNT Hyperframes package(s) copied in too — project is self-contained"
    fi
  fi
  if $INSTALL_GLOBAL; then
    deploy_brag_to "$HOME/.cursor/skills"
    ok "/brag → $HOME/.cursor/skills/brag"
  fi

  step "Fallback rule for older Cursor versions"
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
2. For the video composition step, also follow everything in the installed
   Hyperframes skills under `.cursor/skills/` (read `/hyperframes` first).
3. Prerequisite: Node.js 22+, FFmpeg on PATH, `npx hyperframes doctor`
   should pass without errors.

This rule is a compatibility fallback for Cursor versions without native
Skills support (< 2.4). If your Cursor already auto-discovers
`.cursor/skills/brag/`, this rule fires alongside it — harmlessly.
EOF
    ok "written: $RULES_DIR/brag.mdc"
  else
    skip "no project target selected — rules are project-scoped"
  fi

  section "Render pipeline"

  step "Warming up headless Chrome"
  CHECK_DIR="$PROJECT_DIR"
  [[ -z "$CHECK_DIR" ]] && CHECK_DIR="$HOME"
  (cd "$CHECK_DIR" && run_with_spinner "Fetching/verifying Chrome" npx --yes hyperframes browser ensure) \
    || warn "skipped — will happen automatically on first render"

  step "Environment check (hyperframes doctor)"
  (cd "$CHECK_DIR" && npx --yes hyperframes doctor) || warn "hyperframes doctor flagged something above ↑"

  step "uv, for nicer beat-sync on custom tracks (optional)"
  if command -v uv >/dev/null 2>&1; then
    ok "already have it ($(uv --version))"
  else
    if confirm "Install uv for precise beat-sync on your own music tracks?" n; then
      run_with_spinner "Installing uv" brew install uv
    else
      skip "no worries — /brag falls back to 'npx hyperframes beats' automatically"
    fi
  fi

  step "HeyGen API key (optional)"
  HEYGEN_KEY="$HEYGEN_KEY_ARG"
  if [[ -z "$HEYGEN_KEY" ]] && ! $NONINTERACTIVE && $TTY_OK; then
    read -r -p "   Add a HeyGen API key now? Enter to skip: " HEYGEN_KEY
  fi
  if [[ -n "$HEYGEN_KEY" ]]; then
    echo "$HEYGEN_KEY" | npx --yes hyperframes auth login --api-key && ok "saved to ~/.heygen/credentials"
  else
    skip "local rendering works great without a HeyGen account"
  fi

  echo ""
  printf "%b" "${GREEN}${BOLD}"
  rule "═"
  printf "  ✨  Done. Go make something worth bragging about.\n"
  rule "═"
  printf "%b\n" "${RESET}"
  printf "%bNext:%b\n" "${BOLD}" "${RESET}"
  $INSTALL_PROJECT && echo "   • Open '$PROJECT_DIR' in Cursor, then in the agent chat: let's /brag"
  $INSTALL_GLOBAL  && echo "   • /brag now works in every Cursor project on this Mac"
  echo "   • Try a mood: /brag --tone chaotic"
  echo ""
  echo "More installs:"
  echo "   ./$(basename "$0") install --project /path/to/other-project"
  echo "   ./$(basename "$0") install --global"
  echo "Uninstall anytime:"
  echo "   ./$(basename "$0") uninstall"
}

# ============================================================================
#  UNINSTALL
# ============================================================================
do_uninstall() {
  banner "Uninstalling"
  choose_targets

  if ! $PURGE; then
    echo ""
    if confirm "Also remove the Hyperframes companion skills from these locations?" n; then
      PURGE=true
    fi
  fi

  STEP_TOTAL=1
  $INSTALL_PROJECT && STEP_TOTAL=$((STEP_TOTAL + 2))
  $INSTALL_GLOBAL && STEP_TOTAL=$((STEP_TOTAL + 1))

  section "Removing"

  remove_from() {
    local dest="$1" label="$2"
    step "Cleaning $label"
    local removed=0

    if [[ -d "$dest/brag" ]]; then
      rm -rf "$dest/brag"
      ok "removed $dest/brag"
      removed=$((removed + 1))
    else
      skip "$dest/brag not present"
    fi

    if $PURGE; then
      local n=0
      for d in "$dest"/*/; do
        [[ -e "$d" ]] || continue
        local name; name="$(basename "$d")"
        if [[ "$name" == "hyperframes" || "$name" == hyperframes-* || "$name" == "general-video" ]]; then
          rm -rf "$dest/$name"
          n=$((n + 1))
        fi
      done
      [[ $n -gt 0 ]] && ok "removed $n Hyperframes companion package(s)" || skip "no Hyperframes packages found here"
    fi
  }

  if $INSTALL_PROJECT; then
    remove_from "$PROJECT_DIR/.cursor/skills" "$PROJECT_DIR/.cursor/skills"
    step "Removing the project rule"
    if [[ -f "$PROJECT_DIR/.cursor/rules/brag.mdc" ]]; then
      rm -f "$PROJECT_DIR/.cursor/rules/brag.mdc"
      ok "removed $PROJECT_DIR/.cursor/rules/brag.mdc"
    else
      skip "no rule file found"
    fi
  fi

  if $INSTALL_GLOBAL; then
    remove_from "$HOME/.cursor/skills" "$HOME/.cursor/skills (global)"
  fi

  step "HeyGen credentials (optional)"
  if [[ -f "$HOME/.heygen/credentials" ]]; then
    if confirm "Remove your saved HeyGen API key too? (shared with the heygen CLI)" n; then
      rm -f "$HOME/.heygen/credentials"
      ok "removed ~/.heygen/credentials"
    else
      skip "kept ~/.heygen/credentials"
    fi
  else
    skip "no HeyGen credentials found"
  fi

  echo ""
  printf "%b" "${CYAN}${BOLD}"
  rule "═"
  printf "  🧹  All clear. /brag is uninstalled from the target(s) above.\n"
  rule "═"
  printf "%b\n" "${RESET}"
  info "Node.js, FFmpeg, Homebrew, and uv were left untouched — those are your machine's, not /brag's."
  info "Reinstall anytime with: ./$(basename "$0") install"
}

# ============================================================================
#  GO
# ============================================================================
if [[ "$MODE" == "uninstall" ]]; then
  do_uninstall
else
  do_install
fi
