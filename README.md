# NixOS dotfiles

NixOS + KDE Plasma setup tuned for gaming, with GameBoost, an automatic performance mode for games.

## Install

On a fresh NixOS install (it keeps using `/etc/nixos/hardware-configuration.nix`):

```bash
nix-shell -p git --run "git clone https://github.com/HenrikDK2/nixos-dotfiles $HOME/nixos"
sudo NIX_CONFIG="experimental-features = nix-command flakes" nixos-rebuild boot --impure --flake $HOME/nixos
reboot
```

The new generation is used from the next reboot. The system also upgrades itself automatically once a day, never while a game is running.

## Temporary apps (nix-session)

`nix shell .` only lasts for one terminal. `nix-session` builds a flake package once and keeps its programs on PATH in every terminal until reboot, without changing the dotfiles:

```bash
nix-session add                       # build the flake in this folder
nix-session add .#myapp -L            # a specific package, extra args go to nix build
nix-session add github:owner/repo     # any flake ref
nix-session list
nix-session remove .                  # by flake ref, or by the key from list
nix-session clear
```

It lives in `$XDG_RUNTIME_DIR/nix-session` (a tmpfs), so a reboot or full logout clears it, and the next GC can remove the build. Run `add` again after changing the code to rebuild. Its programs come before installed ones on PATH.
