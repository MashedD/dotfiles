[[ $- != *i* ]] && return

# Set the directory we want to store zinit and plugins
ZINIT_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/zinit/zinit.git"

# xdg-ninja
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_STATE_HOME="$HOME/.local/state"
export XDG_CACHE_HOME="$HOME/.cache"
export XDG_PICTURES_DIR="$HOME/Pictures"
export HISTFILE="$XDG_STATE_HOME"/bash/history
export INPUTRC="$XDG_CONFIG_HOME"/readline/inputrc
export XAUTHORITY="$XDG_RUNTIME_DIR"/Xauthority
export XINITRC="$XDG_CONFIG_HOME"/X11/xinitrc
export CARGO_HOME="$XDG_DATA_HOME"/cargo
export WINEPREFIX="$XDG_DATA_HOME"/wine
alias wget="wget --hsts-file=$XDG_DATA_HOME/wget-hsts"

# Download zinit, if it's not there yet
if [ ! -d "$ZINIT_HOME" ]; then
  mkdir -p "$(dirname $ZINIT_HOME)"
  git clone https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME"
fi

# Source/Load zinit
source "$ZINIT_HOME/zinit.zsh"

# DOS Navigator VAX palette
typeset -gr VAX_BLACK='#000000'
typeset -gr VAX_GREEN='#00ff41'
typeset -gr VAX_DIM_GREEN='#00aa33'
typeset -gr VAX_SILVER='#c0c0c0'
typeset -gr VAX_GRAY='#666666'
typeset -gr VAX_YELLOW='#ffff00'
typeset -gr VAX_CYAN='#00ffff'
typeset -gr VAX_BLUE='#5555ff'
typeset -gr VAX_MAGENTA='#ff55ff'
typeset -gr VAX_RED='#ff3333'

# Settings for `less`
export LESS=-R
export LESS_TERMCAP_mb=$'\e[1;31m'
export LESS_TERMCAP_md=$'\e[1;33m'
export LESS_TERMCAP_me=$'\e[0m'
export LESS_TERMCAP_so=$'\e[30;47m'
export LESS_TERMCAP_se=$'\e[0m'
export LESS_TERMCAP_us=$'\e[1;36m'
export LESS_TERMCAP_ue=$'\e[0m'
export LESSOPEN="| /usr/bin/highlight -O ansi %s 2>/dev/null"

#export FZF_DEFAULT_OPTS=TODO:

# Add in zsh plugins
# NOTE: zsh-syntax-highlighting must be loaded LAST (after all other plugins)
zinit light zsh-users/zsh-completions
zinit light zsh-users/zsh-autosuggestions
zinit light Aloxaf/fzf-tab
zinit light zsh-users/zsh-syntax-highlighting
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE="fg=${VAX_GRAY}"

# Enable pattern highlighter - catches $var patterns the main highlighter misses
ZSH_HIGHLIGHT_HIGHLIGHTERS+=(pattern)
ZSH_HIGHLIGHT_PATTERNS=(
  '\$[a-zA-Z_][a-zA-Z0-9_]#' "fg=${VAX_CYAN}"
  '\$\{[a-zA-Z_][a-zA-Z0-9_]#\}' "fg=${VAX_CYAN}"
  '\$[#?!@*-]' "fg=${VAX_CYAN}"
  '\$[0-9]##' "fg=${VAX_CYAN}"
)

