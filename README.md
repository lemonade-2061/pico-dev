# pico-dev

Raspberry Pi Pico (RP2040) の開発環境を Nix flake 1個にまとめたもの。
`nix develop` に入った時点で SDK・ARM クロスコンパイラ・CMake・Ninja・picotool・
シリアルモニタが揃うので、VsCode の「Raspberry Pi Pico」拡張が `~/.pico-sdk` へ
2GB ダウンロードする工程は不要。

対象は **Pico 1 / RP2040**（`PICO_BOARD=pico` 固定）。Pico 2 (RP2350) を使うときは
`shell.nix` の `PICO_BOARD` / `PICO_PLATFORM` と、生成される `CMakeLists.txt` の
`set(PICO_BOARD pico ...)` を書き換える。

## コマンド

shell に入ると4つのコマンドが使える。VsCode 拡張のボタンと1対1で対応している。

| コマンド | 相当するもの | 内容 |
| --- | --- | --- |
| `pico-new <名前>` | New Project | `CMakeLists.txt` / `<名前>.c` / `pico_sdk_import.cmake` / `.clangd` / `.envrc` を生成（中身は LED 点滅 + `printf`） |
| `pico-build` | Compile | `cmake -G Ninja` → ビルド。`build/<名前>.uf2` が出る（`BUILD_TYPE=Release` で最適化） |
| `pico-flash` | RUN | `build/*.uf2` を書き込んで実行。環境に応じて picotool / RPI-RP2 ドライブへのコピーを自動で選ぶ |
| `pico-mon` | シリアルモニタ | `/dev/ttyACM*` を 115200 bps で開く（終了は `Ctrl-t q`） |

プロジェクト名は半角英数と `_` `-` のみ。日本語や空白はビルドが通らない。

## 使い方（Linux + Nix）

```sh
nix develop github:lemonade-2061/pico-dev
pico-new blink
cd blink
pico-build
pico-flash          # Pico を BOOTSEL モードで繋いでおく
pico-mon
```

