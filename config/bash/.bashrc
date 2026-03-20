BASHHOME="$HOME/.config/bash/conf"

if [ -d "$BASHHOME" ] && [ -r "$BASHHOME" ] && [ -x "$BASHHOME" ]; then
    for i in "$BASHHOME"/*; do
        source "$i"
    done
fi

# Load local overrides if present
[ -f "$HOME/.config/bash/local.bashrc" ] && source "$HOME/.config/bash/local.bashrc"
