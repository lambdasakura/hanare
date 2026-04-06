# hanare (AI Sandbox)

Docker ベースの AI 開発環境コンテナ。bash / zsh + starship のシェル環境に、mise によるツール管理、AI コーディングツール（Claude Code, Codex）がプリインストールされている。Linux / macOS / Windows に対応。

## 前提条件

- Docker（Linux / macOS）または Docker Desktop for Windows
- Linux / macOS: bash
- Windows: PowerShell 5.1+

## インストール

リポジトリをクローンし、`hanare` コマンドにパスを通す。

### Linux / macOS

```bash
git clone <repository-url> ~/hanare
ln -s ~/hanare/hanare ~/.local/bin/hanare
```

`~/.local/bin` にパスが通っていない場合はシェルの設定に追加する:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

### Windows

リポジトリをクローンし、`hanare.cmd` へのシンボリックリンクをパスの通ったディレクトリに作成する。

```powershell
git clone <repository-url> $HOME\hanare

# ディレクトリがなければ作成
New-Item -ItemType Directory -Path "$HOME\bin" -Force

# シンボリックリンクを作成（管理者権限の PowerShell で実行）
New-Item -ItemType SymbolicLink -Path "$HOME\bin\hanare.cmd" -Target "$HOME\hanare\hanare.cmd"
New-Item -ItemType SymbolicLink -Path "$HOME\bin\hanare.ps1" -Target "$HOME\hanare\hanare.ps1"
```

`$HOME\bin` にパスが通っていない場合はシステム環境変数に追加する:

```powershell
# 現在のユーザの PATH に追加
[Environment]::SetEnvironmentVariable("Path", "$HOME\bin;" + [Environment]::GetEnvironmentVariable("Path", "User"), "User")
```

> **Note**: PowerShell の実行ポリシーが制限されている場合は `hanare.cmd` を使うか、`Set-ExecutionPolicy RemoteSigned -Scope CurrentUser` を実行する。

## クイックスタート

```bash
# イメージをビルド
hanare build

# コンテナを起動（ディレクトリを /workspace 配下にマウント）
hanare start ~/projects/myapp

# 複数ディレクトリを同時にマウントして起動
hanare start ~/projects/myapp ~/projects/shared-lib

# 起動中のコンテナに別ターミナルから接続
hanare attach myapp

# コンテナを停止・削除（ディレクトリパスまたはコンテナ名で指定）
hanare stop ~/projects/myapp
hanare stop myapp
```

### 初回起動について

初回の `start` 時は mise が Node.js 等のツールを自動インストールするため数分かかる。2 回目以降は `mise-data/` にキャッシュされるためスキップされる。

## コマンド

| コマンド | 説明 |
|---|---|
| `hanare build [<name>]` | コンテナイメージをビルド。`<name>` 指定時は `Dockerfile.<name>` を使用 |
| `hanare start [--image <name>] [--shell bash\|zsh] <dir>...` | コンテナを起動。複数ディレクトリを同時にマウント可能。既に起動中なら再接続 |
| `hanare attach [--shell bash\|zsh] [<name>]` | 起動中のコンテナに接続。`<name>` 省略時は起動中のコンテナが 1 つなら自動選択 |
| `hanare stop <dir\|name>` | コンテナを停止・削除。ディレクトリパスまたはコンテナ名で指定 |
| `hanare clean` | 全コンテナを停止・削除し、全 hanare イメージも削除 |
| `hanare status` | 起動中の hanare コンテナを一覧表示（使用イメージも表示） |
| `hanare help` | ヘルプを表示 |

## 起動の仕組み

```
hanare start <dir>...
  │
  ├─ docker run -d ... sleep infinity   ← コンテナをバックグラウンドで起動
  │    └─ entrypoint.sh                 ← Docker ソケットのパーミッション設定
  │
  ├─ docker exec init.sh               ← mise install（ツールの初期化、完了まで待機）
  │
  └─ docker exec -it tmux ...          ← tmux セッションに接続（シェル起動）
```

既に起動中のコンテナに対して `start` を実行すると、init をスキップして tmux に再接続する。`attach` でも起動中のコンテナに接続できる（別ターミナルからの接続用）。

## デフォルト設定の変更

`hanare.conf` を作成すると、デフォルトのイメージ・シェル・Docker 起動オプションを変更できる。

```bash
cp hanare.conf.example hanare.conf
```

