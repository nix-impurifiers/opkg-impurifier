# SPDX-License-Identifier: MIT
{
  pkgs,
  impurifier,
  coreSrc,
}:
let
  tool =
    name: version:
    pkgs.runCommand "${name}-${version}"
      {
        pname = name;
        inherit version;
      }
      ''
        mkdir -p $out/bin
        printf '#!${pkgs.busybox}/bin/sh\necho ${name}-${version}\n' > $out/bin/${name}
        chmod +x $out/bin/${name}
      '';
  config = pkgs.writeText "native-opkg.conf" ''
    dest root /
    arch all 1
    arch x86_64 10
    src native file:///tmp/native-feed
    option info_dir /var/lib/opkg/info
    option status_file /var/lib/opkg/status
    option lists_dir /var/lib/opkg/lists
    option lock_file /var/lib/opkg/lock
    option cache_dir /var/cache/opkg
  '';
  command = "opkg -f ${config} -o /srv/target";
  index = "rm -rf /tmp/native-feed; python3 ${../nix/repository.py} /tmp/native-feed /tmp/packages/*.ipk; ${command} update";
  install = "${index}; ${command} install native-first native-second";
  prune = "python3 ${./native-prune.py} opkg -f ${config} -o /srv/target";

in
import (coreSrc + "/tests/native-vm.nix") {
  inherit pkgs install;
  name = "opkg";
  tools = [
    pkgs.opkg
    pkgs.python3
  ];
  first = impurifier.makeNativePackages { pkg = tool "native-first" "1"; };
  second = impurifier.makeNativePackages { pkg = tool "native-second" "1"; };
  upgraded = impurifier.makeNativePackages { pkg = tool "native-first" "2"; };
  initialize = "mkdir -p /srv/target/var/lib/opkg/info /srv/target/var/lib/opkg/lists /srv/target/var/cache/opkg";
  upgrade = "${index}; ${command} --autoremove upgrade native-first";
  removeFirst = "${command} --autoremove remove native-first; ${prune}";
  removeSecond = ''
    ${command} --autoremove remove native-second
    ${prune}
    test -z "$(${command} list-installed)"
    # opkg's directory-symlink pass can leave empty parent directories.
    find /srv/target/nix/store -depth -mindepth 1 -type d -empty -delete
  '';
  verify = ''
    ${command} verify > /tmp/native-opkg-verify.log 2>&1
    test ! -s /tmp/native-opkg-verify.log
  '';
}
