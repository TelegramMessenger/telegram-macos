#!/bin/zsh
set -e
python3 "${0:A:h}/manual.py" --behavior old "$@"
