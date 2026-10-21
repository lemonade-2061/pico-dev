# RaspberryPi Pico (RP2040) 開発環境 — devShell 本体。
#
#   nix develop github:lemonade-2061/pico-dev   # リポジトリから直接
#   nix develop                                 # clone したディレクトリで
#
# 基板は Pico 1 / RP2040 前提 (PICO_BOARD=pico)。SDK とツールチェーンは nix store
# 上に来るので、VsCode 拡張が ~/.pico-sdk に 2GB 落とす工程は丸ごと要らない。
#
# 鷹合研究室の手順書 (Windows + VsCode + 「Raspberry Pi Pico」拡張) がやっている
#   1. SDK/ツールチェーン取得 → この devShell (宣言的)
#   2. Compile       → pico-build
#   3. RUN           → pico-flash
#   4. シリアルモニタ → pico-mon
# の置き換え。エディタは何でもよい (nvim + clangd を想定)。
#
# root 権限が必要な部分 (udev ルール / dialout グループ) は devShell では扱えない。
# NixOS なら ./module.nix を imports、他の Linux は README の手動手順を見る。
# WSL2 では picotool / シリアルが使えないので pico-flash は RPI-RP2 ドライブへの
# コピーに自動で切り替わる (詳細は README)。
{
  pkgs,
  # pico-new が生成する .envrc (direnv) が指す flake。clone して使う場合や
  # fork した場合はここを上書きする。
  flakeRef ? "github:lemonade-2061/pico-dev",
  # Picoprobe/debugprobe 経由の SWD デバッグ (openocd)。閉包が 0.8GB 増える
  # (openocd-rp2040 が GTK4 / SDL / zenity を引きずる) ので既定では入れない。
  # 必要なときは `nix develop github:lemonade-2061/pico-dev#debug`。
  withOpenocd ? false,
}:

