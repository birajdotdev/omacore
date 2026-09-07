#!/usr/bin/env bash
# Setup script for the Omacore Omarchy plugin.
#
# Automates everything from a cold start:
#   1. Install the OpenSCQ30 CLI (latest official release) if not found
#   2. Detect your Soundcore earbuds over Bluetooth
#   3. Register them with OpenSCQ30 (model auto-detected)
#   4. Install + enable the plugin
#   5. Point it at your earbuds, restart the shell
#
# Idempotent: safe to re-run. Pass --yes to skip prompts (picks the
# first/only Soundcore device found).

set -euo pipefail

PLUGIN_URL="https://github.com/birajdotdev/omacore.git"
PLUGIN_GH="birajdotdev/omacore"
OPENSCQ30_GH="Oppzippy/OpenSCQ30"
PLUGIN_ID="io.github.birajdotdev.omacore"
BIN_DIR="$HOME/.local/opt/openscq30"
BIN_LINK="$HOME/.local/bin/openscq30"
ASSUME_YES=0

usage() {
  cat <<'EOF'
Usage: setup.sh [--yes]

Installs and configures the Omacore plugin for Omarchy.

Options:
  --yes   Skip prompts; auto-detect and use the first Soundcore device found.
EOF
}

for arg in "$@"; do
  case "$arg" in
    --yes) ASSUME_YES=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; usage; exit 1 ;;
  esac
done

say()  { printf '\033[1;32m==>\033[0m %s\n' "$1"; }
info() { printf '\033[1;34m i\033[0m %s\n' "$1"; }
warn() { printf '\033[1;33m W\033[0m %s\n' "$1"; }
die()  { printf '\033[1;31mERROR\033[0m %s\n' "$1" >&2; exit 1; }

prompt_yesno() { # $1 = question; default yes
  local answer
  [[ "$ASSUME_YES" == 1 ]] && return 0
  printf '%s [Y/n] ' "$1"
  read -r answer
  [[ -z "$answer" || "$answer" =~ ^[YyOo] ]] || exit 1
}

command_exists() { command -v "$1" >/dev/null 2>&1; }

has_gh() { command_exists gh; }
latest_release() { # $1 = github repo; echos latest tag (no gh auth needed)
  local repo="$1"
  if has_gh; then
    gh release view --repo "$repo" --json tagName --jq .tagName
  else
    curl -fsSL "https://api.github.com/repos/$repo/releases/latest" \
      | grep -o '"tag_name":[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"\(.*\)"/\1/'
  fi
}

download_asset() { # $1 = github repo $2=tag $3=asset $4=dest-dir
  local repo="$1" tag="$2" asset="$3" dir="${4%/}"
  if has_gh; then
    gh release download "$tag" --repo "$repo" --pattern "$asset" --dir "$dir"
  else
    curl -fsSL -o "$dir/$asset" \
      "https://github.com/$repo/releases/download/$tag/$asset"
  fi
}

install_openscq30() {
  if command_exists openscq30; then
    info "openscq30 found: $(openscq30 --version 2>/dev/null | head -1)"
    if ! openscq30 list-models 2>/dev/null | grep -q "SoundcoreD1202"; then
      warn "Installed openscq30 is too old to know R60i NC / P31i (need >= 2.10.0)."
      prompt_yesno "Install the latest official release alongside it?"
      # fall through to install; keep existing binary as-is
    else
      return 0
    fi
  fi

  say "Installing OpenSCQ30 CLI"
  command -v curl >/dev/null 2>&1 || die "curl is required to download OpenSCQ30"
  local tag
  tag="$(latest_release "$OPENSCQ30_GH")"
  [[ -n "$tag" ]] || die "Could not determine the latest OpenSCQ30 release"
  info "Latest release: $tag"

  local arch
  case "$(uname -m)" in
    x86_64)  arch="x86_64" ;;
    aarch64|arm64) arch="arm64" ;;
    *) die "Unsupported architecture: $(uname -m) (OpenSCQ30 ships amd64/arm64 linux builds)" ;;
  esac
  local asset="openscq30-cli-linux-$arch"

  mkdir -p "$BIN_DIR" "$HOME/.local/bin"
  download_asset "$OPENSCQ30_GH" "$tag" "$asset" "$BIN_DIR"
  chmod +x "$BIN_DIR/$asset"
  ln -sf "$BIN_DIR/$asset" "$BIN_LINK"
  info "Installed to $BIN_LINK -> $BIN_DIR/$asset"
  command_exists openscq30 || PATH="$HOME/.local/bin:$PATH"
}

