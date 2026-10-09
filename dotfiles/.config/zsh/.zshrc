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

# Aurora terminal palette; bright Matrix green is reserved for the prompt marker.
typeset -gr VAX_BLACK='#07110d'
typeset -gr VAX_GREEN='#70c98b'
typeset -gr VAX_DIM_GREEN='#63736a'
typeset -gr VAX_SILVER='#c7d5cb'
typeset -gr VAX_GRAY='#63736a'
typeset -gr VAX_YELLOW='#d6bd72'
typeset -gr VAX_CYAN='#70c5bd'
typeset -gr VAX_BLUE='#78a9c4'
typeset -gr VAX_MAGENTA='#b18bbd'
typeset -gr VAX_RED='#d87979'

# Settings for `less`
export LESS=-R
# Use Kitty's ANSI palette for syntax highlighting in bat.
export BAT_THEME=ansi
export LESS_TERMCAP_mb=$'\e[38;2;217;121;121;1m'
export LESS_TERMCAP_md=$'\e[38;2;214;189;114;1m'
export LESS_TERMCAP_me=$'\e[0m'
export LESS_TERMCAP_so=$'\e[30;47m'
export LESS_TERMCAP_se=$'\e[0m'
export LESS_TERMCAP_us=$'\e[38;2;112;197;189;1m'
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
zstyle ':completion:*' list-colors 'fi=38;2;199;213;203:di=38;2;120;169;196:ex=38;2;112;201;139:ln=38;2;112;197;189:or=38;2;217;121;121:mi=38;2;217;121;121:pi=38;2;214;189;114:so=38;2;177;139;189:bd=38;2;214;189;114:cd=38;2;214;189;114:ma=30;47'
zstyle ':completion:*' menu no
zstyle ':fzf-tab:complete:cd:*' fzf-preview 'eza $realpath'

# Shell integration
export FZF_DEFAULT_OPTS="${FZF_DEFAULT_OPTS:+${FZF_DEFAULT_OPTS} }--border=sharp --color=fg:${VAX_SILVER},bg:${VAX_BLACK},hl:${VAX_YELLOW},fg+:#f0f4f1,bg+:#1b2b22,hl+:#00ff41,info:${VAX_CYAN},prompt:${VAX_GREEN},pointer:#00ff41,marker:${VAX_YELLOW},spinner:${VAX_CYAN},header:${VAX_DIM_GREEN},border:#263b30"
eval "$(fzf --zsh)"

# Treat comments as comments
setopt interactivecomments

man() {
  LESS_TERMCAP_md=$'\e[38;2;214;189;114;1m' \
  LESS_TERMCAP_me=$'\e[0m' \
  LESS_TERMCAP_se=$'\e[0m' \
  LESS_TERMCAP_so=$'\e[30;47m' \
  LESS_TERMCAP_ue=$'\e[0m' \
  LESS_TERMCAP_us=$'\e[38;2;112;197;189;1m' \
  command man "$@"
}

export EZA_COLORS='di=38;2;120;169;196:ex=38;2;112;201;139:ln=38;2;112;197;189:or=38;2;217;121;121'
alias l="eza --icons=auto --group-directories-first"
alias la='eza --icons=auto --group-directories-first -A'
alias ls="eza --icons=auto --group-directories-first"
alias ll="eza --icons=auto --group-directories-first -lA --git"
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

# Two-line Aurora prompt: location and Git branch above, Matrix-green input below.
autoload -Uz add-zsh-hook vcs_info
zstyle ':vcs_info:git:*' check-for-changes true
zstyle ':vcs_info:git:*' check-for-staged-changes true
zstyle ':vcs_info:git:*' stagedstr '+'
zstyle ':vcs_info:git:*' unstagedstr '*'
zstyle ':vcs_info:git:*' formats ' %F{#63736a}[%b%u%c]%f'
zstyle ':vcs_info:git:*' actionformats ' %F{#63736a}[%b%u%c|%a]%f'
add-zsh-hook precmd vcs_info
setopt prompt_subst
PROMPT='%F{#63736a}┌─%f %F{#70c5bd}%~%f${vcs_info_msg_0_}%(?.. %F{#d87979}✘ %?%f)
%F{#00ff41}└─❯%f '

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
