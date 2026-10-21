# Raspberry Pi Pico 開発の「root 権限が必要な部分」だけを受け持つ NixOS モジュール。
# devShell (shell.nix) 側では扱えないので分けてある。
#
#   imports = [ inputs.pico-dev.nixosModules.default ];
#   programs.pico-dev = { enable = true; users = [ "lemonade" ]; };
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.pico-dev;
in
{
  options.programs.pico-dev = {
    enable = lib.mkEnableOption "Raspberry Pi Pico 開発用の udev ルールとシリアル権限";

    users = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "lemonade" ];
      description = ''
        dialout / plugdev グループに入れるユーザー。シリアルモニタ (pico-mon が
        開く /dev/ttyACM*) は root:dialout 660 なので、ここに書かないと読めない。
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # picotool は Pico を USB の生デバイスとして開く。BOOTSEL 中の RP2 ブートROM が
    # 見せる PICOBOOT インタフェース (マスストレージとは別のインタフェース) と、
    # 実行中プログラムの reset インタフェース (pico_stdio_usb) が対象。
    # nixpkgs の picotool は 60-picotool.rules を同梱しているのでそれを登録する。
    # openocd-rp2040 側のルールは Picoprobe/debugprobe 経由の SWD デバッグ用。
    services.udev.packages = [
      pkgs.picotool
      pkgs.openocd-rp2040
    ];

    # 上のルールは TAG+="uaccess" (ログイン中のユーザーに ACL を付与) と
    # GROUP="plugdev" を併記している。uaccess だけで用は足りるが、NixOS には
    # plugdev グループが存在しないため、放っておくと udev が毎回
    # 「Unknown group 'plugdev'」を吐く。グループを作って解消しておく。
    users.groups.plugdev = { };

    users.users = lib.genAttrs cfg.users (_: {
      extraGroups = [
        "dialout"
        "plugdev"
      ];
    });

    # 補足: BOOTSEL モードの Pico は USB マスストレージ (RPI-RP2) としても現れる。
    # picotool は別インタフェースを使うので自動マウントと干渉しない。.uf2 を
    # ドラッグ&ドロップして書き込む手も残るため、自動マウントは無効化していない。
  };
}
