[ "$TERM" = "dumb" ] && PS1='$ ' && return

###############################################################################
# Common Settings
###############################################################################

# enable bash-completion
if [ -f /usr/share/bash-completion/bash_completion ]; then
    source /usr/share/bash-completion/bash_completion
elif [ -f /etc/bash_completion ]; then
    source /etc/bash_completion
fi

###############################################################################
# History
###############################################################################

HISTFILE=~/.bash_history
HISTSIZE=10000
HISTFILESIZE=10000

# append to history instead of overwriting
shopt -s histappend

# ignore duplicate commands and commands starting with space
HISTCONTROL=ignoreboth

# save multi-line commands as one entry
shopt -s cmdhist

###############################################################################
# Locale / Path
###############################################################################

export LANG=en_US.UTF-8
export LC_COLLATE=C

export PATH=~/bin:~/.local/bin:$PATH

###############################################################################
# Starship
###############################################################################
eval "$(starship init bash)"

###############################################################################
# SSH Agent
###############################################################################
SSH_AGENT_FILE="$HOME/.cache/ssh-agent.env"
if [ -z "$SSH_AUTH_SOCK" ]; then
    mkdir -p "$HOME/.cache"
    RUNNING_AGENT="$(ps -ax | grep 'ssh-agent -s' | grep -v grep | wc -l | tr -d '[:space:]')"
    if [ "$RUNNING_AGENT" = "0" ]; then
        ssh-agent -s &> "$SSH_AGENT_FILE"
    fi
    eval "$(cat "$SSH_AGENT_FILE")"
fi
