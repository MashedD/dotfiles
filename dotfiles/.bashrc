[[ $- != *i* ]] && return

# From bash.sensible
PROMPT_DIRTRIM=2
PROMPT_COMMAND='history -a'
HISTSIZE=300000
HISTFILESIZE=100000
HISTCONTROL="erasedups:ignoreboth"
export HISTIGNORE="&:[ ]*:exit:ls:bg:fg:history:clear"
HISTTIMEFORMAT='%F %T '
# Use Kitty's ANSI palette for syntax highlighting in bat.
export BAT_THEME=ansi
CDPATH="."
set -o noclobber
shopt -s checkwinsize
shopt -s globstar 2> /dev/null
shopt -s nocaseglob
shopt -s histappend
shopt -s cmdhist
shopt -s autocd 2> /dev/null
shopt -s dirspell 2> /dev/null
shopt -s cdspell 2> /dev/null
shopt -s cdable_vars
bind Space:magic-space
bind "set completion-ignore-case on"
bind "set completion-map-case on"
bind "set show-all-if-ambiguous on"
bind "set mark-symlinked-directories on"
bind '"\e[A": history-search-backward'
bind '"\e[B": history-search-forward'
bind '"\e[C": forward-char'
bind '"\e[D": backward-char'

man() {
  LESS_TERMCAP_md=$'\e[38;2;214;189;114;1m' \
  LESS_TERMCAP_me=$'\e[0m' \
  LESS_TERMCAP_se=$'\e[0m' \
  LESS_TERMCAP_so=$'\e[01;44;33m' \
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
alias rg="rg --no-ignore"
alias fd="fd --no-ignore"
alias q="cd $HOME/Games/quake2"

# Keep Bash's fuzzy finder styled like the Zsh/Kitty Aurora setup.
if command -v fzf >/dev/null 2>&1; then
  export FZF_DEFAULT_OPTS="${FZF_DEFAULT_OPTS:+${FZF_DEFAULT_OPTS} }--border=sharp --color=fg:#c7d5cb,bg:#07110d,hl:#d6bd72,fg+:#f0f4f1,bg+:#1b2b22,hl+:#00ff41,info:#70c5bd,prompt:#70c98b,pointer:#00ff41,marker:#d6bd72,spinner:#70c5bd,header:#63736a,border:#263b30"
  eval "$(fzf --bash)"
fi

export EDITOR="vim"
export VIEWER="vim -R"
export TERMINAL="kitty"
export PATH="$PATH:$HOME/.local/bin:$HOME/Projects/scripts:$HOME/Programs:$HOME/go/bin"

export PATH="$HOME/.local/bin/dotnet:$PATH"
export DOTNET_ROOT="$HOME/.local/bin/dotnet"

# Match the Aurora two-line prompt used by the interactive Zsh setup.
if [ -r /usr/share/git/completion/git-prompt.sh ]; then
  . /usr/share/git/completion/git-prompt.sh
  GIT_PS1_SHOWDIRTYSTATE=1
  GIT_PS1_SHOWSTASHSTATE=1
  export PS1="\[\033[38;2;99;115;106m\]┌─\[\033[38;2;112;197;189m\]\W\[\033[38;2;99;115;106m\]\$(__git_ps1 ' [%s]')\n\[\033[38;2;0;255;65m\]└─❯\[\033[0m\] "
else
  export PS1="\[\033[38;2;99;115;106m\]┌─\[\033[38;2;112;197;189m\]\W\n\[\033[38;2;0;255;65m\]└─❯\[\033[0m\] "
fi
export _JAVA_AWT_WM_NONREPARENTING=1 # Fix for JDownloader 2

export MPD_HOST="$XDG_RUNTIME_DIR/mpd/socket"
export CODEX_HOME="$HOME/.config/codex"
export DO_NOT_TRACK=1 # https://donottrack.sh/

export XDG_PICTURES_DIR="$HOME/Pictures"
export HYPRSHOT_DIR="$HOME/Pictures"

eval "$(direnv hook bash)"

