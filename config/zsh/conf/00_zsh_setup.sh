[[ $TERM == "dumb" ]] && unsetopt zle && PS1='$ ' && return

###############################################################################
# Common Settings
###############################################################################

bindkey -e

setopt NO_beep
setopt print_eight_bit
setopt NO_flow_control
setopt auto_pushd

WORDCHARS='*?_-.[]~=&;!#$%^(){}<>'

###############################################################################
# History
###############################################################################

setopt append_history

HISTFILE=~/.histfile
HISTSIZE=10000
SAVEHIST=10000

setopt extended_history
setopt hist_ignore_dups
setopt hist_ignore_all_dups
setopt hist_verify
setopt share_history

###############################################################################
# Completion
###############################################################################

LISTMAX=0

autoload -Uz compinit; compinit

zstyle ':completion:*:sudo:*' command-path /usr/local/sbin /usr/local/bin /usr/sbin /usr/bin /sbin /bin

setopt auto_list
setopt auto_menu
setopt auto_param_keys
setopt auto_param_slash
setopt NO_list_types
setopt magic_equal_subst
setopt mark_dirs

zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS}

###############################################################################
# Locale / Path
###############################################################################

export LANG=en_US.UTF-8
export LC_COLLATE=C

export PATH=~/bin:~/.local/bin:$PATH

###############################################################################
# Starship
###############################################################################
eval "$(starship init zsh)"

###############################################################################
# SSH Agent
###############################################################################
SSH_AGENT_FILE="$HOME/.cache/ssh-agent.env"
if [ -z "$SSH_AUTH_SOCK" ]; then
   mkdir -p "$HOME/.cache"
   RUNNING_AGENT="`ps -ax | grep 'ssh-agent -s' | grep -v grep | wc -l | tr -d '[:space:]'`"
   if [ "$RUNNING_AGENT" = "0" ]; then
        ssh-agent -s &> "$SSH_AGENT_FILE"
   fi
   eval `cat "$SSH_AGENT_FILE"`
fi
