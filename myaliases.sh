#!/bin/sh
echo "alias type='file'" >> $HOME/.bash_aliases
echo "alias fck='sudo \$(history -p \!\!)'" >> $HOME/.bash_aliases
echo "alias ubuntuversion='lsb_release -a'" >> $HOME/.bash_aliases
echo "alias ls='ls -alh --full-time --color'" >> $HOME/.bash_aliases
echo "alias .='ls -alh --full-time --color | more'" >> $HOME/.bash_aliases
echo "alias cd..='cd ..'" >> $HOME/.bash_aliases
echo "alias ..='cd ..'" >> $HOME/.bash_aliases
source $HOME/.bash_aliases
