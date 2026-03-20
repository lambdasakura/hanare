ZSHHOME="$HOME/.config/zsh/conf"

if [ -d $ZSHHOME -a -r $ZSHHOME -a -x $ZSHHOME ]; then
    for i in $ZSHHOME/*; do
        source $i
    done
fi

# Load local overrides if present
[ -f "$HOME/.config/zsh/local.zshrc" ] && source "$HOME/.config/zsh/local.zshrc"
