#!/bin/bash
set -e

# Docker ソケットへのアクセスを許可
if [ -S /var/run/docker.sock ]; then
  sudo chmod 666 /var/run/docker.sock
fi

exec "$@"
