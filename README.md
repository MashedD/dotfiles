# Dotfiles

CachyOS. Windows 98 style + neon green Matrix.

![Screenshot](screenshot.png)

On screenshot:

- Hyprland
- Waybar
- Walker (+elephant)
- Firefox
- Kitty
- Midnight Commander
- Vim/Neovim
- Tmux (forgot to show on screenshot)
- Audacious

But it is outdated. Now I'm using Openbox + lxpanel.

## Deployment

This repository uses [GNU Stow](https://www.gnu.org/software/stow/) to link
the `dotfiles` package into `$HOME`. Applying or unlinking also requires
`fc-cache` to refresh the bundled fonts.

```sh
./stow.sh          # dry-run preflight (same as ./stow.sh check)
./stow.sh apply    # preflight, then create or refresh Stow-owned links
./stow.sh unlink   # preflight, then remove only Stow-owned links
```

The helper never overwrites, moves, backs up, or adopts existing files. If
`check` reports a regular file or a legacy absolute symlink, inspect it and
resolve it manually before running `apply`. This keeps deployment predictable
and prevents the repository from silently taking ownership of local changes.
