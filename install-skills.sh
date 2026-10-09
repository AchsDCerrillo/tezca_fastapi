#!/usr/bin/env bash
# Install the tezca-fastapi skills into coding agents: Claude Code as a real plugin through the
# Claude plugin marketplace (claude-plugin), or as plain Agent Skills folders for Codex, OpenCode,
# Gemini CLI, Antigravity, GitHub Copilot, Cursor and Claude Code (claude).
#
# Safe by design:
#   - Skills are installed as self-contained folders named "tezca-<skill>" (no clash with your own skills).
#   - Each installed folder carries a marker file; the script only ever updates/removes folders that
#     have that marker. An existing folder without it is left untouched (skipped with a warning).
#   - No agent config file (settings.json, opencode.json, AGENTS.md, ...) is edited by this script.
#     claude-plugin goes through Claude's own `claude plugin` CLI, which merges its entries safely.
#
# Usage:
#   ./install-skills.sh                                   # interactive
#   ./install-skills.sh --scope project --agents all --project-dir ~/code/my-api
#   ./install-skills.sh --scope user --agents codex,gemini
#   ./install-skills.sh --scope project --agents claude-plugin --marketplace-source https://github.com/me/tezca_fastapi_plugin.git
#   ./install-skills.sh --uninstall --scope project --agents all --project-dir .
#   ./install-skills.sh --list-agents
# Options: --scope project|user  --agents a,b|all  --project-dir DIR  --marketplace-source URL|PATH
#          --dry-run  --uninstall  --yes  -h

set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREFIX="tezca-"
MARKER=".tezca-fastapi-install"
ALL_AGENTS="claude-plugin codex opencode gemini antigravity copilot cursor claude"
DEFAULT_AGENTS="claude-plugin,codex,opencode,gemini,antigravity,copilot,cursor"
PLUGIN_ID="tezca-fastapi@tezca-fastapi-marketplace"
MARKETPLACE_NAME="tezca-fastapi-marketplace"

SCOPE=""
AGENTS=""
PROJECT_DIR=""
DRY_RUN=0
UNINSTALL=0
ASSUME_YES=0
MARKETPLACE_SOURCE=""
DO_CLAUDE_PLUGIN=0

# ---------- helpers ----------
c_bold=$'\033[1m'; c_yel=$'\033[33m'; c_grn=$'\033[32m'; c_red=$'\033[31m'; c_off=$'\033[0m'
[ -t 1 ] || { c_bold=""; c_yel=""; c_grn=""; c_red=""; c_off=""; }
info() { printf '%s\n' "$*"; }
ok()   { printf '%s✔%s %s\n' "$c_grn" "$c_off" "$*"; }
warn() { printf '%s!%s %s\n' "$c_yel" "$c_off" "$*" >&2; }
die()  { printf '%s✘ %s%s\n' "$c_red" "$*" "$c_off" >&2; exit 1; }
run()  { if [ "$DRY_RUN" = 1 ]; then printf '  [dry-run] %s\n' "$*"; else "$@"; fi; }

usage() { sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0; }

agent_label() {
  case "$1" in
    codex) echo "OpenAI Codex" ;;
    opencode) echo "OpenCode" ;;
    gemini) echo "Gemini CLI" ;;
    antigravity) echo "Google Antigravity" ;;
    copilot) echo "GitHub Copilot (VS Code / CLI / cloud agent)" ;;
    cursor) echo "Cursor" ;;
    claude-plugin) echo "Claude Code plugin via the Claude marketplace (recommended for Claude)" ;;
    claude) echo "Claude Code plain skills folder (only if you can't use the plugin)" ;;
    *) echo "$1" ;;
  esac
}

# Skill directory for an agent + scope. Project scope: every agent except Claude reads the shared
# Agent Skills location .agents/skills, so one copy serves them all. Empty output = unsupported.
agent_dir() {
  local agent="$1" scope="$2"
  if [ "$scope" = project ]; then
    case "$agent" in
      claude) echo "$PROJECT_DIR/.claude/skills" ;;
      *)      echo "$PROJECT_DIR/.agents/skills" ;;
    esac
  else
    case "$agent" in
      codex|opencode|copilot) echo "$HOME/.agents/skills" ;;
      gemini)      echo "$HOME/.gemini/skills" ;;
      antigravity) echo "$HOME/.gemini/config/skills" ;;
      claude)      echo "$HOME/.claude/skills" ;;
      cursor)      echo "" ;;   # no documented user-level skills folder
    esac
  fi
}