```bash
# hanare.conf
IMAGE=myenv
SHELL=bash
DOCKER_OPTS=--gpus all --network host -p 8080:8080
```

| 設定 | 説明 | 環境変数 |
|---|---|---|
| `IMAGE` | デフォルトイメージ名 | `HANARE_IMAGE` |
| `SHELL` | デフォルトシェル (bash/zsh) | `HANARE_SHELL` |
| `DOCKER_OPTS` | `docker run` に追加するオプション | `HANARE_DOCKER_OPTS` |

環境変数で一時的に上書き可能。`--image` / `--shell` の CLI フラグが最優先。

## プロキシ環境での利用

`HTTP_PROXY` / `HTTPS_PROXY` / `NO_PROXY` 環境変数を設定してから `build` / `start` を実行すると、Docker のビルド・起動時に自動で渡される。

```bash
export HTTP_PROXY=http://proxy.example.com:8080
export HTTPS_PROXY=http://proxy.example.com:8080
export NO_PROXY=localhost,127.0.0.1
hanare build
hanare start .
```

## ファイル構成

```
.
├── hanare                    # CLI (Linux/macOS bash)
├── hanare.ps1                # CLI (Windows PowerShell)
├── hanare.cmd                # Windows 用 .cmd ラッパー
├── hanare.conf.example       # デフォルト設定のひな形
├── docker/
│   ├── Dockerfile            # デフォルトイメージ定義
│   ├── Dockerfile.example    # カスタムイメージのひな形
│   ├── entrypoint.sh         # エントリーポイント（Docker ソケット設定）
│   ├── init.sh               # 初期化スクリプト（mise install 等）
│   └── hanare-hostpath       # コンテナ内パス → ホストパス変換コマンド
├── config/                   # ~/.config/ にマウントされる設定ファイル群
│   ├── starship.toml         # starship プロンプト設定
│   ├── mise/
│   │   └── config.toml.example  # ツール定義のひな形
│   ├── git/
│   │   ├── config            # 汎用 git 設定
│   │   ├── config.local.example  # 個人設定のひな形
│   │   └── ignore            # グローバル gitignore
│   ├── bash/
│   │   ├── .bashrc                # conf/* と local.bashrc の読み込み
│   │   ├── local.bashrc.example   # 個人設定のひな形
│   │   └── conf/
│   │       ├── 00_bash_setup.sh       # 汎用 bash 設定
│   │       ├── 01_mise.sh             # mise 有効化
│   │       └── 90_local.sh.example    # 個人設定のひな形
│   ├── tmux/
│   │   ├── tmux.conf              # 汎用 tmux 設定
│   │   └── tmux.local.conf.example  # 個人設定のひな形
│   └── zsh/
│       ├── .zshenv                # ZDOTDIR 設定
│       ├── .zshrc                 # conf/* と local.zshrc の読み込み
│       ├── local.zshrc.example    # 個人設定のひな形
│       └── conf/
│           ├── 00_zsh_setup.sh        # 汎用 zsh 設定
│           ├── 01_mise.sh             # mise 有効化
│           └── 90_local.sh.example    # 個人設定のひな形
├── ssh/                      # ~/.ssh にマウント（読み取り専用）
└── mise-data/                # mise データ永続化用
```

## ボリュームマウント

### 常にマウントされるもの

| ホスト側 | コンテナ内 | 備考 |
|---|---|---|
| `config/` | `~/.config/` | 設定ファイル群 |
| `ssh/` | `~/.ssh/` | 読み取り専用 |
| `mise-data/` | `~/.local/share/mise/` | ツールデータ永続化 |
| `<dir>...` (引数) | `/workspace/<dir名>/` | 作業ディレクトリ（複数指定可） |
| `/var/run/docker.sock` | `/var/run/docker.sock` | Docker outside of Docker |

### 条件付きでマウントされるもの

| ホスト側 | コンテナ内 | 条件 |
|---|---|---|
| `config/zsh/.zshenv` | `~/.zshenv` | zsh 使用時（読み取り専用） |
| `~/.claude/` | `~/.claude/` | ディレクトリが存在する場合 |
| `~/.claude.json` | `~/.claude.json` | ファイルが存在する場合 |
| `~/.codex/` | `~/.codex/` | ディレクトリが存在する場合 |

## プリインストール済みツール

