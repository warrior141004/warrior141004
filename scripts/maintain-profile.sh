#!/usr/bin/env bash
set -euo pipefail

USERNAME="${GITHUB_USERNAME:-warrior141004}"
PROFILE_DIR="${PROFILE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
README_PATH="$PROFILE_DIR/README.md"
AUTO_START="<!-- PROFILE-AUTO-START -->"
AUTO_END="<!-- PROFILE-AUTO-END -->"
MAX_WAIT_SECONDS="${MAX_WAIT_SECONDS:-120}"

log() {
  printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*"
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

wait_for_github() {
  local waited=0

  while (( waited <= MAX_WAIT_SECONDS )); do
    if gh api -X GET "/users/$USERNAME/repos" -f per_page=1 >/dev/null 2>&1; then
      return 0
    fi

    log "Waiting for GitHub network/authentication..."
    sleep 5
    waited=$((waited + 5))
  done

  if [[ -n "${GH_TOKEN:-}${GITHUB_TOKEN:-}" ]]; then
    die "Could not reach the GitHub API with the configured token."
  fi

  die "Could not reach GitHub or GitHub CLI is not authenticated. Run: gh auth login"
}

escape_markdown_cell() {
  local value="${1:-}"
  value="${value//$'\r'/ }"
  value="${value//$'\n'/ }"
  value="${value//|//}"
  printf '%s' "$value"
}

build_activity_section() {
  local tmp_file="$1"
  local rows_file
  rows_file="$(mktemp)"

  gh api -X GET "/users/$USERNAME/repos" \
    -f type=owner \
    -f sort=pushed \
    -f direction=desc \
    -f per_page=12 \
    --jq '.[] | select(.fork == false and .archived == false and .name != "'"$USERNAME"'") | [.name, .html_url, (.language // "Mixed"), ((.description // "No description yet.") | gsub("\\|"; "/")), (.pushed_at[0:10])] | @tsv' > "$rows_file"

  {
    printf '%s\n' "$AUTO_START"
    printf '<h2 align="center">Latest Public Work</h2>\n\n'
    printf '<p align="center"><em>Generated from live public GitHub repository data. Run <code>scripts/maintain-profile.sh</code> to refresh.</em></p>\n\n'
    printf '| Repository | Stack | Focus | Last Push |\n'
    printf '| --- | --- | --- | --- |\n'

    if [[ -s "$rows_file" ]]; then
      while IFS=$'\t' read -r name url language description pushed_at; do
        name="$(escape_markdown_cell "$name")"
        url="$(escape_markdown_cell "$url")"
        language="$(escape_markdown_cell "$language")"
        description="$(escape_markdown_cell "$description")"
        pushed_at="$(escape_markdown_cell "$pushed_at")"
        printf '| [%s](%s) | `%s` | %s | %s |\n' "$name" "$url" "$language" "$description" "$pushed_at"
      done < "$rows_file"
    else
      printf '| No public source repositories found. | `-` | Add public projects to populate this section. | - |\n'
    fi

    printf '%s\n' "$AUTO_END"
  } > "$tmp_file"

  rm -f "$rows_file"
}

replace_activity_section() {
  local section_file="$1"
  local tmp_readme
  tmp_readme="$(mktemp)"

  grep -qF "$AUTO_START" "$README_PATH" || die "README is missing $AUTO_START"
  grep -qF "$AUTO_END" "$README_PATH" || die "README is missing $AUTO_END"

  awk -v start="$AUTO_START" -v end="$AUTO_END" -v section="$section_file" '
    BEGIN {
      while ((getline line < section) > 0) {
        replacement = replacement line ORS
      }
    }
    $0 == start {
      printf "%s", replacement
      skipping = 1
      next
    }
    $0 == end {
      skipping = 0
      next
    }
    !skipping {
      print
    }
  ' "$README_PATH" > "$tmp_readme"

  mv "$tmp_readme" "$README_PATH"
}

check_profile_images() {
  local failures=0
  local url
  local code

  log "Checking README image links..."

  while IFS= read -r url; do
    code="$(curl -L -s -o /dev/null -w '%{http_code}' --max-time 20 "$url" || true)"

    if [[ "$code" =~ ^[23] ]]; then
      continue
    fi

    failures=$((failures + 1))
    log "Image warning: HTTP ${code:-000} $url"
  done < <(grep -oE 'src="https://[^"]+"' "$README_PATH" | sed 's/^src="//; s/"$//' | sort -u)

  if (( failures == 0 )); then
    log "Image check passed."
  else
    log "Image check finished with $failures warning(s). The script will continue."
  fi
}

open_profile_if_requested() {
  if [[ "${OPEN_PROFILE:-0}" != "1" ]]; then
    return 0
  fi

  log "Opening profile in browser..."

  if command -v cmd.exe >/dev/null 2>&1; then
    cmd.exe /C start "" "https://github.com/$USERNAME" >/dev/null 2>&1 || true
  elif command -v xdg-open >/dev/null 2>&1; then
    xdg-open "https://github.com/$USERNAME" >/dev/null 2>&1 || true
  fi
}

main() {
  require_command git
  require_command gh
  require_command curl
  require_command awk
  require_command sed

  cd "$PROFILE_DIR"

  log "Maintaining GitHub profile for $USERNAME"
  wait_for_github

  log "Pulling latest profile repository state..."
  git pull --ff-only

  local section_file
  section_file="$(mktemp)"
  build_activity_section "$section_file"
  replace_activity_section "$section_file"
  rm -f "$section_file"

  check_profile_images

  if git diff --quiet -- README.md; then
    log "README is already up to date. No commit needed."
  else
    log "Committing real profile data changes..."
    git add README.md
    git commit -m "Refresh profile activity"
    git push
  fi

  log "Done: https://github.com/$USERNAME"
  open_profile_if_requested
}

main "$@"
