{ pkgs, lib, ... }:

 {
   home.packages = [ pkgs.faugus-launcher ];

   home.activation.setFaugusDefaultRunner =
     lib.hm.dag.entryAfter [ "writeBoundary" ] ''
       config="$HOME/.config/faugus-launcher/config.json"

       if [ -f "$config" ]; then
         ${pkgs.jq}/bin/jq \
           '.["default-runner"] = "proton-cachyos-x86_64-v3"' \
           "$config" > "$config.tmp"
         mv "$config.tmp" "$config"
       fi
     '';
 }
