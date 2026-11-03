# SPDX-License-Identifier: MIT
{
  pkgs,
  impurifier,
  coreSrc,
}:
let
  net = impurifier.makeNetIpk { pkg = pkgs.hello; };
  offline = impurifier.makeOfflineIpk { pkg = pkgs.hello; };
  closure = pkgs.closureInfo {
    rootPaths = [
      net
      offline
    ];
  };
in
{
  native-vm = import ./native-vm.nix { inherit pkgs impurifier coreSrc; };
  openwrt-vm = import ./openwrt-vm.nix { inherit pkgs impurifier; };
  unit = impurifier.unit;
  emitter =
    pkgs.runCommand "opkg-impurifier-contract"
      {
        nativeBuildInputs = [
          pkgs.binutils
          pkgs.gnutar
        ];
      }
      ''
        tar xzOf ${net} debian-binary | grep '^2.0$'
        tar xzOf ${net} control.tar.gz | tar xzOf - control | grep '^Package: hello$'
        tar xzOf ${
          impurifier.makeRuntimeIpk { nixDependency = "custom-nix-provider"; }
        } control.tar.gz | tar xzOf - control | grep '^Depends: custom-nix-provider, python3$'
        test "$(wc -l < ${closure}/store-paths)" = 2
        touch $out
      '';
  vm = import ./vm.nix {
    inherit pkgs impurifier;
    hardwareFixture = import (coreSrc + "/tests/hardware-fixture.nix") { inherit pkgs; };
  };
}
