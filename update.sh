#!/bin/bash -ex
git pull
git submodule update --init --recursive

git status
if hash go 2>/dev/null; then
  ./install_go_tools.sh
else
  echo "No go executable found."
fi
