#!/bin/bash

# MacOS Hostname / Domain Blocker
# Blocks exact hostnames by writing a managed section into the selected macOS hosts file.
# Hosts cannot block URL paths/endpoints; URLs are reduced to their hostname.

APP_NAME="MacOS Hostname / Domain Blocker"
BEGIN_MARKER="# >>> RECOVERY_DOMAIN_BLOCKER BEGIN"
END_MARKER="# <<< RECOVERY_DOMAIN_BLOCKER END"

# Preload your domains/endpoints here.
# URLs are allowed, but only their hostname will be used.

DEFAULT_ENTRIES=(
  "block.me.api.somesubdomain.domain.lol"
)

ADD_IPV6="yes"
TARGET_HOSTS=""
BLOCKLIST=()

# ---------- UI ----------

if [ -t 1 ]; then
  BOLD="$(printf '\033[1m')"
  DIM="$(printf '\033[2m')"
  RED="$(printf '\033[31m')"
  GREEN="$(printf '\033[32m')"
  YELLOW="$(printf '\033[33m')"
  BLUE="$(printf '\033[34m')"
  CYAN="$(printf '\033[36m')"
  RESET="$(printf '\033[0m')"
else
  BOLD=""
  DIM=""
  RED=""
  GREEN=""
  YELLOW=""
  BLUE=""
  CYAN=""
  RESET=""
fi

hr() {
  printf '%s\n' "------------------------------------------------------------"
}

header() {
  clear 2>/dev/null || true
  printf '%s%s%s\n' "$BOLD" "$APP_NAME" "$RESET"
  hr
  if [ -n "$TARGET_HOSTS" ]; then
    printf '%sTarget hosts file:%s %s\n' "$CYAN" "$RESET" "$TARGET_HOSTS"
  else
    printf '%sTarget hosts file:%s not selected\n' "$CYAN" "$RESET"
  fi
  printf '%sIPv6 block lines:%s %s\n' "$CYAN" "$RESET" "$ADD_IPV6"
  printf '%sCurrent blocklist:%s %s item(s)\n' "$CYAN" "$RESET" "${#BLOCKLIST[@]}"
  hr
}

info() {
  printf '%s[info]%s %s\n' "$BLUE" "$RESET" "$*"
}

ok() {
  printf '%s[ok]%s %s\n' "$GREEN" "$RESET" "$*"
}

warn() {
  printf '%s[warn]%s %s\n' "$YELLOW" "$RESET" "$*" >&2
}

fail() {
  printf '%s[error]%s %s\n' "$RED" "$RESET" "$*" >&2
}

pause() {
  printf '\nPress Return to continue...'
  read -r _
}

confirm() {
  local prompt="$1"
  local answer
  printf '%s [y/N]: ' "$prompt"
  read -r answer
  case "$answer" in
    y|Y|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

# ---------- Helpers ----------

trim() {
  printf '%s' "$1" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

is_duplicate_path() {
  local candidate="$1"
  local existing
  for existing in "${HOST_CANDIDATES[@]:-}"; do
    [ "$existing" = "$candidate" ] && return 0
  done
  return 1
}

add_host_candidate() {
  local path="$1"

  [ -z "$path" ] && return 0
  is_duplicate_path "$path" && return 0

  HOST_CANDIDATES+=("$path")
}

normalize_entry() {
  local raw="$1"
  local cleaned host

  cleaned="$(trim "$raw")"

  # Remove inline comments unless the line looks like a URL with a fragment.
  case "$cleaned" in
    http://*|https://*) ;;
    *) cleaned="$(printf '%s' "$cleaned" | sed 's/[[:space:]]*#.*$//')" ;;
  esac

  cleaned="$(trim "$cleaned")"
  [ -z "$cleaned" ] && return 1

  # If someone pasted a hosts-file row, keep only the hostname field.
  # Example: "0.0.0.0 example.com" -> "example.com"
  set -- $cleaned
  if [ "$#" -ge 2 ]; then
    case "$1" in
      0.0.0.0|127.0.0.1|::|::1) cleaned="$2" ;;
    esac
  fi

  host="$cleaned"

  # Reduce URL to hostname.
  if printf '%s' "$host" | grep -q '://'; then
    warn "URL detected; hosts can only block the hostname, not the path: $host"
    host="${host#*://}"
  fi

  # Remove userinfo, path, query, fragment, and port.
  host="${host##*@}"
  host="${host%%/*}"
  host="${host%%\?*}"
  host="${host%%#*}"
  host="${host%%:*}"
  host="${host%.}"

  # Lowercase.
  host="$(printf '%s' "$host" | tr '[:upper:]' '[:lower:]')"

  if printf '%s' "$host" | grep -q '^\*\.'; then
    warn "Wildcard detected: $host"
    warn "The hosts file does not support wildcard domains. Only adding the apex domain."
    host="${host#*.}"
  fi

  if [ -z "$host" ]; then
    return 1
  fi

  if ! printf '%s' "$host" | grep -Eq '^[a-z0-9][a-z0-9.-]*[a-z0-9]$|^[a-z0-9]$'; then
    warn "Skipping invalid hostname: $raw"
    return 1
  fi

  if printf '%s' "$host" | grep -q '\.\.'; then
    warn "Skipping invalid hostname with consecutive dots: $raw"
    return 1
  fi

  printf '%s\n' "$host"
}

