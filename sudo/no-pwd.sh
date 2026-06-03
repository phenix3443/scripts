#!/bin/bash
set -e
USER="${USER:-$(whoami)}"
echo "${USER} ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/nopass >/dev/null
sudo chmod 0440 /etc/sudoers.d/nopass
echo "[OK] ${USER} can run sudo without password"
