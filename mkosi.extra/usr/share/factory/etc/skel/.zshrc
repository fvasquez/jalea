# Jalea's default zsh configuration, copied from /etc/skel when the account
# is created. It is yours: edit or replace it. System-wide settings live in
# /etc/zsh/. Debian's own suggestions are in /etc/zsh/newuser.zshrc.recommended.

PROMPT='%F{green}%n@%m%f:%F{blue}%~%f%# '

# History: shared between shells, no duplicates, 10000 lines.
setopt histignorealldups sharehistory
HISTSIZE=10000
SAVEHIST=10000
HISTFILE=~/.zsh_history

# Emacs key bindings, like bash.
bindkey -e

# Completion, with a menu and case-insensitive matching.
autoload -Uz compinit
compinit
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list '' 'm:{a-z}={A-Z}' 'm:{a-zA-Z}={A-Za-z}' 'r:|[._-]=* r:|=* l:|=*'
zstyle ':completion:*' verbose true
eval "$(dircolors -b)"
zstyle ':completion:*:default' list-colors ${(s.:.)LS_COLORS}

alias ls='ls --color=auto'
alias grep='grep --color=auto'
