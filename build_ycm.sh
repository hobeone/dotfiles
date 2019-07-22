#!/bin/bash -ex

pushd ./vim/bundle/YouCompleteMe
python install.py --go-completer
popd
