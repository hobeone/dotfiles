#!/bin/bash -ex

pushd home/vim/plugged/YouCompleteMe/
python3 install.py --go-completer
popd