`pico-new` は `.envrc` も置くので、[direnv](https://direnv.net/) があれば
`direnv allow` 以降は `cd` しただけで shell に入る。

### udev ルール（書き込み・シリアルの権限）

`picotool` は USB の生デバイスを開くので、ルールが無いと `Permission denied` になる。
ここは root 権限が必要で devShell では面倒を見られない。

**NixOS** — このリポジトリの NixOS モジュールを入れる:

```nix
# flake.nix
inputs.pico-dev.url = "github:lemonade-2061/pico-dev";

# configuration.nix 側
imports = [ inputs.pico-dev.nixosModules.default ];
programs.pico-dev = {
  enable = true;
  users = [ "yourname" ];   # dialout / plugdev に入れるユーザー
};
```

**その他の Linux** — ルールを手でコピーして、シリアルのグループに入る:

```sh
sudo cp "$(nix build --no-link --print-out-paths nixpkgs#picotool)/etc/udev/rules.d/60-picotool.rules" /etc/udev/rules.d/
sudo udevadm control --reload-rules && sudo udevadm trigger
sudo usermod -aG dialout "$USER"   # Arch 等で /dev/ttyACM* が root:uucp なら uucp
# 再ログイン（グループは入り直すまで効かない）
```

ルールを入れたくない場合でも、`pico-flash` は BOOTSEL 中の Pico が
`RPI-RP2` としてマウントされていればそこへコピーする経路に落ちるので書き込める。

## 使い方（Windows）

Nix は Windows ネイティブでは動かないので WSL2 を使う。ただし **WSL2 には
USB デバイスがそのままでは見えない**（picotool もシリアルも届かない）という制約が
あるため、素直さの順に3案ある。

### 案1: 素の VsCode + 「Raspberry Pi Pico」拡張（講義の手順書どおり）

Windows だけで完結し、書き込みもシリアルモニタも GUI から動く。
**単に課題を進めたいだけならこれが一番確実。** この flake の取り柄は
「環境が宣言的で壊れない・SDK を手で落とさない」ところなので、
Nix に興味が無いなら無理に移る必要はない。

### 案2: WSL2 でビルド + RPI-RP2 ドライブへコピーで書き込み（おすすめ）

USB passthrough が要らないので設定が軽い。`pico-flash` が WSL を検出して
自動でこの経路に切り替わる。

1. PowerShell（管理者）で WSL2 を入れて再起動:

   ```powershell
   wsl --install -d Ubuntu
   ```

2. Ubuntu の中で Nix を入れる（flakes を有効化）:

   ```sh
   sh <(curl -L https://nixos.org/nix/install) --daemon
   # シェルを開き直してから
   mkdir -p ~/.config/nix
   echo 'experimental-features = nix-command flakes' >> ~/.config/nix/nix.conf
   ```

3. 環境に入ってビルド:

   ```sh
   nix develop github:lemonade-2061/pico-dev
   pico-new blink && cd blink && pico-build
   ```

   プロジェクトは WSL 側のホーム（`~/`）に置く。`/mnt/c/...` 上はファイル I/O が
   遅く、ビルドが数倍重くなる。

4. Pico を BOOTSEL モードで繋ぐ（BOOTSEL を押しながら USB を挿す）。
   エクスプローラに `RPI-RP2` ドライブが出たら:

   ```sh
   pico-flash
   ```

   「RPI-RP2 ドライブが見つかりません」と言われたら、WSL からそのドライブが
   見えていない。`ls /mnt/*/INFO_UF2.TXT` で確認し、無ければ手動マウント:

   ```sh
   sudo mkdir -p /mnt/d && sudo mount -t drvfs D: /mnt/d   # D: は実際のドライブレター
   ```

   エクスプローラで `build/blink.uf2` を `RPI-RP2` にドラッグしても同じ。

5. シリアルモニタ（`printf` の出力）は **Windows 側**で開く。
   デバイスマネージャー →「ポート (COM と LPT)」で COM 番号を確認し、
   TeraTerm / PuTTY / Arduino IDE のシリアルモニタで **115200 bps**。

この案では `pico-mon` と `picotool` は使えない（WSL から USB が見えないため）。
`pico-build` までが Nix の担当、書き込みと表示は Windows 側という分担になる。

### 案3: WSL2 + usbipd-win（`pico-flash` / `pico-mon` まで WSL 内で完結）

USB デバイスを WSL に転送すれば Linux と同じ使い方ができる。

```powershell
winget install usbipd
usbipd list                       # BOOTSEL 中の Pico の BUSID を見る
usbipd bind   --busid <BUSID>     # 管理者権限、初回のみ
usbipd attach --wsl --busid <BUSID>
```

WSL 側で udev ルールが要るので、上の「その他の Linux」の手順も実施する。
注意点:

- BOOTSEL に入る／プログラムが起動するたびに USB デバイスとして出入りするので、
  その都度 `usbipd attach` が必要になりがち（素直さでは案2に負ける）。
- シリアル（CDC-ACM）は WSL2 の既定カーネルの構成次第で見えないことがあり、
  その場合 `CONFIG_USB_ACM` を有効にしたカーネルを自分でビルドする必要がある。

## ファイル構成

| ファイル | 役目 |
| --- | --- |
| `flake.nix` | 配線だけ。`devShells.{default,pico}` と `nixosModules.default` を公開 |
| `shell.nix` | devShell 本体。ツール一式と `pico-*` コマンドの実装 |
| `module.nix` | NixOS モジュール（udev ルール + dialout/plugdev） |
| `flake.lock` | nixpkgs を固定。手元で動いた組み合わせがそのまま再現される |

`shell.nix` は `flakeRef` 引数を取る。fork したら `pico-new` が生成する `.envrc`
の参照先を変えられる:

```nix
default = import ./shell.nix {
  inherit pkgs;
  flakeRef = "github:yourname/pico-dev";
};
```

## トラブルシュート

- **`pico-build` で `PICO_SDK_PATH` 関連のエラー** — devShell の外で実行している。
  `nix develop` に入ってから、または `direnv allow` を済ませる。
- **`picotool: Permission denied`** — udev ルールが入っていない（上記参照）。
- **`pico-mon` でポートが見つからない** — `pico_enable_stdio_usb` した
  プログラムを書き込まないとシリアルは現れない。LED 点滅だけのコードでは出てこない。
- **エディタで `pico/stdlib.h` が赤くなる** — `.clangd` は `build/` の
  `compile_commands.json` を読むので、一度 `pico-build` を通す。clangd には
  `--query-driver=**/arm-none-eabi-*` が必要（newlib のヘッダ解決）。
