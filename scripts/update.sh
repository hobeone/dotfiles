#!/bin/bash -ex
git pull --recurse-submodules --verbose
git submodule update --init --recursive
git submodule foreach git pull --recurse-submodules origin master
git status --verbose
omz update
