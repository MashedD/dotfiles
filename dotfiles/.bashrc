[[ $- != *i* ]] && return

# From bash.sensible
PROMPT_DIRTRIM=2
PROMPT_COMMAND='history -a'
HISTSIZE=300000
HISTFILESIZE=100000
HISTCONTROL="erasedups:ignoreboth"
export HISTIGNORE="&:[ ]*:exit:ls:bg:fg:history:clear"
HISTTIMEFORMAT='%F %T '
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
  LESS_TERMCAP_md=$'\e[01;31m' \
  LESS_TERMCAP_me=$'\e[0m' \
  LESS_TERMCAP_se=$'\e[0m' \
  LESS_TERMCAP_so=$'\e[01;44;33m' \
  LESS_TERMCAP_ue=$'\e[0m' \
  LESS_TERMCAP_us=$'\e[01;32m' \
  command man "$@"
}

alias l="ls --color=auto"
alias la='ls --color=auto -A'
alias ls="ls --color=auto"
alias ll="ls --color=auto -lA"
alias cp="cp -i" # confirm before overwriting something
alias df="df -h"
alias free="free -m"
alias grep="grep --colour=auto"
alias egrep="egrep --colour=auto"
alias fgrep="fgrep --colour=auto"
#alias zzz="sudo zzz"
#alias reboot="sudo reboot"
#alias poweroff="sudo poweroff"
alias mpv="mpv --volume=65 --audio-display=no"
alias tmux="tmux -2"

export EDITOR="vim"
export VIEWER="vim -R"
export TERMINAL="st"
export PATH="$PATH:$HOME/.local/bin:$HOME/Projects/scripts"
export PS1="\[\033[01;36m\]\[\033[01;34m\]\W\[\033[01;36m\]\$\[\033[00m\] "
export _JAVA_AWT_WM_NONREPARENTING=1 # Fix for JDownloader 2