agent_note() {
  case "$1" in
    gemini) echo "Gemini CLI: Agent Skills may need to be enabled in your Gemini settings (not changed by this script)." ;;
    cursor) [ "$SCOPE" = user ] && echo "Cursor: no documented user-level skills folder; install at project level instead." ;;
    claude) echo "Claude Code plain skills: if the tezca-fastapi plugin is also installed you'll see both copies; prefer claude-plugin." ;;
  esac
  return 0
}

# ---------- args ----------
while [ $# -gt 0 ]; do
  case "$1" in
    --scope) SCOPE="${2:-}"; shift 2 ;;
    --agents) AGENTS="${2:-}"; shift 2 ;;
    --project-dir) PROJECT_DIR="${2:-}"; shift 2 ;;
    --marketplace-source) MARKETPLACE_SOURCE="${2:-}"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --uninstall) UNINSTALL=1; shift ;;
    --yes|-y) ASSUME_YES=1; shift ;;
    --list-agents) for a in $ALL_AGENTS; do printf '  %-12s %s\n' "$a" "$(agent_label "$a")"; done; exit 0 ;;
    -h|--help) usage ;;
    *) die "Unknown option: $1 (see --help)" ;;
  esac
done

[ -d "$PLUGIN_DIR/skills" ] && [ -d "$PLUGIN_DIR/references" ] || die "Run this script from the tezca-fastapi plugin folder."
command -v perl >/dev/null || die "perl is required (preinstalled on macOS and most Linux distros)."

# ---------- interactive questions ----------
if [ -z "$SCOPE" ]; then
  [ -t 0 ] || die "--scope is required when not running interactively."
  info "${c_bold}Where should the skills be installed?${c_off}"
  info "  1) project level - only this project (committable, shared with your team)  [default]"
  info "  2) user level    - every project on this machine, for your user"
  read -r -p "Choose [1/2]: " ans
  case "${ans:-1}" in 1|project) SCOPE=project ;; 2|user) SCOPE=user ;; *) die "Invalid choice." ;; esac
fi
[ "$SCOPE" = project ] || [ "$SCOPE" = user ] || die "--scope must be 'project' or 'user'."

if [ "$SCOPE" = project ]; then
  if [ -z "$PROJECT_DIR" ]; then
    if [ -t 0 ]; then
      read -r -p "Project directory [$(pwd)]: " PROJECT_DIR
    fi
    PROJECT_DIR="${PROJECT_DIR:-$(pwd)}"
  fi
  PROJECT_DIR="${PROJECT_DIR/#\~/$HOME}"
  [ -d "$PROJECT_DIR" ] || die "Project directory not found: $PROJECT_DIR"
  PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
  [ "$PROJECT_DIR" = "$PLUGIN_DIR" ] && die "Pick your FastAPI project, not the plugin folder itself."
fi

if [ -z "$AGENTS" ]; then
  [ -t 0 ] || die "--agents is required when not running interactively."
  info "${c_bold}Which agents?${c_off} (comma separated, or 'all')"
  for a in $ALL_AGENTS; do printf '  %-12s %s\n' "$a" "$(agent_label "$a")"; done
  read -r -p "Agents [$DEFAULT_AGENTS]: " AGENTS
  AGENTS="${AGENTS:-$DEFAULT_AGENTS}"
fi
[ "$AGENTS" = all ] && AGENTS="$DEFAULT_AGENTS"
AGENTS="${AGENTS// /}"

# Validate agents and compute the de-duplicated list of target directories.
TARGETS=""
NOTES=""
IFS=',' read -r -a AGENT_LIST <<< "$AGENTS"
for a in "${AGENT_LIST[@]}"; do
  [ -z "$a" ] && continue
  case " $ALL_AGENTS " in *" $a "*) ;; *) die "Unknown agent '$a'. Use --list-agents." ;; esac
  if [ "$a" = claude-plugin ]; then DO_CLAUDE_PLUGIN=1; continue; fi
  if [ "$a" = claude ] && [[ ",$AGENTS," == *",claude-plugin,"* ]]; then
    warn "Skipping 'claude' (plain skills): 'claude-plugin' already installs them for Claude Code."; continue
  fi
  d="$(agent_dir "$a" "$SCOPE")"
  n="$(agent_note "$a")"
  [ -n "$n" ] && NOTES="${NOTES}${n}"$'\n'
  [ -z "$d" ] && continue
  case $'\n'"$TARGETS" in *$'\n'"$d"$'\n'*) ;; *) TARGETS="${TARGETS}${d}"$'\n' ;; esac
