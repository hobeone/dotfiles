#!/bin/bash -ex

pushd ./vim/bundle/youcompleteme
python install.py --go-completer
popd
