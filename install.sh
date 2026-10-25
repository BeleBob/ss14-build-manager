#!/usr/bin/env bash
# Installs the ss14 build manager as a command under a name you choose.
#   curl -fsSL https://raw.githubusercontent.com/BeleBob/ss14-build-manager/main/install.sh | bash
set -euo pipefail

URL="${SS14_SCRIPT_URL:-https://raw.githubusercontent.com/BeleBob/ss14-build-manager/main/ss14.sh}"
BIN_DIR="${SS14_BIN_DIR:-$HOME/.local/bin}"

# Answers come from the terminal, because the script itself arrives on stdin when piped.
ask() {
    local answer
    printf '%s [%s]: ' "$1" "$2" > /dev/tty
    IFS= read -r answer < /dev/tty || exit 1
    echo "${answer:-$2}"
}

command -v curl >/dev/null || { echo "curl is required" >&2; exit 1; }

name="$(ask 'Command name' ss14)"
lower="$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')"
if [ "$lower" != "$name" ]; then
    echo "Command names are lowercase: using '$lower'"
    name="$lower"
fi
[[ "$name" =~ ^[a-z][a-z0-9_-]*$ ]] || { echo "Bad name: use lowercase letters, digits, '-' or '_', starting with a letter" >&2; exit 1; }

target="$BIN_DIR/$name"
if [ -e "$target" ]; then
    [[ "$(ask "$target exists. Replace it? (y/n)" n)" =~ ^[yY]$ ]] || { echo "Cancelled" >&2; exit 1; }
fi

mkdir -p "$BIN_DIR"
tmp="$(mktemp "$BIN_DIR/.ss14.XXXXXX")"
trap 'rm -f "$tmp"' EXIT
curl -fsSL -o "$tmp" "$URL"
chmod 755 "$tmp"
mv -f "$tmp" "$target"
trap - EXIT

next="$name"
case ":$PATH:" in
    *":$BIN_DIR:"*)
        ;;
    *)
        # Write the PATH line with $HOME, so the rc file stays valid on any machine.
        shown_dir="${BIN_DIR/#$HOME/\$HOME}"
        line="export PATH=\"$shown_dir:\$PATH\""
        rc="$HOME/.bashrc"
        [ "$(basename "${SHELL:-}")" = zsh ] && rc="$HOME/.zshrc"
        echo
        echo "$BIN_DIR is not in PATH, so '$name' will not be found in a new terminal."
        if [[ "$(ask "Add it to $rc? (y/n)" y)" =~ ^[yY]$ ]]; then
            grep -qsF "$line" "$rc" || printf '\n# ss14\n%s\n' "$line" >> "$rc"
            echo "Added to $rc. Open a new terminal (or run: source $rc)."
        else
            echo "Add this line to your shell config yourself: $line"
        fi
        next="$target"
        ;;
esac

echo
echo "Installed: $name -> $target"
echo "Next: $next install   (choose a build; no server is installed here)"
