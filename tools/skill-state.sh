#!/usr/bin/env bash
# Shared project-skill state for install.sh and skill-lifecycle.sh. Source it;
# it defines functions only.
#
# Callers provide:
#   skill_files NAME   manifest-relative paths of NAME for this platform
#   OWNERSHIP_FILE     project ownership record (may be empty)
#   USE_COLOR          1 to colorize output
#   MIGRATIONS_FILE    file collecting migrations (empty disables recording)

list_contains() {
  case ",$2," in *",$1,"*) return 0 ;; *) return 1 ;; esac
}

fingerprint() {
  cksum "$1" | awk '{print $1 ":" $2}'
}

paint() {
  if [ "${USE_COLOR:-0}" -eq 1 ]; then printf '\033[%sm%s\033[0m' "$1" "$2"; else printf '%s' "$2"; fi
}

colorize_diff() {
  if [ "${USE_COLOR:-0}" -eq 1 ]; then
    awk '
      /^(---|\+\+\+) / { printf "\033[1m%s\033[0m\n", $0; next }
      /^@@/ { printf "\033[36m%s\033[0m\n", $0; next }
      /^-/ { printf "\033[31m%s\033[0m\n", $0; next }
      /^\+/ { printf "\033[32m%s\033[0m\n", $0; next }
      { print }
    '
  else
    cat
  fi
}

# Unified diff from the local file (---) to the release (+++).
show_diff() {
  local local_file="$1" release_file="$2" label="$3" local_description="$4" release_description="$5"
  [ -f "$local_file" ] && [ ! -L "$local_file" ] || local_file=/dev/null
  { diff -u -L "$label ($local_description)" -L "$label ($release_description)" "$local_file" "$release_file" || true; } | colorize_diff
}

# Put a comma-separated selection into the order of AVAILABLE.
canonical_skill_csv() {
  local wanted="$1" available="$2" name result=""
  local IFS=,
  for name in $available; do
    list_contains "$name" "$wanted" || continue
    result="${result:+$result,}$name"
  done
  printf '%s' "$result"
}

skills_line_value() {
  if [ -z "$1" ]; then printf 'none'; else printf '%s' "${1//,/, }"; fi
}

skills_line_present() {
  [ -f "$1" ] && grep -Eq '^[[:space:]]*- \*\*skills:\*\*' "$1"
}

# Reads the selection declared in AGENTS.md ("- **skills:** a, b" or "none").
# Without the line every available skill is selected. Sets:
#   SKILL_SELECTION          valid selected names in AVAILABLE order
#   SKILL_SELECTION_INVALID  1 when the line names unknown skills or is empty
#   SKILL_SELECTION_PROBLEM  why the line is invalid
# An invalid line must never cause skills to be removed: a typo would
# otherwise uninstall the skill it meant to name.
# shellcheck disable=SC2034
read_skill_selection() {
  local agents="$1" available="$2" raw token kept="" unknown=""
  SKILL_SELECTION=""
  SKILL_SELECTION_INVALID=0
  SKILL_SELECTION_PROBLEM=""
  if ! skills_line_present "$agents"; then
    SKILL_SELECTION="$available"
    return 0
  fi
  raw="$(sed -n 's/^[[:space:]]*- \*\*skills:\*\*//p' "$agents" | head -1 | tr -d '[:space:]')"
  if [ -z "$raw" ]; then
    SKILL_SELECTION_INVALID=1
    SKILL_SELECTION_PROBLEM="the skills line has no value; write skill names or none"
    printf ' ! AGENTS.md has an empty skills line; no skills are removed until it lists skill names or none\n' >&2
    return 0
  fi
  [ "$raw" != none ] || return 0
  local tokens=()
  IFS=',' read -r -a tokens <<< "$raw"
  for token in "${tokens[@]}"; do
    [ -n "$token" ] || continue
    if list_contains "$token" "$available"; then
      kept="${kept:+$kept,}$token"
    else
      unknown="${unknown:+$unknown, }$token"
      printf " ! AGENTS.md selects skill '%s', which this release does not provide; ignoring it\n" "$token" >&2
    fi
  done
  if [ -n "$unknown" ]; then
    SKILL_SELECTION_INVALID=1
    SKILL_SELECTION_PROBLEM="unknown skills: $unknown"
  fi
  SKILL_SELECTION="$(canonical_skill_csv "$kept" "$available")"
}

