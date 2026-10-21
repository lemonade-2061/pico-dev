# Raspberry Pi Pico (RP2040) の開発環境を1リポジトリで完結させたもの。
#
# 使う側 (friend):
#   nix develop github:lemonade-2061/pico-dev
#   pico-new blink && cd blink && pico-build && pico-flash
#
# NixOS で udev ルール等も入れる場合:
#   inputs.pico-dev.url = "github:lemonade-2061/pico-dev";
#   imports = [ inputs.pico-dev.nixosModules.default ];
#   programs.pico-dev = { enable = true; users = [ "yourname" ]; };
{
  description = "Raspberry Pi Pico (RP2040) 開発環境 — devShell + udev 設定";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

  outputs =
    { self, nixpkgs }:
    let
      # Pico の SDK/ツールチェーンが揃うのは Linux のみ想定 (macOS は未検証)。
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems =
        f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      devShells = forAllSystems (pkgs: rec {
        default = import ./shell.nix { inherit pkgs; };
        # `nix develop ...#pico` でも入れるように別名を残す
        pico = default;
      });

      # root 権限が必要な部分 (udev ルール / シリアルのグループ)
      nixosModules.default = import ./module.nix;
      nixosModules.pico-dev = self.nixosModules.default;
    };
}
