# Body for pkgs.writeShellApplication: it adds the shebang and
# `set -euo pipefail`, so neither belongs here.

readonly GAME="FFXIPAL"
readonly DEFAULT_APP_ID=230350
readonly POL="SquareEnix/FINAL FANTASY XI"
readonly BACKUP_DIR="$HOME/FFXI_BACKUP"
readonly ARCHIVE="$HOME/FFXI_BACKUP.7z"

die() { echo "$*" >&2; exit 1; }

library_dirs() {
	local root
	for root in ~/.steam/steam ~/.local/share/Steam ~/Games \
		~/.var/app/com.valvesoftware.Steam/.local/share/Steam \
		~/snap/steam/common/.local/share/Steam \
		/mnt/* /media/"${USER:-}"/* /run/media/"${USER:-}"/*; do
		[ -d "$root" ] || continue
		echo "$root"
		# `|| true`: a missing libraryfolders.vdf must not abort the loop
		grep -Poh '"path"\s+"\K[^"]+' "$root/steamapps/libraryfolders.vdf" 2>/dev/null || true
	done | xargs -rd '\n' -n1 readlink -f | awk '!seen[$0]++'
}

# Print the first <library>/steamapps/$1 (or <library>/$1) that exists
find_in_libraries() {
	local lib sa
	while read -r lib; do
		for sa in "$lib/steamapps" "$lib"; do
			if [ -d "$sa/$1" ]; then
				echo "$sa/$1"
				return 0
			fi
		done
	done < <(library_dirs)
	return 1
}

app_id() {
	local m
	m=$(grep -l "\"installdir\"[[:space:]]*\"$GAME\"" "$1"/appmanifest_*.acf 2>/dev/null | head -n1 || true)
	m=${m##*_}
	echo "${m%.acf}"
}

# Sets FFXI_DIR, APP_ID, PREFIX_DIR
locate() {
	[ -d "${FFXI_DIR:-}" ] \
		|| FFXI_DIR=$(find_in_libraries "common/$GAME") \
		|| FFXI_DIR=$(find ~ /mnt /media /run/media -maxdepth 7 -type d -path "*/common/$GAME" -print -quit 2>/dev/null)
	[ -d "$FFXI_DIR" ] || return 1

	local steamapps=${FFXI_DIR%/common/*}
	APP_ID=$(app_id "$steamapps")
	APP_ID=${APP_ID:-$DEFAULT_APP_ID}

	local pfx="compatdata/$APP_ID/pfx"
	if [ ! -d "${PREFIX_DIR:-}" ]; then
		if [ -d "$steamapps/$pfx" ]; then
			PREFIX_DIR="$steamapps/$pfx"
		else
			PREFIX_DIR=$(find_in_libraries "$pfx" || true)
		fi
	fi
	return 0
}

# Copy the files we care about from $1 to $2, keeping relative paths
transfer() {
	mkdir -p "$2"
	(
		cd "$1" || exit 1
		for item in settings.xml Windower "$POL/USER" "$POL"/Tools*; do
			# if, not `&&`: a missing optional item must not fail the subshell
			if [ -e "$item" ]; then
				cp -rf --parents "$item" "$2/"
			fi
		done
	)
}

write_installer() {
	{
		echo '#!/bin/bash'
		declare -p GAME DEFAULT_APP_ID POL
		declare -f die library_dirs find_in_libraries app_id locate transfer
		cat <<'EOS'
cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1
locate || die "FFXI isn't installed. Install it first, or set FFXI_DIR."
echo "Installing into: $FFXI_DIR"
transfer "$PWD" "$FFXI_DIR"
echo "FFXI backup installation complete."
EOS
	} > "$BACKUP_DIR/install.sh"
	chmod +x "$BACKUP_DIR/install.sh"
}

# 7z prompts for the password itself, keeping it out of `ps` and history
create_archive() {
	echo -e "\nEnter a backup password when prompted.\n"
	7z a -p -mhe=on "$ARCHIVE" "$BACKUP_DIR" || die "Archive failed; kept $BACKUP_DIR."
	rm -rf "$BACKUP_DIR"
	echo -e "\nBackup created: $ARCHIVE"
}

main() {
	locate || die "FFXI isn't installed. Set FFXI_DIR if it's in an unusual place."
	echo "Game:   $FFXI_DIR"
	echo "Prefix: ${PREFIX_DIR:-not found}"

	rm -rf "$BACKUP_DIR" "$ARCHIVE"
	transfer "$FFXI_DIR" "$BACKUP_DIR"
	write_installer
	create_archive
}

main