detect_devices() { # fills DEVICES array with "mac\tname" lines for soundcore buds
  DEVICES=()
  if ! command_exists bluetoothctl; then
    warn "bluetoothctl not found; you'll need to enter the MAC address manually."
    return
  fi
  local line mac name
  while IFS= read -r line; do
    mac="$(echo "$line" | awk '{print $2}')"
    name="$(echo "$line" | cut -d' ' -f3- )"
    if echo "$name" | grep -qi "soundcore\|sound core"; then
      DEVICES+=("$mac	$name")
    fi
  done < <(bluetoothctl devices 2>/dev/null)
}

match_model() { # $1 = device name; echoes best model id, or empty
  local name="$1" best="" bestscore=0 score
  local id model_name
  while IFS= read -r line; do
    id="$(echo "$line" | awk '{print $1}')"
    model_name="$(echo "$line" | awk '{$1=""; print substr($0,2)}')"
    score=0
    # Exact model-name match scores highest
    if echo "$model_name" | grep -qi "$name"; then score=3
    # Otherwise score by word overlap
    else
      for word in $name; do
        echo "$model_name" | grep -qi "$word" && score=$((score+1))
      done
    fi
    if (( score > bestscore )); then bestscore=$score; best="$id"; fi
  done < <(openscq30 list-models 2>/dev/null)
  (( bestscore > 0 )) && echo "$best"
}

register_device() { # $1 = mac $2 = model
  if openscq30 paired-devices list 2>/dev/null | grep -iq "$1"; then
    info "Device $1 already registered with OpenSCQ30"
  else
    say "Registering $1 with OpenSCQ30"
    openscq30 paired-devices add -a "$1" -m "$2"
  fi
}

install_plugin() {
  if omarchy plugin list 2>/dev/null | grep -q "$PLUGIN_ID"; then
    info "Plugin already installed"
  else
    say "Installing and enabling Omacore plugin"
    omarchy plugin add "$PLUGIN_URL" --enable --yes
  fi
}

set_config() {
  say "Pointing plugin at $1"
  omarchy bar set "$PLUGIN_ID" macAddress "$1" >/dev/null
  # If openscq30 isn't natively on PATH, point the plugin at our install so it
  # works regardless of the login shell's PATH state.
  if ! command_exists openscq30 && [[ -L "$BIN_LINK" ]]; then
    omarchy bar set "$PLUGIN_ID" ctlPath "$BIN_LINK" >/dev/null
  fi
}

###### main ######
say "Omacore setup"
install_openscq30

say "Looking for Soundcore earbuds"
detect_devices
local_mac=""
if (( ${#DEVICES[@]} > 0 )); then
  if (( ASSUME_YES == 1 || ${#DEVICES[@]} == 1 )); then
    local_mac="$(echo "${DEVICES[0]}" | cut -f1)"
    name="$(echo "${DEVICES[0]}" | cut -f2)"
    info "Using $local_mac ($name)"
  else
    info "Found multiple Soundcore devices:"
    local i=1
    for dev in "${DEVICES[@]}"; do
      printf '  [%d] %s\n' "$i" "$(echo "$dev" | tr '\t' ' ')"
      i=$((i+1))
    done
    printf 'Choose a device [1-%d]: ' "${#DEVICES[@]}"
    read -r choice
    choice=$(( ${choice:-1} - 1 ))
    (( choice >= 0 && choice < ${#DEVICES[@]} )) || die "Invalid choice"
    local_mac="$(echo "${DEVICES[$choice]}" | cut -f1)"
    name="$(echo "${DEVICES[$choice]}" | cut -f2)"
  fi
else
  info "No Soundcore devices found over Bluetooth."
  printf 'Enter the earbuds MAC address (e.g. AA:BB:CC:DD:EE:FF): '
  read -r local_mac
fi
[[ -n "$local_mac" ]] || die "No MAC address to configure"

# Auto-detect model id from the device name if we can
if command_exists openscq30; then
  model="$(match_model "$name" 2>/dev/null || true)"
  [[ -n "$model" ]] && info "Detected model id: $model"
fi
model="${model:-SoundcoreD1202C}"
info "Registering with model id: $model"

register_device "$local_mac" "$model"
install_plugin
set_config "$local_mac"

say "Verifying the plugin can reach your earbuds"
if command_exists openscq30; then
  if timeout 20 openscq30 device -a "$local_mac" list-settings --json >/dev/null 2>&1; then
    info "Connection OK"
  else
    warn "Could not reach the earbuds right now (are they in range/awake?)."
    warn "The widget will appear in the bar once they're reachable."
  fi
fi

say "Restarting the Omarchy shell"
omarchy restart shell || true

say "Done! The Omacore widget is now in the right side of your bar."
echo
echo "  Click the icon to see battery + ANC settings."
echo "  Or edit settings later: omarchy bar set $PLUGIN_ID <key> <value>"