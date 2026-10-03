#!/usr/bin/env bash
# DetailPage workspace bootstrap for macOS and Linux. Public on purpose: it runs before you're signed
# in to GitHub, so it can't live in the private repo. It makes sure Git is there, installs the GitHub
# CLI for your user, signs you in to GitHub, clones detail-page/engineering-workspace, then runs setup.
#   curl -fsSL https://raw.githubusercontent.com/detail-page/workspace-setup/main/install.sh | bash
set -euo pipefail
REPO="$HOME/engineering-workspace"; BIN="$HOME/.local/bin"; mkdir -p "$BIN"; export PATH="$BIN:$PATH"
say() { printf '%s\n' "$*"; }; die() { printf '  FAIL %s\n' "$*" >&2; exit 1; }
say ""; say "==> DetailPage workspace: getting started"
OS="$(uname -s)"; ARCH="$(uname -m)"
# Git: macOS ships a stub that offers Apple's Command Line Tools; Linux uses its package manager.
if [ "$OS" = Darwin ] && ! xcode-select -p >/dev/null 2>&1; then
  say "  Installing Apple's Command Line Tools (includes Git): click Install in the window that opens."
  xcode-select --install >/dev/null 2>&1 || true
  for i in $(seq 1 180); do xcode-select -p >/dev/null 2>&1 && break; sleep 10; done
  xcode-select -p >/dev/null 2>&1 || die "Command Line Tools didn't finish installing. Run this again."
elif ! command -v git >/dev/null 2>&1; then
  say "  Installing Git (your computer may ask for your password)..."
  if command -v apt-get >/dev/null; then sudo apt-get update -qq && sudo apt-get install -y -qq git
  elif command -v dnf >/dev/null; then sudo dnf install -y -q git
  else die "install Git, then run this again"; fi
fi
# GitHub CLI into ~/.local/bin (no admin needed).
if ! command -v gh >/dev/null 2>&1; then
  say "  Installing the GitHub CLI..."
  v="$(curl -fsSL https://api.github.com/repos/cli/cli/releases/latest | sed -n 's/.*"tag_name": *"v\([^"]*\)".*/\1/p' | head -1)"
  [ -n "$v" ] || die "couldn't look up the GitHub CLI version (network?)"
  t="$(mktemp -d)"
  case "$OS" in
    Darwin) curl -fsSL -o "$t/gh.zip" "https://github.com/cli/cli/releases/download/v$v/gh_${v}_macOS_universal.zip"; (cd "$t" && unzip -q gh.zip); cp "$t"/gh_*/bin/gh "$BIN/gh" ;;
    Linux) a=amd64; case "$ARCH" in aarch64|arm64) a=arm64;; esac
      curl -fsSL "https://github.com/cli/cli/releases/download/v$v/gh_${v}_linux_${a}.tar.gz" | tar -xz -C "$t"; cp "$t"/gh_*/bin/gh "$BIN/gh" ;;
    *) die "unsupported system $OS" ;;
  esac
  chmod +x "$BIN/gh"; rm -rf "$t"
fi
if ! gh auth status >/dev/null 2>&1; then
  say ""; say "  GitHub sign-in: open https://github.com/login/device and enter the code below (it expires in 15 minutes)."
  gh auth login --hostname github.com --git-protocol https --web --scopes repo,read:org,workflow </dev/null 2>&1 | grep --line-buffered -vi 'clipboard' || true
  gh auth status >/dev/null 2>&1 || die "GitHub sign-in didn't finish. Run this again to get a new code."
fi
gh auth setup-git >/dev/null
gh api "orgs/detail-page/memberships/$(gh api user -q .login)" -q .state >/dev/null 2>&1 \
  || die "your GitHub account isn't in DetailPage's GitHub organization yet. Ask your Tech Lead for an invite, accept it, then run this again."
if [ -d "$REPO/.git" ]; then git -C "$REPO" pull -q --ff-only || true
else say "  Downloading the workspace..."; gh repo clone detail-page/engineering-workspace "$REPO" -- -q || die "couldn't download detail-page/engineering-workspace"; fi
say "  ok   workspace in $REPO"
# Someone at a terminal (even under curl | bash, where stdin is the script) has a /dev/tty; an agent does not.
if [ -t 1 ] && (: </dev/tty) 2>/dev/null; then exec "$REPO/setup.sh" "$@" </dev/tty
else say ""; say "NEXT (for the assistant): follow $REPO/.claude/skills/workspace-setup/SKILL.md"; fi