# VAX syntax roles: green commands, silver text, and high-contrast accents.
ZSH_HIGHLIGHT_STYLES[default]="fg=${VAX_SILVER}"
ZSH_HIGHLIGHT_STYLES[comment]="fg=${VAX_DIM_GREEN}"
ZSH_HIGHLIGHT_STYLES[command]="fg=${VAX_GREEN},bold"
ZSH_HIGHLIGHT_STYLES[function]="fg=${VAX_GREEN},bold"
ZSH_HIGHLIGHT_STYLES[builtin]="fg=${VAX_GREEN}"
ZSH_HIGHLIGHT_STYLES[hashed-command]="fg=${VAX_GREEN}"
ZSH_HIGHLIGHT_STYLES[reserved-word]="fg=${VAX_YELLOW},bold"
ZSH_HIGHLIGHT_STYLES[precommand]="fg=${VAX_CYAN}"
ZSH_HIGHLIGHT_STYLES[alias]="fg=${VAX_CYAN}"
ZSH_HIGHLIGHT_STYLES[suffix-alias]="fg=${VAX_CYAN}"
ZSH_HIGHLIGHT_STYLES[path]="fg=${VAX_SILVER}"
ZSH_HIGHLIGHT_STYLES[path_pathseparator]="fg=${VAX_GREEN}"
ZSH_HIGHLIGHT_STYLES[commandseparator]="fg=${VAX_SILVER}"
ZSH_HIGHLIGHT_STYLES[redirection]="fg=${VAX_YELLOW}"
ZSH_HIGHLIGHT_STYLES[globbing]="fg=${VAX_YELLOW}"
ZSH_HIGHLIGHT_STYLES[history-expansion]="fg=${VAX_YELLOW}"
ZSH_HIGHLIGHT_STYLES[single-quoted-argument]="fg=${VAX_MAGENTA}"
ZSH_HIGHLIGHT_STYLES[double-quoted-argument]="fg=${VAX_MAGENTA}"
ZSH_HIGHLIGHT_STYLES[dollar-double-quoted-argument]="fg=${VAX_MAGENTA}"
ZSH_HIGHLIGHT_STYLES[back-double-quoted-argument]="fg=${VAX_MAGENTA}"
ZSH_HIGHLIGHT_STYLES[back-dollar-quoted-argument]="fg=${VAX_MAGENTA}"
ZSH_HIGHLIGHT_STYLES[unknown-token]="fg=${VAX_RED},bold"

# Add in snippets
zinit snippet OMZP::git
zinit snippet OMZP::sudo
zinit snippet OMZP::archlinux
zinit snippet OMZP::command-not-found

# Load completions
autoload -U compinit && compinit -d "$XDG_CACHE_HOME"/zsh/zcompdump-"$ZSH_VERSION"

zinit cdreplay -q

# Keybindings
bindkey -e
bindkey '^p' history-search-backward
bindkey '^n' history-search-forward
bindkey "\e[3~" delete-char # Del
bindkey '^[[1;5D' backward-word # Ctrl+Left
bindkey '^[[1;5C' forward-word # Ctrl+Right
bindkey '^[[H' beginning-of-line # Home
bindkey '^[[F' end-of-line # End

# History
HISTSIZE=5000
# Note: in case history doesn't work, then create this dir: mkdir -p "$XDG_STATE_HOME/zsh"
HISTFILE="$XDG_STATE_HOME"/zsh/history
SAVEHIST=$HISTSIZE
HISTDUP=erase
setopt appendhistory
setopt sharehistory
setopt hist_ignore_space
setopt hist_ignore_all_dups
setopt hist_save_no_dups
setopt hist_ignore_dups
setopt hist_find_no_dups

# Change directory without cd
setopt auto_cd

# Completion styling
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'
zstyle ':completion:*' list-colors 'fi=38;2;192;192;192:di=38;2;192;192;192:ex=38;2;0;255;65:ln=38;2;0;255;255:or=38;2;255;51;51:mi=38;2;255;51;51:pi=38;2;255;255;0:so=38;2;85;85;255:bd=38;2;255;255;0:cd=38;2;255;255;0:ma=30;47'
zstyle ':completion:*' menu no
zstyle ':fzf-tab:complete:cd:*' fzf-preview 'eza $realpath'

# Shell integration
export FZF_DEFAULT_OPTS="${FZF_DEFAULT_OPTS:+${FZF_DEFAULT_OPTS} }--color=fg:${VAX_SILVER},bg:${VAX_BLACK},hl:${VAX_YELLOW},fg+:#ffffff,bg+:${VAX_GRAY},hl+:${VAX_YELLOW},info:${VAX_GREEN},prompt:${VAX_GREEN},pointer:${VAX_GREEN},marker:${VAX_YELLOW},spinner:${VAX_GREEN},header:${VAX_DIM_GREEN},border:${VAX_BLUE}"
eval "$(fzf --zsh)"

