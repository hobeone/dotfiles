#!/bin/sh -ex

INSTALL_TO=~/dotfiles
ECHO=""

while getopts "n" VALUE "$@"; do
  if [ "$VALUE" = "n" ]; then
    echo "Running in dryrun mode."
    ECHO=echo
  fi
done

warn() {
    echo ERROR: "$1" >&2
}

die() {
    warn "$1"
    exit 1
}

link_file_or_dir() {
  src="$1"
  dest="$2"
  if [ ! -e $dest ]; then
    echo "$dest doesn't exist, linking."
    $ECHO ln -sfT "$src" "$dest";
  elif [ -h $dest ]; then
    echo "$dest is a symlink, relinking."
    $ECHO ln -sfT "$src" "$dest";
  else
    warn "$dest already exists and is not a symlink. Skipping."
  fi
}

if [ -e $INSTALL_TO ]; then
  $ECHO cd $INSTALL_TO
  $ECHO git pull
else
  $ECHO git clone https://github.com/hobeone/dotfiles.git $INSTALL_TO
  $ECHO cd $INSTALL_TO
fi
# Initialize submodules
git submodule update --init --recursive


LINKS="vimrc vim ohmyzsh fonts Xmodmap Xresources zshrc tmux.conf xscreensaver npmrc p10k.zsh"
for f in $LINKS; do
  link_file_or_dir "$INSTALL_TO"/"$f" ~/."$f"
done

mkdir -p ~/bin
BINS="keyboard-settings file-inotify performance.sh swap2ram.sh"
for f in $BINS; do
  link_file_or_dir "$INSTALL_TO"/bin/"$f" ~/bin/"$f"
done

$ECHO fc-cache -f -v

$ECHO touch ~/.vim/user.vim
$ECHO touch ~/.zshrc.local

$ECHO mkdir -p ~/.config
$ECHO mkdir -p ~/.config/Terminal
$ECHO mkdir -p ~/.ssh
link_file_or_dir "$INSTALL_TO"/config/Terminal/terminalrc ~/.config/Terminal/terminalrc
link_file_or_dir "$INSTALL_TO"/config/openbox ~/.config/openbox
link_file_or_dir "$INSTALL_TO"/ssh/config ~/.ssh/config
link_file_or_dir "$INSTALL_TO"/config/input-remapper-2 ~/.config/input-remapper-2
link_file_or_dir "$INSTALL_TO"/config/labwc ~/.config/xfce4/labwc
link_file_or_dir "$INSTALL_TO"/config/labwc ~/.config/labwc
link_file_or_dir "$INSTALL_TO"/config/kanshi ~/.config/kanshi
