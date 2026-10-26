#!/usr/bin/env bash
# WSL2 (Ubuntu) に Nix を入れて pico-dev の環境を先に取ってくるまでを1発でやる。
#
#   curl -fsSL https://raw.githubusercontent.com/lemonade-2061/pico-dev/master/wsl-setup.sh | bash
#
# 何度実行してもよい (済んでいる段階は飛ばす)。
set -euo pipefail

FLAKE="github:lemonade-2061/pico-dev"
NIX_PROFILE_SH=/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh

say() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m!!\033[0m %s\n' "$*" >&2; exit 1; }

# 1. WSL2 か (WSL1 では Nix が動かない)
if grep -qi microsoft /proc/version 2>/dev/null; then
  uname -r | grep -qi wsl2 ||
    die "WSL1 で動いている。PowerShell で 'wsl --set-version Ubuntu 2' してからやり直す"
else
  say "WSL ではなさそう。普通の Linux なら README の「使い方（Linux + Nix）」を見る"
fi

# 2. systemd が有効か (nix-daemon をサービスとして登録するのに要る)
if [ "$(ps -p 1 -o comm=)" != systemd ]; then
  if ! grep -qs '^systemd=true' /etc/wsl.conf; then
    say "WSL の systemd を有効にする (sudo のパスワードを聞かれる)"
    printf '\n[boot]\nsystemd=true\n' | sudo tee -a /etc/wsl.conf >/dev/null
  fi
  cat <<'EOF'

systemd を有効にした。反映には WSL の再起動が要る:
  1. このウィンドウを閉じる
  2. PowerShell で  wsl --shutdown
  3. Ubuntu を開き直して、同じコマンドをもう一度実行
EOF
  exit 0
fi

# 3. Nix 本体 (flakes も有効になった状態で入る)
if ! command -v nix >/dev/null && [ ! -e "$NIX_PROFILE_SH" ]; then
  say "Nix をインストールする (sudo のパスワードを聞かれる)"
  curl -fsSL https://install.determinate.systems/nix | sh -s -- install --no-confirm
fi
# 今のシェルにはまだ PATH が通っていないので読み込む
# shellcheck disable=SC1090
[ -e "$NIX_PROFILE_SH" ] && . "$NIX_PROFILE_SH"
command -v nix >/dev/null || die "nix が見つからない。Ubuntu を開き直してもう一度実行する"

# 4. 環境を先にダウンロードしておく (初回は 3.4GiB 程度、数分〜十数分)
say "Pico の開発環境をダウンロードする"
nix develop "$FLAKE" --command true

cat <<EOF

準備完了。Ubuntu を開き直してから:

  nix develop $FLAKE
  cd ~ && pico-new blink && cd blink && pico-build
  pico-flash      # Pico を BOOTSEL を押しながら挿しておく

printf の出力は Windows 側の TeraTerm 等で COM ポートを 115200 bps で開いて見る。
EOF
