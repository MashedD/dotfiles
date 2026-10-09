#!/bin/sh
# startx also works when XINITRC was not exported by the login shell.
exec sh "${XDG_CONFIG_HOME:-$HOME/.config}/X11/xinitrc"
