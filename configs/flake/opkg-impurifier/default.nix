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
      };
  };
  perSystem =
    { pkgs, ... }:
    let
      impurifier = import ../../../nix {
        inherit pkgs;
        coreSrc = inputs.impurifier;
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
      checks = import ../../../tests {
        inherit pkgs impurifier;
        coreSrc = inputs.impurifier;
      };
    };
}
