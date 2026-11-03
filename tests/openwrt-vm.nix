# SPDX-License-Identifier: MIT
{
  pkgs,
  impurifier,
  bundled ? false,
}:
let
  runtime = impurifier.makeRuntimeIpk { stateDir = "/opt/nix/state/opkg-impurifier"; };
  rootfs = pkgs.fetchurl {
    url = "https://downloads.openwrt.org/releases/24.10.4/targets/x86/64/openwrt-24.10.4-x86-64-rootfs.tar.gz";
    hash = "sha256-5/irhO71XH6yNJLeewUX28I/vtqkq7toD+ZHIMMJ3AM=";
  };
  tool =
    version:
    pkgs.runCommand "wrt-tool-${version}"
      {
        pname = "wrt-tool";
        inherit version;
      }
      ''
        mkdir -p $out/bin
        printf '#!${pkgs.busybox}/bin/sh\necho ${version}\n' > $out/bin/wrt-tool
        chmod +x $out/bin/wrt-tool
      '';
  app =
    offline: version:
    impurifier.makeIpk {
      pkg = tool version;
      inherit offline;
      release = if offline then "2" else "1";
      hostDependencies = [ ];
      configFiles."/etc/wrt-tool.conf" = pkgs.writeText "wrt-tool.conf" "version=${version}\n";
    };
  provider = impurifier.buildIpk {
    name = "fixture-native-runtime";
    version = "1";
    provides = [
      "nix"
      "python3"
    ];
    payload = pkgs.runCommand "wrt-runtime-provider" { } ''
      mkdir -p $out/usr/bin
      ${
        if bundled then
          ''
            printf '#!/bin/sh\nexit 1\n' > $out/usr/bin/nix-store
            chmod 755 $out/usr/bin/nix-store
          ''
        else
          "ln -s ${pkgs.nix}/bin/nix-store $out/usr/bin/nix-store"
      }
      ln -s ${pkgs.python3}/bin/python3 $out/usr/bin/python3
    '';
  };
  repository =
    offline: version:
    impurifier.makeRepository {
      packages = [
        provider
        runtime
        (app offline version)
      ];
    };