let
  # withSubmodules: TinyUSB を含む。pico_stdio_usb (printf を USB シリアルへ
  # 出す = 手順書の「シリアルモニター」) が TinyUSB 必須なので必ず有効にする。
  picoSdk = pkgs.pico-sdk.override { withSubmodules = true; };
  sdkPath = "${picoSdk}/lib/pico-sdk";

  # 手順書の「新規プロジェクトの作り方」に相当。拡張機能の New Project が
  # 吐くのと同じ構成 (CMakeLists.txt / <名前>.c / pico_sdk_import.cmake) を作る。
  pico-new = pkgs.writeShellApplication {
    name = "pico-new";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      set -euo pipefail
      name="''${1:-}"
      if [ -z "$name" ]; then
        echo "usage: pico-new <プロジェクト名>   (例: pico-new test00)" >&2
        exit 1
      fi
      case "$name" in
        *[!A-Za-z0-9_-]*)
          echo "pico-new: 名前は半角英数と _ - のみ (日本語・空白はビルドエラーの原因)" >&2
          exit 1;;
      esac
      if [ -e "$name" ]; then
        echo "pico-new: '$name' はすでに存在します" >&2
        exit 1
      fi

      mkdir -p "$name"
      cd "$name"

      # SDK 同梱の import スクリプトをそのまま使う (PICO_SDK_PATH を解決する)
      cp "${sdkPath}/external/pico_sdk_import.cmake" .
      chmod +w pico_sdk_import.cmake

      cat > CMakeLists.txt <<EOF
      cmake_minimum_required(VERSION 3.13)

      set(CMAKE_C_STANDARD 11)
      set(CMAKE_CXX_STANDARD 17)
      # clangd (エディタの補完・エラー表示) が読む compile_commands.json を出す
      set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

      # 基板は Pico 1 (RP2040)。Pico2 を選ぶと書き込めないので注意。
      set(PICO_BOARD pico CACHE STRING "Board type")

      include(pico_sdk_import.cmake)

      project($name C CXX ASM)
      pico_sdk_init()

      add_executable($name $name.c)
      pico_set_program_name($name "$name")
      pico_set_program_version($name "0.1")

      # printf の行き先。USB シリアル (/dev/ttyACM0) に出す = pico-mon で読める。
      pico_enable_stdio_usb($name 1)
      pico_enable_stdio_uart($name 0)

      target_link_libraries($name
        pico_stdlib      # GPIO / タイマー / stdio
        hardware_adc     # 電圧計測 (w2_volt 等)
        hardware_pwm     # PWM 出力
      )

      # .uf2 (書き込み用ファイル) と .elf/.bin/.dis を build/ に生成する
      pico_add_extra_outputs($name)
      EOF

      cat > "$name.c" <<EOF
      #include <stdio.h>
      #include "pico/stdlib.h"

      #define LED_DELAY_MS 250

      int main(void) {
          stdio_init_all();

          gpio_init(PICO_DEFAULT_LED_PIN);
          gpio_set_dir(PICO_DEFAULT_LED_PIN, GPIO_OUT);

          while (true) {
              gpio_put(PICO_DEFAULT_LED_PIN, 1);
              sleep_ms(LED_DELAY_MS);
              gpio_put(PICO_DEFAULT_LED_PIN, 0);
              sleep_ms(LED_DELAY_MS);
              printf("blink\n");
          }
      }
      EOF

      # clangd (エディタの補完・エラー表示) は cmake が build/ に吐く
      # compile_commands.json を読む。SDK が使うコンパイルフラグ
      # (-mcpu=cortex-m0plus -mthumb -std=gnu11 ...) は clang でもそのまま通る。
      #
      # newlib のヘッダを解決させるには clangd に --query-driver が必要だが、
      # これは CLI 専用オプションなので .clangd には書けない。
      # nvim 側 (dotfiles/nvim/lua/plugins/clangd.lua) で渡している。
      #
      # UnusedIncludes/MissingIncludes は切る。pico/stdlib.h のような
      # まとめヘッダ (中身を再 include するだけ) を「直接使っていない」と
      # 誤検出して毎回警告を出すため。
      cat > .clangd <<'EOF'
      CompileFlags:
        CompilationDatabase: build

      Diagnostics:
        UnusedIncludes: None
        MissingIncludes: None
      EOF

      # cd しただけで devShell に入るように (direnv)
      cat > .envrc <<'EOF'
      use flake ${flakeRef}
      EOF

      cat > .gitignore <<'EOF'
      build/
      .direnv/
      EOF

      echo "作成しました: $PWD"
      echo "  cd $name && direnv allow   # 初回のみ"
      echo "  pico-build   # ビルド (手順書の Compile)"
      echo "  pico-flash   # 書き込み  (手順書の RUN)"
      echo "  pico-mon     # シリアルモニタ"
    '';
  };

  # 手順書の「Compile」ボタン相当。cmake 構成は build/ が無いときだけ走る。
  pico-build = pkgs.writeShellApplication {
    name = "pico-build";
    runtimeInputs = [ pkgs.cmake pkgs.ninja ];
    text = ''
      set -euo pipefail
      [ -f CMakeLists.txt ] || { echo "pico-build: CMakeLists.txt が無い (プロジェクトの直下で実行して)" >&2; exit 1; }
      # 既定は Debug。手順書の「ビルドタイプ切り替え」に相当し、最適化による
      # 不具合を避けるため開発中は Debug のままでよい (BUILD_TYPE=Release で変更)。
      cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE="''${BUILD_TYPE:-Debug}"
      cmake --build build "$@"
      echo
      ls -1 build/*.uf2 2>/dev/null || echo "警告: .uf2 が生成されていません (pico_add_extra_outputs を確認)"
    '';
  };

  # 手順書の「RUN」ボタン相当。BOOTSEL 中の Pico に uf2 を書き込んで実行させる。
  #
  # 経路は2つある:
  #   picotool   … USB の生デバイス (PICOBOOT インタフェース) を開く。ネイティブ
  #                Linux 用。書き込み後そのまま実行 (-x) までできる。
  #   ドライブへ cp … BOOTSEL 中の Pico はマスストレージ (RPI-RP2) にも見えるので、
  #                .uf2 を置くだけで書き込める。手順書のドラッグ&ドロップと同じ。
  #                WSL2 は /dev/bus/usb に Pico が出てこない (usbipd-win が必要) ため
  #                こちらを使う。Windows 側にマウントされた /mnt/<ドライブ> を探す。
  pico-flash = pkgs.writeShellApplication {
    name = "pico-flash";
    runtimeInputs = [ pkgs.picotool pkgs.coreutils pkgs.gnugrep ];
    text = ''
      set -euo pipefail

      is_wsl() {
        [ -n "''${WSL_DISTRO_NAME:-}" ] && return 0
        grep -qi microsoft /proc/sys/kernel/osrelease 2>/dev/null
      }

      # BOOTSEL 中の Pico がマスストレージとして見えていればそのマウント先を返す。
      # INFO_UF2.TXT は RP2 ブートROM が必ず置くファイルなので目印に使える。
      find_uf2_drive() {
        local info
        for info in /mnt/*/INFO_UF2.TXT /run/media/*/*/INFO_UF2.TXT /media/*/*/INFO_UF2.TXT; do
          if [ -f "$info" ]; then
            dirname "$info"
            return 0
          fi
        done
        return 1
      }

      copy_to_drive() {
        local drive="$1" file="$2"
        echo "コピー: $file -> $drive  (RPI-RP2)"
        cp "$file" "$drive/"
        sync
        echo "完了。Pico が自動で再起動してプログラムが走ります。"
      }

      uf2="''${1:-}"
      if [ -z "$uf2" ]; then
        # build 直下の .uf2 を自動で選ぶ
        set -- build/*.uf2
        [ -e "$1" ] || { echo "pico-flash: build/*.uf2 が無い。先に pico-build を実行して" >&2; exit 1; }
        [ "$#" -eq 1 ] || { echo "pico-flash: .uf2 が複数ある。ファイルを指定して: $*" >&2; exit 1; }
        uf2="$1"
      fi
      [ -f "$uf2" ] || { echo "pico-flash: '$uf2' が無い" >&2; exit 1; }

      # WSL2: picotool は使えないのでドライブ経路だけ
      if is_wsl; then
        if drive="$(find_uf2_drive)"; then
          copy_to_drive "$drive" "$uf2"
          exit 0
        fi
        cat >&2 <<'MSG'

      pico-flash: RPI-RP2 ドライブが見つかりません (WSL2)。

      WSL2 では USB デバイスそのものが見えないため、Windows 側に現れる
      「RPI-RP2」ドライブ経由で書き込みます。次の順で操作してください:
        1. 基板の BOOTSEL ボタンを押したまま USB を挿し直す
           (外部タクトスイッチがあるなら: BOOTSEL 押下 → 28番GND-30番RUN を
            押して離す → BOOTSEL を離す)
        2. エクスプローラに RPI-RP2 ドライブが出たのを確認する
        3. この WSL から見えるか確認: ls /mnt/*/INFO_UF2.TXT
           見えないときは sudo mkdir -p /mnt/d && sudo mount -t drvfs D: /mnt/d
           (D: は実際のドライブレターに置き換える)
        4. もう一度 pico-flash

      エクスプローラで build/*.uf2 を RPI-RP2 に直接ドラッグしても同じです。
      MSG
        exit 1
      fi

      # ネイティブ Linux: まず picotool
      # -f: 実行中プログラムが USB reset インタフェースを持てば自動で BOOTSEL に落とす
      #     (pico_enable_stdio_usb したプログラムなら手でボタンを押さなくてよい)
      # -x: 書き込み後にそのまま実行する
      echo "書き込み: $uf2"
      if picotool load -f -x -v "$uf2"; then
        exit 0
      fi

      # picotool が失敗 (udev ルール未設定など) → ドライブが見えていればそちらで
      if drive="$(find_uf2_drive)"; then
        echo "picotool は失敗したので RPI-RP2 ドライブ経由で書き込みます" >&2
        copy_to_drive "$drive" "$uf2"
        exit 0
      fi

      cat >&2 <<'MSG'

      書き込めませんでした。Pico を手動で BOOTSEL モードにしてから再実行してください:
        1. 基板の BOOTSEL ボタンを押したままにする
        2. 外部タクトスイッチ (28番 GND - 30番 RUN) を押して離す
        3. BOOTSEL ボタンから手を離す
      picotool info で認識されているか確認できます。
      「Permission denied」が出る場合は udev ルールが入っていません (README 参照)。
      MSG
      exit 1
    '';
  };

  # 手順書の「シリアルモニターの使い方」相当。Ctrl-t q で終了。
  pico-mon = pkgs.writeShellApplication {
    name = "pico-mon";
    runtimeInputs = [ pkgs.tio pkgs.coreutils pkgs.gnugrep ];
    text = ''
      set -euo pipefail
      dev="''${1:-}"
      if [ -z "$dev" ]; then
        # Pico の CDC-ACM を探す (Raspberry Pi のベンダID 2e8a)
        for d in /dev/serial/by-id/*Raspberry_Pi* /dev/ttyACM*; do
          [ -e "$d" ] && { dev="$d"; break; }
        done
      fi
      if [ -z "$dev" ]; then
        if [ -n "''${WSL_DISTRO_NAME:-}" ] || grep -qi microsoft /proc/sys/kernel/osrelease 2>/dev/null; then
          cat >&2 <<'MSG'
      pico-mon: WSL2 からは Pico のシリアル (/dev/ttyACM*) は見えません。
      Windows 側のターミナルソフトで COM ポートを開いてください:
        - デバイスマネージャー →「ポート (COM と LPT)」で COM番号を確認
        - TeraTerm / PuTTY / Arduino IDE のシリアルモニタ で 115200 bps で接続
      どうしても WSL 内で読みたい場合は usbipd-win でデバイスを渡す必要があります
      (README の「WSL2 でフルに使う」参照)。
      MSG
          exit 1
        fi
        echo "pico-mon: シリアルポートが見つからない。Pico にプログラムが書き込まれているか確認 (blink だけだと出てきません)" >&2
        exit 1
      fi
      echo "接続: $dev  (終了: Ctrl-t q)"
      exec tio -b 115200 "$dev"
    '';
  };
in
pkgs.mkShell {
  packages = with pkgs; [
    gcc-arm-embedded # arm-none-eabi-gcc / arm-none-eabi-gdb (クロスコンパイラ)
    picotool # uf2 書き込み・デバイス情報
    cmake
    ninja
    python3 # SDK のビルドスクリプトが使う
    clang-tools # clangd (nvim の LSP)
    tio # シリアルモニタ
    pico-new
    pico-build
    pico-flash
    pico-mon
  ]
  ++ pkgs.lib.optional withOpenocd pkgs.openocd-rp2040;

  # 拡張機能が ~/.pico-sdk に 2GB ダウンロードする代わりに、
  # nix store 上の SDK を指す (読み取り専用・世代管理される)。
  PICO_SDK_PATH = sdkPath;
  # 基板は Pico 1 (RP2040)。手順書の「Pico2 を選ぶと書き込めない」対策。
  PICO_BOARD = "pico";
  PICO_PLATFORM = "rp2040";

  shellHook = ''
    echo "Pico dev shell  (SDK: ${picoSdk.version}, $(arm-none-eabi-gcc -dumpversion) / arm-none-eabi)"
    echo "  pico-new <名前>  新規プロジェクト作成"
    echo "  pico-build       ビルド        (VsCode の Compile)"
    echo "  pico-flash       書き込み+実行 (VsCode の RUN)"
    echo "  pico-mon         シリアルモニタ"
    if [ -n "''${WSL_DISTRO_NAME:-}" ]; then
      echo "  (WSL2 検出: pico-flash は RPI-RP2 ドライブへのコピー、pico-mon は Windows 側で)"
    fi
  '';
}
