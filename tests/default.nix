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
        ar p ${net} debian-binary | grep '^2.0$'
        ar p ${net} control.tar.gz | tar xzOf - ./control | grep '^Package: hello$'
        ar p ${
          impurifier.makeRuntimeIpk { nixDependency = "custom-nix-provider"; }
        } control.tar.gz | tar xzOf - ./control | grep '^Depends: custom-nix-provider, python3$'
        test "$(wc -l < ${closure}/store-paths)" = 2
        touch $out
      '';
  vm = import ./vm.nix {
    inherit pkgs impurifier;
    hardwareFixture = import (coreSrc + "/tests/hardware-fixture.nix") { inherit pkgs; };
  };
}