done
[ -n "$TARGETS" ] || [ "$DO_CLAUDE_PLUGIN" = 1 ] || die "Nothing to do for the selected agents at $SCOPE level."

if [ "$DO_CLAUDE_PLUGIN" = 1 ]; then
  command -v claude >/dev/null || die "claude-plugin needs the Claude Code CLI ('claude') on your PATH."
  if [ -z "$MARKETPLACE_SOURCE" ]; then
    # Prefer the git remote (works for teammates); fall back to this local folder.
    MARKETPLACE_SOURCE="$(git -C "$PLUGIN_DIR" remote get-url origin 2>/dev/null || true)"
    MARKETPLACE_SOURCE="${MARKETPLACE_SOURCE:-$PLUGIN_DIR}"
  fi
  if [ "$SCOPE" = project ] && [ -d "$MARKETPLACE_SOURCE" ]; then
    warn "Project-level marketplace source is a local path ($MARKETPLACE_SOURCE): teammates won't have it. Push the plugin to git and pass --marketplace-source <git-url> to share it."
  fi
fi

# Claude marketplace install/uninstall through the official CLI (it edits Claude's settings itself).
claude_plugin() {
  local scope="$SCOPE" cwd="$HOME"
  [ "$SCOPE" = project ] && cwd="$PROJECT_DIR"
  if [ "$UNINSTALL" = 1 ]; then
    if (cd "$cwd" && run claude plugin uninstall "$PLUGIN_ID" --scope "$scope"); then
      ok "Claude plugin $PLUGIN_ID uninstalled ($scope)"
      info "  The marketplace entry was kept. Remove it with: claude plugin marketplace remove $MARKETPLACE_NAME"
    else
      warn "Claude plugin $PLUGIN_ID was not installed at $scope level (nothing removed)."
    fi
    return 0
  fi
  if claude plugin marketplace list 2>/dev/null | grep -q "$MARKETPLACE_NAME"; then
    (cd "$cwd" && run claude plugin marketplace update "$MARKETPLACE_NAME") \
      || warn "Could not update marketplace $MARKETPLACE_NAME; installing from the version already fetched."
  else
    (cd "$cwd" && run claude plugin marketplace add "$MARKETPLACE_SOURCE" --scope "$scope") \
      || die "claude plugin marketplace add failed for $MARKETPLACE_SOURCE"
  fi
  (cd "$cwd" && run claude plugin install "$PLUGIN_ID" --scope "$scope") || die "claude plugin install failed."
  ok "Claude plugin $PLUGIN_ID installed ($scope). Use /tezca-fastapi:start-fast-api etc."
}

