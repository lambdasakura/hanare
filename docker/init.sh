#!/bin/bash
set -e

if command -v mise &>/dev/null; then
  # /workspace 以下の mise 設定ファイルを自動で trust
  find /workspace -maxdepth 3 -name '.mise.toml' -o -name '.tool-versions' 2>/dev/null | while read -r f; do
    mise trust "$f"
  done

  # Node.js LTS を確保（npm / codex に必要）
  if ! mise which node &>/dev/null; then
    mise install node@lts
    mise use --global node@lts
  fi

  # ユーザ定義のツールをインストール
  mise install --yes

  # codex のインストール（npm が利用可能な場合のみ）
  if mise which npm &>/dev/null; then
    if ! mise exec -- command -v codex &>/dev/null; then
      mise exec -- npm install -g @openai/codex || true
    fi
  fi
fi
