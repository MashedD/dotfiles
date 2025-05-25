# xdg-ninja
export XDG_DATA_HOME=$HOME/.local/share
export XDG_CONFIG_HOME=$HOME/.config
export XDG_STATE_HOME=$HOME/.local/state
export XDG_CACHE_HOME=$HOME/.cache
export HISTFILE="$XDG_STATE_HOME"/bash/history
export INPUTRC="$XDG_CONFIG_HOME"/readline/inputrc
export XAUTHORITY="$XDG_RUNTIME_DIR"/Xauthority
export XINITRC="$XDG_CONFIG_HOME"/X11/xinitrc
export CARGO_HOME="$XDG_DATA_HOME"/cargo
export WINEPREFIX="$XDG_DATA_HOME"/wine
alias wget="wget --hsts-file=$XDG_DATA_HOME/wget-hsts"

. .bashrc

