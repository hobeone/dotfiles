#!/bin/bash -ex
git pull
git submodule update --init --remote
git status
./install_go_tools.sh
pushd vim/bundle/tern_for_vim
npm install
popd
