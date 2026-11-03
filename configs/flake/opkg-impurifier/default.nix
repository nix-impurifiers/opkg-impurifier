# SPDX-License-Identifier: MIT
{ ... }:
{ lib, inputs, ... }:
{
  flake.lib = lib.mkForce {
    opkg-impurifier =
      { pkgs }:
      import ../../../nix {
        inherit pkgs;
        coreSrc = inputs.impurifier;
        sourceInfo = inputs.self;
      };
  };
  perSystem =
    { pkgs, ... }:
    let
      impurifier = import ../../../nix {
        inherit pkgs;
        coreSrc = inputs.impurifier;
        sourceInfo = inputs.self;
      };
      bundle = {
        bundledNixStore = "${
          import (inputs.impurifier + "/tests/static-nix.nix") { inherit pkgs; }
        }/bin/nix-store";
        bundledNixNotices = [ "${pkgs.nix.src}/COPYING" ];
      };
      bundledImpurifier = impurifier // {
        runtimeIpk = impurifier.makeRuntimeIpk bundle;
        makeRuntimeIpk = args: impurifier.makeRuntimeIpk (args // bundle);
      };
    in
    {
      packages = {
        default = impurifier.engine;
        engine = impurifier.engine;
        runtime-ipk = impurifier.runtimeIpk;
        hello-net-ipk = impurifier.makeNetIpk { pkg = pkgs.hello; };
        hello-offline-ipk = impurifier.makeOfflineIpk { pkg = pkgs.hello; };
      };
      formatter = pkgs.nixfmt-tree;
      checks =
        (import ../../../tests {
          inherit pkgs impurifier;
          coreSrc = inputs.impurifier;
        })
        // {
          bundled-vm = import ../../../tests/vm.nix {
            inherit pkgs;
            hardwareFixture = import (inputs.impurifier + "/tests/hardware-fixture.nix") { inherit pkgs; };
            impurifier = bundledImpurifier;
            bundled = true;
          };
          bundled-openwrt-vm = import ../../../tests/openwrt-vm.nix {
            inherit pkgs;
            impurifier = bundledImpurifier;
            bundled = true;
          };
        };
    };
}
