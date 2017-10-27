#!/bin/bash -ex
git pull
git submodule update --init --remote
git submodule foreach git pull origin master

git status
if hash go 2>/dev/null; then
  ./install_go_tools.sh
else
  echo "No go executable found."
fi

if hash npm 2>/dev/null; then
  pushd vim/bundle/tern_for_vim
  npm install
  popd
else
  echo "npm not found"
fi