man() {
  LESS_TERMCAP_md=$'\e[01;33m' \
  LESS_TERMCAP_me=$'\e[0m' \
  LESS_TERMCAP_se=$'\e[0m' \
  LESS_TERMCAP_so=$'\e[30;47m' \
  LESS_TERMCAP_ue=$'\e[0m' \
  LESS_TERMCAP_us=$'\e[1;36m' \
  command man "$@"
}

alias l="eza"
alias la='eza -A'
alias ls="eza"
alias ll="eza -lA"
alias cp="cp -i" # confirm before overwriting something
alias df="df -h"
alias free="free -m"
alias grep="grep --colour=auto"
alias egrep="egrep --colour=auto"
alias fgrep="fgrep --colour=auto"
#alias zzz="sudo zzz"
#alias reboot="sudo reboot"
#alias poweroff="sudo poweroff"
alias zzz="systemctl suspend"
alias mpv="mpv --volume=65 --audio-display=no"
alias tmux="tmux -2"
alias vim="nvim"
alias mc="mc -u"
alias q="cd $HOME/Games/quake2"
alias fd="fd --no-ignore"
alias rg="rg --no-ignore"

export EDITOR="nvim"
export VIEWER="nvim -R"
export TERMINAL="kitty"
export PATH="$PATH:$HOME/.local/bin:$HOME/.local/share/cargo/bin:$HOME/Projects/scripts:$HOME/Programs:$HOME/go/bin"
export _JAVA_AWT_WM_NONREPARENTING=1 # Fix for JDownloader 2

export MPD_HOST="$XDG_RUNTIME_DIR/mpd/socket"

export PS1="%F{${VAX_GREEN}}%~%f %F{${VAX_SILVER}}\$%f "

# Cyberpunk

#unset PS1 PROMPT RPS1 RPROMPT
#autoload -Uz colors && colors
#
#CYAN=%F{cyan}
#MAG=%F{magenta}
#YLW=%F{yellow}
#GRN=%F{green}
#WHT=%F{white}
#RST=%f
#
#PROMPT="${MAG}[${CYAN}%n${MAG}@${CYAN}%m${MAG}:${YLW}%~${MAG}]${GRN} >> ${RST}"
#setopt PROMPT_SUBST
#
#BLUE='%F{#5577ff}'
#CYAN='%F{#55ffff}'
#LIME='%F{#55ff99}'
#MAGENTA='%F{#ff55ff}'
#YELLOW='%F{#ffff55}'
#RED='%F{#ff5555}'
#RESET='%f%b'
#
#PS1='%B'"$BLUE"'%n'"$RESET"'@'"$CYAN"'%m'"$RESET"' '"$LIME"'%~'"$RESET"'
#%(?..'"$RED"'✘✘✘ '"$RESET"')'"$MAGENTA"'❯'"$CYAN"'❯'"$LIME"'❯ '"$RESET"
#
#RPS1='%B'"$YELLOW"'$(git rev-parse --abbrev-ref HEAD 2>/dev/null)'"$RESET"

function y() {
    local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
    yazi "$@" --cwd-file="$tmp"
    IFS= read -r -d '' cwd < "$tmp"
    [ -n "$cwd" ] && [ "$cwd" != "$PWD" ] && builtin cd -- "$cwd"
    rm -f -- "$tmp"
}

eval "$(direnv hook zsh)"

# opencode
export PATH=/home/user/.opencode/bin:$PATH

export PATH="$HOME/.local/bin/dotnet:$PATH"
export DOTNET_ROOT="$HOME/.local/bin/dotnet"
export CODEX_HOME="$HOME/.config/codex"

export HYPRSHOT_DIR="$HOME/Pictures"

export DO_NOT_TRACK=1 # https://donottrack.sh/
