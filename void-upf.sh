#!/usr/bin/env bash
# ------------------------------------------------------------
# CONFIG – pick a colour name for orphaned / maintained packages
# ------------------------------------------------------------
ORPHAN_COLOR_NAME="brightred"      # orphaned packages
MAINTAINED_COLOR_NAME="brightgreen" # packages with a maintainer
# ------------------------------------------------------------

# ---- colour name → ANSI code map ---------------------------------
declare -A COLORS=(
    [black]="30"     [brightblack]="90"
    [red]="31"       [brightred]="91"
    [green]="32"     [brightgreen]="92"
    [yellow]="33"    [brightyellow]="93"
    [blue]="34"      [brightblue]="94"
    [magenta]="35"   [brightmagenta]="95"
    [cyan]="36"      [brightcyan]="96"
    [white]="37"     [brightwhite]="97"
)

# Resolve the names to actual escape sequences
ORPHAN_COLOR="\033[${COLORS[$ORPHAN_COLOR_NAME]}m"
MAINTAINED_COLOR="\033[${COLORS[$MAINTAINED_COLOR_NAME]}m"
COLOR_RESET="\033[0m"
# ------------------------------------------------------------

# Default flags
ORPHAN_ONLY=false
NON_ORPHAN_ONLY=false
COLOR_OUTPUT=false
SHOW_HELP=false

# ---------- parse options ----------
while getopts "omch-:" opt; do
  case $opt in
    o) ORPHAN_ONLY=true ;;
    m) NON_ORPHAN_ONLY=true ;;
    c) COLOR_OUTPUT=true ;;
    h) SHOW_HELP=true ;;
    -)
      case "${OPTARG}" in
        help) SHOW_HELP=true ;;
        *) echo "Unknown option --${OPTARG}"; exit 1 ;;
      esac
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      SHOW_HELP=true
      ;;
  esac
done

# Show help if requested
if $SHOW_HELP; then
  cat << 'EOF'

Usage: void-upf.sh [options]

Options:
  -o               Show only orphaned packages
  -m               Show only maintained packages
  -c               Enable color output (red=orphaned, green=maintained)
  -h, --help       Show this help message

EOF
  exit 0
fi

# -o and -m are mutually exclusive
if $ORPHAN_ONLY && $NON_ORPHAN_ONLY; then
  echo "Error: -o and -m cannot be used together" >&2
  exit 1
fi

# ---------- sanity checks ----------
if ! command -v xbps-query >/dev/null 2>&1; then
  echo "Error: xbps-query not found – is XBPS installed?" >&2
  exit 1
fi

# ---------- FIRST PASS: count totals (independent of filters) ----------
total_count=0
maintained_count=0
orphaned_count=0

while IFS= read -r pkgname; do
  [ -z "$pkgname" ] && continue
  (( total_count++ ))

  maintainer=$(xbps-query -p maintainer "$pkgname" 2>/dev/null)

  if [ -n "$maintainer" ]; then
    if [ "$maintainer" = "Orphaned <orphan@voidlinux.org>" ]; then
      (( orphaned_count++ ))
    else
      (( maintained_count++ ))
    fi
  fi
done < <(xbps-query -m)

# ---------- SECOND PASS: collect filtered data for display ----------
declare -a PKGS MAINTS

while IFS= read -r pkgname; do
  [ -z "$pkgname" ] && continue

  maintainer=$(xbps-query -p maintainer "$pkgname" 2>/dev/null)

  if [ -n "$maintainer" ]; then
    # Apply display filters
    if $ORPHAN_ONLY && [ "$maintainer" != "Orphaned <orphan@voidlinux.org>" ]; then
      continue
    elif $NON_ORPHAN_ONLY && [ "$maintainer" = "Orphaned <orphan@voidlinux.org>" ]; then
      continue
    fi

    PKGS+=("$pkgname")
    MAINTS+=("$maintainer")
  else
    # Only show "not found" if no filter is active
    if ! $ORPHAN_ONLY && ! $NON_ORPHAN_ONLY; then
      PKGS+=("$pkgname")
      MAINTS+=("Maintainer not found")
    fi
  fi
done < <(xbps-query -m)

# ---------- compute column width ----------
header="Package"
max_pkg_len=${#header}
for p in "${PKGS[@]}"; do
  (( ${#p} > max_pkg_len )) && max_pkg_len=${#p}
done
(( max_pkg_len += 2 ))  # padding after colon

# ---------- print header (always plain) ----------
printf "%-${max_pkg_len}s %s\n" "${header}:" "Maintainer"

# ---------- print single separator line ----------
total_width=$(( max_pkg_len + 50 ))
printf '%*s\n' "$total_width" '' | tr ' ' '-'

# ---------- helper: print one line ----------
print_line() {
  local pkg="$1"
  local maint="$2"
  local is_orphan=$( [ "$maint" = "Orphaned <orphan@voidlinux.org>" ] && echo true || echo false )

  if $COLOR_OUTPUT; then
    if $is_orphan; then
      printf "%b%-${max_pkg_len}s%b %s\n" "$ORPHAN_COLOR" "$pkg:" "$COLOR_RESET" "$maint"
    else
      printf "%b%-${max_pkg_len}s%b %s\n" "$MAINTAINED_COLOR" "$pkg:" "$COLOR_RESET" "$maint"
    fi
  else
    printf "%-${max_pkg_len}s %s\n" "$pkg:" "$maint"
  fi
}

# ---------- output filtered lines ----------
for i in "${!PKGS[@]}"; do
  print_line "${PKGS[i]}" "${MAINTS[i]}"
done

# ---------- print GLOBAL summary (always full counts) ----------
printf "\n"
printf "Summary (all manually installed packages):\n"
printf "  Total:      %d\n" "$total_count"
printf "  Maintained:%*d\n" $(( ${#total_count} + 1 )) "$maintained_count"
printf "  Orphaned:  %*d\n" $(( ${#total_count} + 1 )) "$orphaned_count"