in
pkgs.testers.runNixOSTest {
  name = "opkg-impurifier-openwrt";
  globalTimeout = 180;
  requiredFeatures = {
    kvm = false;
    devnet = false;
  };
  nodes.machine = { lib, ... }: {
    virtualisation.qemu.package = lib.mkForce pkgs.qemu;
    virtualisation.qemu.forceAccel = false;
    virtualisation.memorySize = 1024;
    virtualisation.useNixStoreImage = true;
    virtualisation.writableStore = true;
    documentation.enable = false;
    environment.systemPackages = with pkgs; [
      nix
      python3
      gnutar
    ];
    nix.settings.substituters = lib.mkForce [ ];
  };
  testScript = ''
    start_all()
    machine.wait_for_unit("multi-user.target")
    machine.succeed("mkdir -p /wrt; tar -xzf ${rootfs} -C /wrt; mkdir -p /wrt/nix /wrt/proc /wrt/dev /wrt/packages /wrt/opt/nix /wrt/var/lib/opkg-impurifier /opt/nix /var/lib/opkg-impurifier")
    machine.succeed("mount --rbind /nix /wrt/nix; mount --rbind /dev /wrt/dev; mount -t proc proc /wrt/proc; mount --bind /opt/nix /wrt/opt/nix; mount --bind /var/lib/opkg-impurifier /wrt/var/lib/opkg-impurifier")
    machine.succeed("mkdir -p /wrt/etc/nix /wrt/var/lock /wrt/var/opkg-lists; printf 'substituters =\\nbuilders =\\nbuild-users-group =\\n' > /wrt/etc/nix/nix.conf; : > /wrt/etc/opkg/distfeeds.conf")
    machine.succeed("cp -r ${repository false "1"} /wrt/repo-net; cp -r ${repository true "1"} /wrt/repo-1; cp -r ${repository true "2"} /wrt/repo-2; chmod -R u+w /wrt/repo-net /wrt/repo-1 /wrt/repo-2")
    root = "chroot /wrt /usr/bin/env PATH=/usr/sbin:/usr/bin:/sbin:/bin HOME=/root "
    machine.succeed(root + "usign -G -s /root/feed.key -p /root/feed.pub; fingerprint=$(chroot /wrt /usr/bin/usign -F -p /root/feed.pub); cp /wrt/root/feed.pub /wrt/etc/opkg/keys/$fingerprint")
    machine.succeed(root + "sh -c 'for repo in /repo-net /repo-1 /repo-2; do $repo/sign-repository $repo /root/feed.key; done'")
    machine.succeed("cp -r /wrt/repo-1/. /wrt/packages/; printf 'src/gz impurifier file:///packages\\n' > /wrt/etc/opkg/customfeeds.conf; systemctl stop dhcpcd; ip link set eth0 down")
    command = "setsid --wait timeout --foreground -k 2s 45s " + root + "/bin/opkg "
    print(machine.succeed(command + "--version"))
    assert "Signature check passed" in machine.succeed(command + "update"), "native signature verification missing"
    with subtest("signed feed rejects modified metadata"):
        machine.succeed("cp /wrt/packages/Packages.gz /index-good; python3 -c \"import gzip; from pathlib import Path; p=Path('/wrt/packages/Packages.gz'); p.write_bytes(gzip.compress(gzip.decompress(p.read_bytes()).replace(b'Package: wrt-tool', b'Package: tampered-tool')))\"")
        code, output = machine.execute(command + "update 2>&1")
        assert "Signature check failed" in output and "timeout" not in output.lower(), output
        machine.fail(root + "opkg-key verify /packages/Packages.sig /packages/Packages.gz")
        machine.fail("test -e /wrt/var/opkg-lists/impurifier")
        machine.succeed("cp /index-good /wrt/packages/Packages.gz")
        machine.succeed(command + "update")
    with subtest("signed feed checks package SHA256 before installation"):
        machine.succeed("cp /wrt/packages/wrt-tool_1-2_x86_64.ipk /package-good; python3 -c \"from pathlib import Path; p=Path('/wrt/packages/wrt-tool_1-2_x86_64.ipk'); b=bytearray(p.read_bytes()); b[-1]^=1; p.write_bytes(b)\"")
        code, output = machine.execute(command + "install wrt-tool 2>&1")
        assert code != 0 and any(word in output.lower() for word in ["checksum", "sha256", "corrupt"]), output
        machine.fail("test -e /opt/nix/profile/bin/wrt-tool")
        machine.succeed("cp /package-good /wrt/packages/wrt-tool_1-2_x86_64.ipk")
    machine.succeed("rm -f /wrt/packages/*; cp -r /wrt/repo-net/. /wrt/packages/")
    machine.succeed(command + "update")
    code, output = machine.execute(command + "install wrt-tool 2>&1")
    print(output)
    assert "nix-profile-engine:" in output, output
    machine.fail("test -e /opt/nix/profile/bin/wrt-tool")
    machine.succeed("rm -f /wrt/packages/*; cp -r /wrt/repo-1/. /wrt/packages/")
    machine.succeed(command + "update")
    machine.succeed(command + "upgrade wrt-tool")
    machine.succeed("test $(/opt/nix/profile/bin/wrt-tool) = 1; echo administrator > /wrt/etc/wrt-tool.conf")
    machine.succeed("rm -f /wrt/packages/*; cp -r /wrt/repo-2/. /wrt/packages/")
    machine.succeed(command + "update")
    machine.succeed(command + "upgrade wrt-tool")
    machine.succeed("test $(/opt/nix/profile/bin/wrt-tool) = 2; grep administrator /wrt/etc/wrt-tool.conf; chroot --userspec=65534:65534 /wrt /opt/nix/profile/bin/wrt-tool | grep '^2$'; nix-store --gc")
    machine.succeed(command + "remove wrt-tool")
    machine.fail("test -e /opt/nix/profile/bin/wrt-tool")
    machine.succeed(root + "/usr/sbin/nix-profile-engine prune --keep 0")
    machine.succeed(command + "remove opkg-impurifier")
    machine.succeed("nix-store --gc")
    machine.fail("test -e ${builtins.unsafeDiscardStringContext (toString (tool "2"))}")
  '';
}