SKILLS=""
for s in "$PLUGIN_DIR"/skills/*/; do
  s="$(basename "$s")"; [ -f "$PLUGIN_DIR/skills/$s/SKILL.md" ] && SKILLS="$SKILLS $s"
done

# ---------- plan ----------
info ""
info "${c_bold}$([ "$UNINSTALL" = 1 ] && echo Uninstall || echo Install) tezca-fastapi skills${c_off} ($SCOPE level)"
info "Skills : $(for s in $SKILLS; do printf '%s%s ' "$PREFIX" "$s"; done)"
info "Into   :"
[ "$DO_CLAUDE_PLUGIN" = 1 ] && info "  Claude Code plugin $PLUGIN_ID (marketplace source: $MARKETPLACE_SOURCE)"
printf '%s' "$TARGETS" | while IFS= read -r d; do [ -n "$d" ] && info "  $d"; done
[ -n "$NOTES" ] && printf '%s' "$NOTES" | while IFS= read -r n; do [ -n "$n" ] && warn "$n"; done
if [ "$ASSUME_YES" = 0 ] && [ "$DRY_RUN" = 0 ] && [ -t 0 ]; then
  read -r -p "Proceed? [y/N]: " ans
  case "$ans" in y|Y|yes) ;; *) info "Aborted."; exit 0 ;; esac
fi

# ---------- uninstall ----------
if [ "$UNINSTALL" = 1 ]; then
  [ "$DO_CLAUDE_PLUGIN" = 1 ] && claude_plugin
  printf '%s' "$TARGETS" | while IFS= read -r d; do
    [ -z "$d" ] && continue
    for s in $SKILLS; do
      dest="$d/$PREFIX$s"
      if [ -f "$dest/$MARKER" ]; then run rm -rf "$dest"; ok "$([ "$DRY_RUN" = 1 ] && echo 'would remove' || echo removed) $dest"
      elif [ -e "$dest" ]; then warn "kept $dest (not installed by this script)"
      fi
    done
  done
  exit 0
fi

# ---------- stage: build self-contained copies once ----------
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/tezca-skills.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
VERSION="$(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "$PLUGIN_DIR/.claude-plugin/plugin.json" | head -1)"
COMMIT="$(git -C "$PLUGIN_DIR" rev-parse --short HEAD 2>/dev/null || echo unknown)"

for s in $SKILLS; do
  out="$STAGE/$PREFIX$s"
  mkdir -p "$out"
  cp -R "$PLUGIN_DIR/skills/$s/." "$out/"
  cp -R "$PLUGIN_DIR/references" "$out/shared"
  # Rewrite plugin-only paths so the skill works standalone in any agent.
  PREFIX="$PREFIX" perl -0pi -e '
    my $p = $ENV{PREFIX};
    s/^name:\s*(\S+)/name: $p$1/m;
    s/ \(`\.\.\/\.\.\/references\/` from this skill.s base directory\)//g;
    s/\. This is `\.\.\/\.\.\/references\/` relative to this skill.s base directory//g;
    s/`\$\{CLAUDE_PLUGIN_ROOT\}\/references\/` is `\.\.\/\.\.\/references\/` from this skill.s base directory\./`shared\/` is inside this skill\x27s folder./g;
    s/\$\{CLAUDE_PLUGIN_ROOT\}\/references\//shared\//g;
    s/\$\{CLAUDE_PLUGIN_ROOT\}\/skills\/([a-z0-9-]+)\//..\/$p$1\//g;
    s/\$\{CLAUDE_PLUGIN_ROOT\}\/skills\//..\/ (sibling ${p}* skill folders)/g;
    s/`\/tezca-fastapi:([a-z0-9-]+)`/the `$p$1` skill/g;
    s/\/tezca-fastapi:([a-z0-9-]+)/$p$1/g;
    s/^(---\n.*?\n---\n)/$1\n> Paths such as `shared\/...`, `references\/...` and `assets\/...` are relative to this skill\x27s folder. Sibling skills are installed next to it as `${p}*`.\n/s;
  ' "$out/SKILL.md"
  if grep -q 'CLAUDE_PLUGIN_ROOT' "$out/SKILL.md"; then die "Unrewritten plugin path in $s/SKILL.md (update install-skills.sh)."; fi
  printf 'tezca-fastapi %s (%s)\nsource: %s\ninstalled: %s\n' "$VERSION" "$COMMIT" "$PLUGIN_DIR" \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$out/$MARKER"
done

# ---------- install ----------
[ "$DO_CLAUDE_PLUGIN" = 1 ] && claude_plugin
installed=0; skipped=0
while IFS= read -r d; do
  [ -z "$d" ] && continue
  run mkdir -p "$d"
  for s in $SKILLS; do
    dest="$d/$PREFIX$s"
    if [ -e "$dest" ] && [ ! -f "$dest/$MARKER" ]; then
      warn "skipped $dest (already exists and was not installed by this script)"
      skipped=$((skipped + 1)); continue
    fi
    action="installed"; [ -e "$dest" ] && action="updated"
    [ "$DRY_RUN" = 1 ] && action="would be $action:"
    # Replace atomically: copy next to the destination, then swap.
    tmp="$d/.$PREFIX$s.tmp.$$"
    run rm -rf "$tmp"
    run cp -R "$STAGE/$PREFIX$s" "$tmp"
    [ -e "$dest" ] && run rm -rf "$dest"
    run mv "$tmp" "$dest"
    ok "$action $dest"
    installed=$((installed + 1))
  done
done <<< "$TARGETS"

info ""
info "${c_bold}$([ "$DRY_RUN" = 1 ] && echo 'Dry run, nothing written:' || echo 'Done:')${c_off} $installed installed/updated, $skipped skipped."
if [ "$SCOPE" = project ]; then
  info "Commit the skills folder(s) to share them with your team, or add them to .gitignore if you'd rather not."
fi
info "Restart your agent(s) so they pick up the new skills. Re-run this script after updating the plugin."