# Writes AGENTS.md content with the skills line set, or removed when every
# skill is selected so default projects keep the unchanged template. Returns 3
# when there is no place to put the line. CRLF files keep CRLF line endings.
render_agents_selection() {
  local source="$1" destination="$2" selection="$3" available="$4" mode=set line
  if [ "$selection" = "$available" ]; then mode=remove; fi
  line="- **skills:** $(skills_line_value "$selection")"
  awk -v mode="$mode" -v line="$line" '
    { lines[NR] = $0 }
    END {
      eol = (NR > 0 && lines[1] ~ /\r$/) ? "\r" : ""
      for (i = 1; i <= NR; i++) if (lines[i] ~ /^[[:space:]]*- \*\*skills:\*\*/) { existing = i; break }
      if (!existing && mode == "set") {
        for (i = 1; i <= NR; i++) {
          if (lines[i] ~ /^##[[:space:]]+Repository identity[[:space:]]*\r?$/) { in_identity = 1; continue }
          if (in_identity && lines[i] ~ /^## /) break
          if (in_identity && lines[i] ~ /^- \*\*[^*]+:\*\*/) anchor = i
        }
        if (!anchor) for (i = 1; i <= NR; i++) if (lines[i] ~ /<!-- template: AGENTS /) { anchor = i; break }
        if (!anchor) exit 3
      }
      for (i = 1; i <= NR; i++) {
        if (i == existing) { if (mode == "set") print line eol; continue }
        print lines[i]
        if (i == anchor) print line eol
      }
    }
  ' "$source" > "$destination"
}

recorded_file_proof() {
  [ -n "${OWNERSHIP_FILE:-}" ] && [ -f "$OWNERSHIP_FILE" ] || return 0
  awk -F '\t' -v value="$1" '$1 == value && $2 == "file" {print $3; exit}' "$OWNERSHIP_FILE"
}

# State of one manifest file in a skill root:
#   new       missing locally
#   current   identical to the release
#   update    unchanged since the toolkit installed it; the release differs
#   local     installed by the toolkit, then edited
#   unmanaged exists but was not installed by the toolkit
file_state() {
  local destination="$1" source="$2" proof
  if [ ! -e "$destination" ] && [ ! -L "$destination" ]; then printf 'new'; return; fi
  proof="$(recorded_file_proof "$destination")"
  if [ -L "$destination" ] || [ ! -f "$destination" ]; then
    if [ -n "$proof" ]; then printf 'local'; else printf 'unmanaged'; fi
    return
  fi
  if cmp -s "$source" "$destination"; then printf 'current'; return; fi
  if [ -z "$proof" ]; then printf 'unmanaged'
  elif [ "$(fingerprint "$destination")" = "$proof" ]; then printf 'update'
  else printf 'local'; fi
}

state_rank() {
  case "$1" in not-installed) printf 0 ;; current) printf 1 ;; update) printf 2 ;; local) printf 3 ;; unmanaged) printf 4 ;; esac
}

# A skill directory replaced by a symbolic link or a file is a local change.
# Nothing is ever written through it.
skill_dir_replaced() {
  local directory="$1/$2"
  [ -L "$directory" ] || { [ -e "$directory" ] && [ ! -d "$directory" ]; }
}

