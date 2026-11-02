# SPDX-License-Identifier: MIT
{ pkgs, coreSrc }:
let
  inherit (pkgs) lib;
  core = import (coreSrc + "/nix") {
    inherit pkgs;
    namespace = "opkg-impurifier";
    sourceInfo = coreSrc;
  };
  architecture =
    if pkgs.stdenv.hostPlatform.isx86_64 then
      "x86_64"
    else if pkgs.stdenv.hostPlatform.isAarch64 then
      "aarch64"
    else
      throw "opkg-impurifier: unsupported target architecture";
  dependency = value: builtins.match "[A-Za-z0-9 .,+|():<>=~_-]+" value != null;
  buildIpk =
    {
      name,
      version,
      release ? "1",
      architecture ? "all",
      payload,
      description ? "Impurified Nix application",
      license ? "LicenseRef-Unknown",
      dependencies ? [ ],
      provides ? [ ],
      conflicts ? [ ],
      replaces ? [ ],
      configPaths ? [ ],
      scripts ? { },
    }:
    assert lib.assertMsg (builtins.match "[a-z0-9][a-z0-9+.-]+" name != null) "invalid IPK name";
    assert lib.assertMsg (
      builtins.match "[0-9][A-Za-z0-9.+:~_-]*" version != null && builtins.match "[0-9]+" release != null
    ) "invalid IPK version or release";
    assert lib.assertMsg (
      builtins.match "[A-Za-z0-9_.+-]+" architecture != null
      && builtins.match "[^\n\r]+" description != null
      && builtins.match "[^\n\r]+" license != null
    ) "invalid IPK metadata";
    assert lib.assertMsg (lib.all dependency (
      dependencies ++ provides ++ conflicts ++ replaces
    )) "invalid IPK dependency";
    assert lib.assertMsg (lib.all (
      kind:
      lib.elem kind [
        "preinst"
        "postinst"
        "prerm"
        "postrm"
      ]
    ) (builtins.attrNames scripts)) "invalid IPK maintainer script";
    pkgs.runCommand "${name}_${version}-${release}_${architecture}.ipk"
      {
        nativeBuildInputs = [
          pkgs.binutils
          pkgs.gnutar
          pkgs.gzip
        ];
        __structuredAttrs = true;
        unsafeDiscardReferences.out = true;
      }
      ''
        set -euo pipefail
        mkdir root control
        cp -r ${payload}/. root/
        chmod -R u+w root
        cat > control/control <<'CONTROL'
        Package: ${name}
        Version: ${version}-${release}
        Architecture: ${architecture}
        Maintainer: Nix Impurifiers <root@localhost>
        Description: ${description}
        License: ${license}
        ${lib.optionalString (dependencies != [ ]) "Depends: ${lib.concatStringsSep ", " dependencies}"}
        ${lib.optionalString (provides != [ ]) "Provides: ${lib.concatStringsSep ", " provides}"}
        ${lib.optionalString (conflicts != [ ]) "Conflicts: ${lib.concatStringsSep ", " conflicts}"}
        ${lib.optionalString (replaces != [ ]) "Replaces: ${lib.concatStringsSep ", " replaces}"}
        CONTROL
        # A blank control line ends the package stanza in opkg.
        sed -i '/^[[:space:]]*$/d' control/control
        echo "Installed-Size: $(du --apparent-size -sk root | cut -f1)" >> control/control
        ${lib.optionalString (configPaths != [ ]) ''
          cat > control/conffiles <<'CONFFILES'
          ${lib.concatStringsSep "\n" configPaths}
          CONFFILES
        ''}
        ${lib.concatStringsSep "\n" (
          lib.mapAttrsToList (kind: source: ''
            install -m755 ${lib.escapeShellArg (toString source)} control/${kind}
          '') scripts
        )}
        printf '2.0\n' > debian-binary
        tar -C control --sort=name --mtime=@1 --owner=0 --group=0 --numeric-owner -czf control.tar.gz .
        tar -C root --sort=name --mtime=@1 --owner=0 --group=0 --numeric-owner -czf data.tar.gz .
        ar crD "$out" debian-binary control.tar.gz data.tar.gz
      '';
  queue = pkgs.writeText "opkg-impurifier-activate" ''
    #!/bin/sh
    set -eu
    if [ "''${PKG_ROOT:-/}" != / ] || [ -n "''${IPKG_INSTROOT:-}" ]; then
      echo 'opkg-impurifier: target activation cannot run against an offline root' >&2
      exit 1
    fi
    if [ -n "''${OPKG_INTERCEPT_DIR:-}" ] && [ -d "$OPKG_INTERCEPT_DIR" ]; then
      printf '#!/bin/sh\nexec /usr/sbin/nix-profile-engine reconcile\n' > "$OPKG_INTERCEPT_DIR/nix-profile-engine"
      chmod 755 "$OPKG_INTERCEPT_DIR/nix-profile-engine"
    else
      exec /usr/sbin/nix-profile-engine reconcile
    fi
  '';
  postinst = pkgs.writeText "impurifier-postinst" ''
    #!/bin/sh
    set -eu
    exec /usr/sbin/opkg-impurifier-activate
  '';
  postrm = pkgs.writeText "impurifier-postrm" ''
    #!/bin/sh
    set -eu
    case "$1" in
      remove|disappear) /usr/sbin/opkg-impurifier-activate ;;
    esac
  '';
  makeIpk =
    args@{
      pkg,
      release ? "1",
      hostDependencies ? [ "systemd" ],
      ...
    }:
    let
      payload = core.makePayload (
        builtins.removeAttrs args [
          "release"
          "hostDependencies"
        ]
      );
    in
    buildIpk {
      name = payload.name;
      inherit (payload) version description configPaths;
      inherit payload release architecture;
      dependencies = [
        "opkg-impurifier (>= ${core.runtimeVersion})"
      ]
      ++ lib.optionals (payload.hostEnabled || (args.hostDependencies or null) != null) hostDependencies;
      scripts = { inherit postinst postrm; };
    };
  makeRuntimeIpk =
    {
      nixDependency ? "nix",
      pythonDependency ? "python3",
    }:
    let
      payload = pkgs.runCommand "opkg-impurifier-runtime-payload" { } ''
        mkdir -p $out
        cp -r ${core.makeRuntimeTree { }}/. $out/
        chmod -R u+w $out
        install -m755 ${queue} $out/usr/sbin/opkg-impurifier-activate
      '';
    in
    buildIpk {
      name = "opkg-impurifier";
      version = core.runtimeVersion;
      inherit payload;
      description = "Native package intent projected into a Nix profile";
      license = "MIT";
      dependencies = [
        nixDependency
        pythonDependency
      ];
      scripts = { inherit postinst; };
    };
in
{
  inherit (core)
    engine
    offlineCache
    unit
    runtimeVersion
    ;
  inherit buildIpk makeIpk makeRuntimeIpk;
  runtimeIpk = makeRuntimeIpk { };
  makeNetIpk = args: makeIpk (args // { offline = false; });
  makeOfflineIpk = args: makeIpk (args // { offline = true; });
  makePackage = args: {
    net = makeIpk (args // { offline = false; });
    offline = makeIpk (args // { offline = true; });
  };
}