| カテゴリ | ツール |
|---|---|
| シェル | zsh, bash, tmux |
| プロンプト | starship |
| ツール管理 | mise |
| ランタイム | Node.js (LTS) ※ init.sh が自動インストール |
| AI | Claude Code, Codex (`@openai/codex`) |
| ビルド | make, build-essential (gcc, g++ 含む), pkg-config |
| ネットワーク | dnsutils (dig, nslookup), iputils-ping, net-tools, traceroute, iproute2 (ip, ss) |
| ユーティリティ | git, curl, wget, jq, vim, nano, less, zip/unzip, Docker CLI, man |

## カスタマイズ

### 個人設定

`.example` ファイルをコピーして個人設定を追加できる。これらのファイルは `.gitignore` で除外されているため、リポジトリには影響しない。

```bash
# git（ユーザ名、メール、alias 等）
cp config/git/config.local.example config/git/config.local

# bash（alias、EDITOR、PAGER 等）
cp config/bash/conf/90_local.sh.example config/bash/conf/90_local.sh
cp config/bash/local.bashrc.example config/bash/local.bashrc

# zsh（alias、EDITOR、PAGER 等）
cp config/zsh/conf/90_local.sh.example config/zsh/conf/90_local.sh
cp config/zsh/local.zshrc.example config/zsh/local.zshrc

# tmux（prefix キー、status line 等）
cp config/tmux/tmux.local.conf.example config/tmux/tmux.local.conf
```

### シェル設定の構造

bash / zsh ともに同じ構造でカスタマイズできる:

| 役割 | bash | zsh |
|---|---|---|
| エントリーポイント | `config/bash/.bashrc` | `config/zsh/.zshrc` |
| 汎用設定 | `conf/00_bash_setup.sh` | `conf/00_zsh_setup.sh` |
| mise 有効化 | `conf/01_mise.sh` | `conf/01_mise.sh` |
| 個人設定（gitignore） | `conf/90_local.sh` | `conf/90_local.sh` |
| 追加設定（gitignore） | `local.bashrc` | `local.zshrc` |

`conf/` 内のファイルはファイル名順にソースされる。`90_local.sh` で `00_*` の設定を上書きできる。

### mise でツールを追加する

コンテナ内で mise を使って開発ツールを追加できる。`mise-data/` にデータが永続化されるため、コンテナを再作成しても維持される。

```bash
# コンテナ内で実行
mise use --global python@latest
mise use --global go@latest
mise use --global rust@latest
```

`mise use --global` は `~/.config/mise/config.toml` に追記する。このファイルは `.gitignore` で除外されているため、ユーザごとに自由にカスタマイズできる。Node.js (LTS) は init.sh が自動でインストールするため、config.toml に記載しなくても利用可能。

### カスタムイメージ

デフォルトの Dockerfile を変更せずに、用途別のイメージを作成できる。

```bash
# ひな形をコピー
cp docker/Dockerfile.example docker/Dockerfile.myenv

# 編集して必要なパッケージを追加
vim docker/Dockerfile.myenv

# ビルド
hanare build myenv

# カスタムイメージでコンテナを起動
hanare start --image myenv ~/projects/myapp
```

カスタム Dockerfile では `FROM hanare:default` でデフォルトイメージを拡張できる。`docker/Dockerfile.*` は `.gitignore` で除外されているため、リポジトリに影響しない。

毎回 `--image` を指定するのが面倒な場合は、`hanare.conf` で `IMAGE=myenv` をデフォルトに設定できる（「デフォルト設定の変更」を参照）。

## Docker outside of Docker でのボリュームマウント

コンテナ内から Docker コマンドを実行する際、コンテナ内のパスをそのまま `-v` に指定しても正しくマウントされない（Docker daemon はホスト上で動作しているため、ホスト側のパスが必要）。

`hanare-hostpath` コマンドを使うと、コンテナ内のパスを対応するホスト側のパスに変換できる。

```bash
# コンテナ内で実行
docker run -v "$(hanare-hostpath /workspace/myproject)":/data some-image
```

ホスト上で実行した場合はそのまま絶対パスを返す。マウントされていないパスを指定した場合はエラーになる。

## 注意事項

- Docker ソケットがマウントされているため、コンテナ内から Docker コマンドを実行できる（Docker outside of Docker）。
- SSH 鍵は `ssh/` ディレクトリに配置する。
- `config/` 配下のファイルはホスト側で編集すれば即座にコンテナに反映される。
- コンテナは `unminimize` 済みのため、man ページやドキュメントが利用可能。
