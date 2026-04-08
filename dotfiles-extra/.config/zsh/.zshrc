[[ $- != *i* ]] && return

# Set the directory we want to store zinit and plugins
ZINIT_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/zinit/zinit.git"

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

# Download zinit, if it's not there yet
if [ ! -d "$ZINIT_HOME" ]; then
  mkdir -p "$(dirname $ZINIT_HOME)"
  git clone https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME"
fi

# Source/Load zinit
source "$ZINIT_HOME/zinit.zsh"

# Settings for `less`
export LESS=-R
export LESS_TERMCAP_mb="$(printf '%b' '[1;31m')"
export LESS_TERMCAP_md="$(printf '%b' '[1;36m')"
export LESS_TERMCAP_me="$(printf '%b' '[0m')"
export LESS_TERMCAP_so="$(printf '%b' '[01;44;33m')"
export LESS_TERMCAP_se="$(printf '%b' '[0m')"
export LESS_TERMCAP_us="$(printf '%b' '[1;32m')"
export LESS_TERMCAP_ue="$(printf '%b' '[0m')"
export LESSOPEN="| /usr/bin/highlight -O ansi %s 2>/dev/null"

#export FZF_DEFAULT_OPTS=TODO:

# Add in zsh plugins
zinit light zsh-users/zsh-syntax-highlighting
zinit light zsh-users/zsh-completions
zinit light zsh-users/zsh-autosuggestions
zinit light Aloxaf/fzf-tab

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
zstyle ':completion:*' list-colors '${(s.:.)LS_COLORS}'
zstyle ':completion:*' menu no
zstyle ':fzf-tab:complete:cd:*' fzf-preview 'eza $realpath'

# Shell integration
eval "$(fzf --zsh)"

man() {
  LESS_TERMCAP_md=$'\e[01;31m' \
  LESS_TERMCAP_me=$'\e[0m' \
  LESS_TERMCAP_se=$'\e[0m' \
  LESS_TERMCAP_so=$'\e[01;44;33m' \
  LESS_TERMCAP_ue=$'\e[0m' \
  LESS_TERMCAP_us=$'\e[01;32m' \
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
alias q="cd $HOME/Data/Games/q2pro"
alias fd="fd --no-ignore"
alias rg="rg --no-ignore"

export EDITOR="nvim"
export VIEWER="nvim -R"
export TERMINAL="kitty"
export PATH="$PATH:$HOME/.local/bin:$HOME/.local/share/cargo/bin:$HOME/Data/Projects/scripts:$HOME/Data/Programs"
export _JAVA_AWT_WM_NONREPARENTING=1 # Fix for JDownloader 2

export MPD_HOST="$XDG_RUNTIME_DIR/mpd/socket"

export PS1="%F{blue}%~%f $ "

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
