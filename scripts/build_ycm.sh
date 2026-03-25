#!/bin/bash -ex

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

pushd "$DOTFILES_DIR/home/.vim/plugged/YouCompleteMe/"
python3 install.py --go-completer
popd
