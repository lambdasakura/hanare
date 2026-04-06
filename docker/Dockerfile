FROM ubuntu:latest

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Tokyo

ARG USERNAME=ubuntu

# minimal イメージを完全化（man, doc 等を復元）
# 変更されることがなく時間がかかるため、最初に実行してキャッシュを活用する
RUN yes | unminimize

# 基本パッケージと開発環境を導入
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install -y \
    sudo \
    tzdata \
    ca-certificates \
    curl \
    wget \
    git \
    vim \
    nano \
    less \
    bash-completion \
    unzip \
    zip \
    jq \
    make \
    build-essential \
    pkg-config \
    software-properties-common \
    openssh-client \
    tmux \
    zsh \
    locales \
    dnsutils \
    iputils-ping \
    net-tools \
    traceroute \
    iproute2

# UTF-8 ロケールを生成
RUN locale-gen en_US.UTF-8
ENV LANG=en_US.UTF-8

# Docker CLI をインストール
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    install -m 0755 -d /etc/apt/keyrings && \
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc && \
    chmod a+r /etc/apt/keyrings/docker.asc && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" > /etc/apt/sources.list.d/docker.list && \
    apt-get update && apt-get install -y docker-ce-cli

# 既存の ubuntu ユーザに sudo 権限を付与
RUN set -eux; \
    id "${USERNAME}"; \
    echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${USERNAME}; \
    chmod 0440 /etc/sudoers.d/${USERNAME}

WORKDIR /workspace
USER ${USERNAME}

# bash / zsh の設定は config/ からマウントされる
ENV PATH="/home/${USERNAME}/.local/bin:${PATH}"
RUN echo '[ -f "$HOME/.config/bash/.bashrc" ] && source "$HOME/.config/bash/.bashrc"' >> /home/${USERNAME}/.bashrc

# mise をインストール
RUN curl https://mise.run | sh

# starship をインストール
RUN curl -sS https://starship.rs/install.sh | sh -s -- --yes --bin-dir ~/.local/bin

# Claude Code をインストール
RUN curl -fsSL https://claude.ai/install.sh | bash

COPY --chmod=755 docker/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY --chmod=755 docker/init.sh /usr/local/bin/init.sh
COPY --chmod=755 docker/hanare-hostpath /usr/local/bin/hanare-hostpath

ENTRYPOINT ["entrypoint.sh"]
CMD ["/bin/zsh"]

