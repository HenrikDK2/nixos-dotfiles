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
