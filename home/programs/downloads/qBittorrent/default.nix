{ pkgs, lib, ... }:

{
  home.packages = [
    pkgs.qbittorrent
  ];

  home.activation.qbittorrentFiles =
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      # Copy a directory's contents into a destination without overwriting
      # existing files, and without inheriting read-only store permissions.
      seedDir() {
        src="$1"
        dst="$2"

        [ -d "$dst" ] || $DRY_RUN_CMD ${pkgs.coreutils}/bin/mkdir -p "$dst"
        # `|| true`: cp -n may return non-zero when it skips existing files.
        $DRY_RUN_CMD ${pkgs.coreutils}/bin/cp -rn \
          --no-preserve=mode,ownership \
          -- "$src/." "$dst/" || true

        # Fix permissions only on what was seeded. A chmod -R of all of $dst
        # would walk qBittorrent's own data (torrent resume files, logs, RSS)
        # on every activation and bump each file's ctime, which makes
        # ctime-based backup tools re-read them.
        # Symlinks are skipped, as chmod -R skips them while recursing.
        # One chmod covers all of them.
        targets=()
        for entry in "$src"/* "$src"/.[!.]* "$src"/..?*; do
          target="$dst/''${entry##*/}"
          [ -e "$entry" ] && [ -e "$target" ] && [ ! -L "$target" ] || continue
          targets+=("$target")
        done
        if [ ''${#targets[@]} -gt 0 ]; then
          $DRY_RUN_CMD ${pkgs.coreutils}/bin/chmod -R u+rwX -- "''${targets[@]}"
        fi
      }

      seedDir "${./files/.config/qBittorrent}"      "$HOME/.config/qBittorrent"
      seedDir "${./files/.local/share/qBittorrent}" "$HOME/.local/share/qBittorrent"
    '';
}