domain_in_blocklist() {
  local domain="$1"
  local existing
  for existing in "${BLOCKLIST[@]}"; do
    [ "$existing" = "$domain" ] && return 0
  done
  return 1
}

add_entry_to_blocklist() {
  local raw="$1"
  local domain

  domain="$(normalize_entry "$raw")" || return 0

  if domain_in_blocklist "$domain"; then
    warn "Already in list: $domain"
    return 0
  fi

  BLOCKLIST+=("$domain")
  ok "Added: $domain"
}

load_defaults() {
  local item
  for item in "${DEFAULT_ENTRIES[@]}"; do
    add_entry_to_blocklist "$item"
  done
}

show_blocklist() {
  local i
  if [ "${#BLOCKLIST[@]}" -eq 0 ]; then
    warn "Blocklist is empty."
    return 0
  fi

  i=1
  for item in "${BLOCKLIST[@]}"; do
    printf '%3d) %s\n' "$i" "$item"
    i=$((i + 1))
  done
}

# ---------- Target discovery ----------

discover_hosts_candidates() {
  HOST_CANDIDATES=()

  local vol

  # Common Recovery mount locations.
  for vol in /Volumes/*; do
    [ -d "$vol" ] || continue

    case "$(basename "$vol")" in
      "macOS Base System"|"OS X Base System"|"Recovery"|"Preboot"|"VM"|"Update")
        continue
        ;;
    esac

    if [ -d "$vol/private/etc" ]; then
      add_host_candidate "$vol/private/etc/hosts"
    fi

    if [ -d "$vol/etc" ]; then
      add_host_candidate "$vol/etc/hosts"
    fi
  done

  # Normal boot fallback, useful if you test outside Recovery.
  if [ -d "/System/Volumes/Data/private/etc" ]; then
    add_host_candidate "/System/Volumes/Data/private/etc/hosts"
  fi

  if [ -d "/private/etc" ]; then
    add_host_candidate "/private/etc/hosts"
  fi
}

select_target_hosts() {
  local i choice custom base

  header
  discover_hosts_candidates

  if [ "${#HOST_CANDIDATES[@]}" -eq 0 ]; then
    warn "No candidate hosts file locations found."
    warn "If FileVault is enabled, unlock/mount the volume first in Disk Utility."
  else
    printf '%sAvailable candidate hosts files:%s\n\n' "$BOLD" "$RESET"

    i=1
    for path in "${HOST_CANDIDATES[@]}"; do
      printf '%3d) %s\n' "$i" "$path"
      i=$((i + 1))
    done
  fi

  printf '\n  c) Enter custom mounted system path, e.g. /Volumes/Macintosh HD - Data'
  printf '\n  q) Cancel\n\n'
  printf 'Choose target: '
  read -r choice

  case "$choice" in
    q|Q)
      return 0
      ;;
    c|C)
      printf 'Enter mounted system/data volume path: '
      read -r custom
      custom="$(trim "$custom")"
      custom="${custom%/}"

      if [ -d "$custom/private/etc" ]; then
        TARGET_HOSTS="$custom/private/etc/hosts"
      elif [ -d "$custom/etc" ]; then
        TARGET_HOSTS="$custom/etc/hosts"
      else
        warn "No private/etc or etc directory found under: $custom"
        if confirm "Create $custom/private/etc and use it"; then
          mkdir -p "$custom/private/etc" || {
            fail "Could not create $custom/private/etc"
            pause
            return 1
          }
          TARGET_HOSTS="$custom/private/etc/hosts"
        else
          return 0
        fi
      fi

      ok "Selected: $TARGET_HOSTS"
      pause
      ;;
    ''|*[!0-9]*)
      warn "Invalid choice."
      pause
      ;;
    *)
      if [ "$choice" -lt 1 ] || [ "$choice" -gt "${#HOST_CANDIDATES[@]}" ]; then
        warn "Choice out of range."
        pause
        return 1
      fi

      TARGET_HOSTS="${HOST_CANDIDATES[$((choice - 1))]}"
      ok "Selected: $TARGET_HOSTS"
      pause
      ;;
  esac
}

require_target() {
  if [ -z "$TARGET_HOSTS" ]; then
    warn "Select a target hosts file first."
    pause
    return 1
  fi
  return 0
}

prepare_hosts_file() {
  local dir

  require_target || return 1

  dir="$(dirname "$TARGET_HOSTS")"

  if [ ! -d "$dir" ]; then
    mkdir -p "$dir" || {
      fail "Failed to create directory: $dir"
      return 1
    }
  fi

  if [ ! -f "$TARGET_HOSTS" ]; then
    warn "Hosts file does not exist; creating it: $TARGET_HOSTS"
    cat > "$TARGET_HOSTS" <<'HOSTS'
##
# Host Database
#
# localhost is used to configure the loopback interface
# when the system is booting. Do not change this entry.
##
127.0.0.1       localhost
255.255.255.255 broadcasthost
::1             localhost
HOSTS
  fi

  if [ ! -w "$TARGET_HOSTS" ]; then
    fail "Hosts file is not writable: $TARGET_HOSTS"
    fail "In Recovery, unlock/mount the disk in Disk Utility, then run this script again."
    return 1
  fi

  return 0
}

backup_hosts() {
  local backup_path timestamp

  prepare_hosts_file || return 1

  timestamp="$(date +%Y%m%d-%H%M%S)"
  backup_path="${TARGET_HOSTS}.recovery-blocker-backup.${timestamp}"

  cp -p "$TARGET_HOSTS" "$backup_path" || {
    fail "Backup failed."
    return 1
  }

  ok "Backup created: $backup_path"
  return 0
}

remove_managed_block_to_file() {
  local input="$1"
  local output="$2"

  awk -v start="$BEGIN_MARKER" -v end="$END_MARKER" '
    $0 == start { inside = 1; next }
    $0 == end { inside = 0; next }
    inside != 1 { print }
  ' "$input" > "$output"
}

fix_hosts_permissions() {
  chmod 0644 "$TARGET_HOSTS" 2>/dev/null || true
  chown root:wheel "$TARGET_HOSTS" 2>/dev/null || true
}

apply_blocklist() {
  local tmp clean item now

  header

  if [ "${#BLOCKLIST[@]}" -eq 0 ]; then
    warn "Blocklist is empty. Add entries first."
    pause
    return 1
  fi

  prepare_hosts_file || {
    pause
    return 1
  }

  backup_hosts || {
    pause
    return 1
  }

  tmp="$(mktemp /tmp/hosts.clean.XXXXXX)" || {
    fail "Could not create temp file."
    pause
    return 1
  }

  clean="$(mktemp /tmp/hosts.new.XXXXXX)" || {
    rm -f "$tmp"
    fail "Could not create temp file."
    pause
    return 1
  }

  remove_managed_block_to_file "$TARGET_HOSTS" "$tmp"

  now="$(date)"

  {
    cat "$tmp"
    printf '\n%s\n' "$BEGIN_MARKER"
    printf '# Managed by %s\n' "$APP_NAME"
    printf '# Updated: %s\n' "$now"
    printf '# Note: hosts blocks hostnames only, not URL paths.\n'

    for item in "${BLOCKLIST[@]}"; do
      printf '0.0.0.0\t%s\n' "$item"
      if [ "$ADD_IPV6" = "yes" ]; then
        printf '::1\t\t%s\n' "$item"
      fi
    done

    printf '%s\n' "$END_MARKER"
  } > "$clean"

  cat "$clean" > "$TARGET_HOSTS" || {
    rm -f "$tmp" "$clean"
    fail "Failed to write hosts file."
    pause
    return 1
  }

  rm -f "$tmp" "$clean"
  fix_hosts_permissions

  ok "Applied ${#BLOCKLIST[@]} hostname(s) to:"
  printf '%s\n' "$TARGET_HOSTS"

  case "$TARGET_HOSTS" in
    /Volumes/*)
      info "Recovery target detected. Reboot into macOS for the change to take effect."
      ;;
    *)
      info "Flush DNS to apply immediately:"
      printf '  sudo dscacheutil -flushcache\n'
      printf '  sudo killall -HUP mDNSResponder\n'
      info "Browsers with Secure DNS (DoH/DoT) bypass /etc/hosts; disable it there if needed."
      ;;
  esac
  pause
}

remove_managed_block() {
  local tmp

  header
  prepare_hosts_file || {
    pause
    return 1
  }

  if ! grep -qF "$BEGIN_MARKER" "$TARGET_HOSTS"; then
    warn "No managed block found in this hosts file."
    pause
    return 0
  fi

  if ! confirm "Remove the managed block from $TARGET_HOSTS"; then
    return 0
  fi

  backup_hosts || {
    pause
    return 1
  }

  tmp="$(mktemp /tmp/hosts.unblocked.XXXXXX)" || {
    fail "Could not create temp file."
    pause
    return 1
  }

  remove_managed_block_to_file "$TARGET_HOSTS" "$tmp"

  cat "$tmp" > "$TARGET_HOSTS" || {
    rm -f "$tmp"
    fail "Failed to write hosts file."
    pause
    return 1
  }

  rm -f "$tmp"
  fix_hosts_permissions

  ok "Managed block removed."
  pause
}

view_managed_block() {
  header
  require_target || return 1

  if [ ! -f "$TARGET_HOSTS" ]; then
    warn "Hosts file does not exist yet."
    pause
    return 0
  fi

  if ! grep -qF "$BEGIN_MARKER" "$TARGET_HOSTS"; then
    warn "No managed block found."
    pause
    return 0
  fi

  awk -v start="$BEGIN_MARKER" -v end="$END_MARKER" '
    $0 == start { inside = 1 }
    inside == 1 { print }
    $0 == end { inside = 0 }
  ' "$TARGET_HOSTS"

  pause
}

restore_backup() {
  local dir pattern backups count i choice selected

  header
  require_target || return 1

  dir="$(dirname "$TARGET_HOSTS")"
  pattern="$(basename "$TARGET_HOSTS").recovery-blocker-backup."

  # shellcheck disable=SC2012
  backups=($(ls -1t "$dir"/"$pattern"* 2>/dev/null))

  count="${#backups[@]}"

  if [ "$count" -eq 0 ]; then
    warn "No backups found next to:"
    printf '%s\n' "$TARGET_HOSTS"
    pause
    return 0
  fi

  printf '%sAvailable backups:%s\n\n' "$BOLD" "$RESET"

  i=1
  for selected in "${backups[@]}"; do
    printf '%3d) %s\n' "$i" "$selected"
    i=$((i + 1))
  done

  printf '\n  q) Cancel\n\n'
  printf 'Restore which backup: '
  read -r choice

  case "$choice" in
    q|Q)
      return 0
      ;;
    ''|*[!0-9]*)
      warn "Invalid choice."
      pause
      return 1
      ;;
  esac

  if [ "$choice" -lt 1 ] || [ "$choice" -gt "$count" ]; then
    warn "Choice out of range."
    pause
    return 1
  fi

  selected="${backups[$((choice - 1))]}"

  if ! confirm "Overwrite current hosts file with this backup"; then
    return 0
  fi

  backup_hosts || {
    pause
    return 1
  }

  cat "$selected" > "$TARGET_HOSTS" || {
    fail "Restore failed."
    pause
    return 1
  }

  fix_hosts_permissions

  ok "Restored from: $selected"
  pause
}

block_apple_mdm_servers() {
  local mdm_domains=(
    "deviceenrollment.apple.com"
    "mdmenrollment.apple.com"
    "iprofiles.apple.com"
  )
  local domain

  for domain in "${mdm_domains[@]}"; do
    add_entry_to_blocklist "$domain"
  done

  ok "Added Apple MDM servers to blocklist."
  pause
}

edit_blocklist_menu() {
  local choice idx line

  while true; do
    header
    printf '%sCurrent entries:%s\n' "$BOLD" "$RESET"
    show_blocklist

    cat <<MENU

Options:
  1) Add one hostname or URL
  2) Paste multiple hostnames/URLs
  3) Remove an entry
  4) Load defaults from script
  5) Clear blocklist
  6) Toggle IPv6 lines
  7) Block Apple MDM servers
  q) Back

MENU

    printf 'Choose option: '
    read -r choice

    case "$choice" in
      1)
        printf 'Enter hostname or URL: '
        read -r line
        add_entry_to_blocklist "$line"
        pause
        ;;
      2)
        printf 'Paste entries, one per line. Enter a single "." on its own line when done.\n\n'
        while IFS= read -r line; do
          [ "$line" = "." ] && break
          add_entry_to_blocklist "$line"
        done
        pause
        ;;
      3)
        if [ "${#BLOCKLIST[@]}" -eq 0 ]; then
          warn "Blocklist is empty."
          pause
          continue
        fi

        printf 'Entry number to remove: '
        read -r idx

        if ! printf '%s' "$idx" | grep -Eq '^[0-9]+$'; then
          warn "Invalid number."
          pause
          continue
        fi

        if [ "$idx" -lt 1 ] || [ "$idx" -gt "${#BLOCKLIST[@]}" ]; then
          warn "Number out of range."
          pause
          continue
        fi

        ok "Removed: ${BLOCKLIST[$((idx - 1))]}"
        unset "BLOCKLIST[$((idx - 1))]"
        BLOCKLIST=("${BLOCKLIST[@]}")
        pause
        ;;
      4)
        load_defaults
        pause
        ;;
      5)
        if confirm "Clear all current blocklist entries"; then
          BLOCKLIST=()
          ok "Blocklist cleared."
        fi
        pause
        ;;
      6)
        if [ "$ADD_IPV6" = "yes" ]; then
          ADD_IPV6="no"
        else
          ADD_IPV6="yes"
        fi
        ok "IPv6 block lines: $ADD_IPV6"
        pause
        ;;
      q|Q)
        return 0
        ;;
      *)
        warn "Invalid option."
        pause
        ;;
    esac
  done
}

main_menu() {
  local choice

  while true; do
    header

    cat <<MENU
Options:
  1) Select target macOS hosts file
  2) Edit blocklist
  3) Apply/update managed block
  4) View managed block currently in hosts file
  5) Remove managed block from hosts file
  6) Restore hosts file from backup
  7) Block Apple MDM servers
  q) Quit

MENU

    printf 'Choose option: '
    read -r choice

    case "$choice" in
      1) select_target_hosts ;;
      2) edit_blocklist_menu ;;
      3) apply_blocklist ;;
      4) view_managed_block ;;
      5) remove_managed_block ;;
      6) restore_backup ;;
      7) block_apple_mdm_servers ;;
      q|Q)
        printf 'Done.\n'
        exit 0
        ;;
      *)
        warn "Invalid option."
        pause
        ;;
    esac
  done
}

# ---------- Startup ----------

if [ "$(id -u)" -ne 0 ]; then
  fail "Run as root. In normal macOS use: sudo $0"
  fail "In macOS Recovery Terminal you are usually already root."
  exit 1
fi

load_defaults
discover_hosts_candidates

if [ "${#HOST_CANDIDATES[@]}" -eq 1 ]; then
  TARGET_HOSTS="${HOST_CANDIDATES[0]}"
fi

main_menu