# True when an ownership record lies below a project skill directory that a
# link or file replaced. Such records are left alone: resolving them would
# follow the link, and nothing below it is ever written or removed.
skill_record_under_replaced_dir() {
  local path="$1" rest
  case "$path" in /*|../*|*/../*) return 1 ;; esac
  case "$path" in */skills/*/*) ;; *) return 1 ;; esac
  rest="${path##*/skills/}"
  case "$rest" in */*) ;; *) return 1 ;; esac
  skill_dir_replaced "${path%/skills/*}/skills" "${rest%%/*}"
}

# Aggregated state of skill NAME in ROOT, including owned files the release no
# longer declares: not-installed | current | update | local | unmanaged.
skill_root_state() {
  local root="$1" name="$2" source_dir="$3" relative state worst=current existing=0 path proof files
  if [ ! -e "$root/$name" ] && [ ! -L "$root/$name" ]; then printf 'not-installed'; return; fi
  if skill_dir_replaced "$root" "$name"; then printf 'local'; return; fi
  files="$(skill_files "$name")"
  while IFS= read -r relative; do
    [ -n "$relative" ] || continue
    state="$(file_state "$root/$name/$relative" "$source_dir/$name/$relative")"
    if [ "$state" = new ]; then state=update; else existing=1; fi
    [ "$(state_rank "$state")" -le "$(state_rank "$worst")" ] || worst="$state"
  done <<< "$files"
  if [ -n "${OWNERSHIP_FILE:-}" ] && [ -f "$OWNERSHIP_FILE" ]; then
    while IFS=$'\t' read -r path proof; do
      [ -n "$path" ] || continue
      printf '%s\n' "$files" | grep -Fqx -- "${path#"$root/$name/"}" && continue
      [ -e "$path" ] || continue
      existing=1
      if [ -f "$path" ] && [ ! -L "$path" ] && [ "$(fingerprint "$path")" = "$proof" ]; then state=update; else state=local; fi
      [ "$(state_rank "$state")" -le "$(state_rank "$worst")" ] || worst="$state"
    done < <(awk -F '\t' -v prefix="$root/$name/" '$2 == "file" && index($1, prefix) == 1 {print $1 "\t" $3}' "$OWNERSHIP_FILE")
  fi
  if [ "$existing" -eq 0 ] && [ "$worst" = update ]; then
    # The directory exists but holds none of the skill's files.
    if [ -n "$(find "$root/$name" -mindepth 1 -print -quit 2>/dev/null)" ]; then printf 'unmanaged'; else printf 'not-installed'; fi
    return
  fi
  printf '%s' "$worst"
}

# Removes directories of skill NAME in ROOT that became empty.
remove_empty_skill_dirs() {
  local root="$1" name="$2" relative directory
  skill_dir_replaced "$root" "$name" && return 0
  while IFS= read -r relative; do
    [ -n "$relative" ] || continue
    directory="$(dirname "$root/$name/$relative")"
    while [ "$directory" != "$root" ] && [ "$directory" != "$root/$name/." ]; do
      rmdir "$directory" 2>/dev/null || break
      directory="$(dirname "$directory")"
    done
  done < <(skill_files "$name")
  return 0
}

record_migration() {
  [ -n "${MIGRATIONS_FILE:-}" ] || return 0
  printf '%s\t%s\t%s\n' "$1" "$2" "$3" >> "$MIGRATIONS_FILE"
}

# Prints the "Migration required" summary. Returns 2 when migration is
# unresolved (kept local changes or an invalid selection), otherwise 0.
print_migration_summary() {
  local file="${MIGRATIONS_FILE:-}" kept replaced removal invalid kind path detail
  [ -n "$file" ] && [ -s "$file" ] || return 0
  kept="$(awk -F '\t' '$1 == "kept" {n++} END {print n + 0}' "$file")"
  replaced="$(awk -F '\t' '$1 == "replaced" {n++} END {print n + 0}' "$file")"
  removal="$(awk -F '\t' '$1 == "kept-removal" {n++} END {print n + 0}' "$file")"
  invalid="$(awk -F '\t' '$1 == "invalid-selection" {n++} END {print n + 0}' "$file")"
  printf '\n%s\n' "$(paint '1;31' 'Migration required')"
  if [ "$invalid" -gt 0 ]; then
    printf '  The skills line in AGENTS.md is invalid; no skills were removed:\n'
    while IFS=$'\t' read -r kind path detail; do
      if [ "$kind" = invalid-selection ]; then printf '    ! %s  (%s)\n' "$path" "$detail"; fi
    done < "$file"
  fi
  if [ "$kept" -gt 0 ]; then
    printf '  Kept with local changes, not updated (%s):\n' "$kept"
    while IFS=$'\t' read -r kind path detail; do
      if [ "$kind" = kept ]; then printf '    ! %s  (release: %s)\n' "$path" "$detail"; fi
    done < "$file"
  fi
  if [ "$removal" -gt 0 ]; then
    printf '  Kept although no longer installed, because they have local changes (%s):\n' "$removal"
    while IFS=$'\t' read -r kind path detail; do
      if [ "$kind" = kept-removal ]; then printf '    ! %s  (%s)\n' "$path" "$detail"; fi
    done < "$file"
  fi
  if [ "$replaced" -gt 0 ]; then
    printf '  Replaced by the release; your previous version was saved (%s):\n' "$replaced"
    while IFS=$'\t' read -r kind path detail; do
      if [ "$kind" = replaced ]; then printf '    ! %s  -> %s\n' "$path" "$detail"; fi
    done < "$file"
  fi
  printf '  Next steps:\n'
  if [ "$invalid" -gt 0 ]; then
    printf '    - Fix the "- **skills:**" line in AGENTS.md: list skill names, or write none.\n'
    printf '      Then rerun to apply the selection.\n'
  fi
  if [ "$kept" -gt 0 ]; then
    printf "    - Review the diffs above: '-' lines are your version, '+' lines are the release.\n"
    printf '      Move your customizations out of toolkit-managed files (for example into a\n'
    printf '      project-specific skill), then rerun with --force to take the release.\n'
    printf '      --force saves your version as <file>.bak.<timestamp> before replacing it.\n'
  fi
  if [ "$removal" -gt 0 ]; then
    printf '    - Files kept after their skill was removed stay listed here until you delete them.\n'
    printf '      Copy anything you still need into your own files, then delete them.\n'
  fi
  if [ "$replaced" -gt 0 ]; then
    printf '    - Re-apply any customizations you still need from the saved .bak files.\n'
  fi
  if [ "$kept" -gt 0 ] || [ "$removal" -gt 0 ] || [ "$invalid" -gt 0 ]; then return 2; fi
  return 0
}
