{ pkgs, lib, ... }:

 {
   home.packages = [ pkgs.faugus-launcher ];

   home.activation.setFaugusDefaultRunner =
     lib.hm.dag.entryAfter [ "writeBoundary" ] ''
       config="$HOME/.config/faugus-launcher/config.json"

       if [ -f "$config" ]; then
         # Guarded: activation runs under `set -e`, so a bare failing jq
         # (malformed config) would abort the whole home-manager activation.
         if ${pkgs.jq}/bin/jq \
           '.["default-runner"] = "proton-cachyos-x86_64-v3"' \
           "$config" > "$config.tmp"; then
           mv "$config.tmp" "$config"
         else
           rm -f "$config.tmp"
           echo "faugus: $config is not valid JSON; left unchanged." >&2
         fi
       fi
     '';
 }
