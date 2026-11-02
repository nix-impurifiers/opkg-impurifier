# SPDX-License-Identifier: MIT
{
  pkgs,
  impurifier,
  hardwareFixture,
}:
let
  tool =
    version:
    pkgs.runCommand "ipk-tool-${version}"
      {
        pname = "ipk-tool";
        inherit version;
      }
      ''
        mkdir -p $out/bin
        printf '#!${pkgs.busybox}/bin/sh\necho ${version}\n' > $out/bin/ipk-tool
        chmod +x $out/bin/ipk-tool
      '';
  app =
    offline: version:
    impurifier.makeIpk {
      pkg = tool version;
      inherit offline;
      configFiles."/etc/ipk-tool.conf" = pkgs.writeText "ipk-config" "version=${version}\n";
    };
  daemon =
    version:
    pkgs.runCommand "ipk-service-${version}"
      {
        pname = "ipk-service";
        inherit version;
      }
      ''
        mkdir -p $out/bin
        cat > $out/bin/ipk-service <<'SCRIPT'
        #!${pkgs.busybox}/bin/sh
        echo ${version} > /var/lib/ipk-service/version
        exec ${pkgs.busybox}/bin/sleep infinity
        SCRIPT
        chmod +x $out/bin/ipk-service
      '';
  service =
    version:
    impurifier.makeOfflineIpk {
      pkg = daemon version;
      users.ipk-service = { };
      directories."/var/lib/ipk-service" = {
        owner = "ipk-service:ipk-service";
        mode = "0750";
      };
      lifecycle = {
        onInstall = ''
          /usr/bin/python3 -c "import pwd; pwd.getpwnam('ipk-service')"
          test -x /opt/nix/profile/bin/ipk-service
          echo initialized > /var/lib/ipk-service/initialized
        '';
        onUpgrade = "echo ${version} > /var/lib/ipk-service/migrated";
      };
      systemd.unit = pkgs.writeText "ipk-service.service" ''
        [Service]
        Type=exec
        User=ipk-service
        ExecStart=/opt/nix/profile/bin/ipk-service
        [Install]
        WantedBy=multi-user.target
      '';
    };
  provider = impurifier.buildIpk {
    name = "vm-runtime";
    version = "1";
    provides = [
      "nix"
      "python3"
      "systemd"
    ];
    payload = pkgs.runCommand "opkg-runtime-provider" { } ''
      mkdir -p $out/usr/share/impurifier-vm
      echo preinstalled > $out/usr/share/impurifier-vm/runtime
    '';
  };
  hostDriver =
    version:
    impurifier.buildIpk {
      name = "impurifier-host-driver";
      inherit version;
      architecture = "x86_64";
      payload = hardwareFixture.driver version;
      scripts.postinst = pkgs.writeText "cooperating-native-driver-postinst" ''
        #!/bin/sh
        exec /usr/sbin/opkg-impurifier-activate
      '';
    };
  hardware = impurifier.makeOfflineIpk {
    hostDependencies = [ "impurifier-host-driver" ];
    pkg = hardwareFixture.tool;
    inherit (hardwareFixture) hardware;
  };
in
pkgs.testers.runNixOSTest {
  name = "opkg-impurifier";
  requiredFeatures = {
    kvm = false;
    devnet = false;
  };
  nodes.machine = { lib, ... }: {
    virtualisation.memorySize = 2048;
    virtualisation.useNixStoreImage = true;
    virtualisation.writableStore = true;
    virtualisation.qemu.package = lib.mkForce pkgs.qemu;
    virtualisation.qemu.forceAccel = false;
    environment.systemPackages = [
      pkgs.opkg
      pkgs.nix
      pkgs.python3
    ];
    systemd.tmpfiles.rules = [
      "d /usr/bin 0755 root root -"
      "L+ /usr/bin/python3 - - - - ${pkgs.python3}/bin/python3"
      "L+ /usr/bin/nix-store - - - - ${pkgs.nix}/bin/nix-store"
      "L+ /usr/bin/systemctl - - - - ${pkgs.systemd}/bin/systemctl"
      "L+ /usr/bin/systemd-sysusers - - - - ${pkgs.systemd}/bin/systemd-sysusers"
      "L+ /usr/bin/systemd-tmpfiles - - - - ${pkgs.systemd}/bin/systemd-tmpfiles"
    ];
    environment.etc."opkg.conf".text = ''
      dest root /
      arch all 1
      arch x86_64 10
      option info_dir /var/lib/opkg/info
      option status_file /var/lib/opkg/status
      option lists_dir /var/lib/opkg/lists
      option lock_file /var/lib/opkg/lock
      option cache_dir /var/cache/opkg
    '';
    nix.settings.substituters = lib.mkForce [ ];
  };
  testScript = ''
    start_all()
    machine.wait_for_unit("multi-user.target")
    machine.succeed("mkdir -p /var/lib/opkg/info /var/lib/opkg/lists /var/cache/opkg /tmp/packages")
    machine.succeed("cp ${app false "1"} /tmp/packages/net1.ipk; cp ${app true "1"} /tmp/packages/offline1.ipk; cp ${app true "2"} /tmp/packages/offline2.ipk; cp ${service "1"} /tmp/packages/service1.ipk; cp ${service "2"} /tmp/packages/service2.ipk; cp ${hostDriver "1"} /tmp/packages/driver1.ipk; cp ${hostDriver "2"} /tmp/packages/driver2.ipk; cp ${hardware} /tmp/packages/hardware.ipk")
    machine.succeed("cp -rL /etc/systemd/system /tmp/systemd-system; chmod -R u+w /tmp/systemd-system; rm /etc/systemd/system; mv /tmp/systemd-system /etc/systemd/system; systemctl daemon-reload")
    machine.succeed("systemctl stop dhcpcd; ip link set eth0 down")
    opkg = "opkg -f /etc/opkg.conf "
    install = opkg + "--force-reinstall --force-downgrade install "
    machine.succeed(install + "${provider} ${impurifier.runtimeIpk}")
    machine.fail("test -e ${builtins.unsafeDiscardStringContext (toString (tool "1"))}")
    with subtest("deferred fetch failure preserves the previous profile"):
        before = machine.succeed("readlink /opt/nix/profile").strip()
        code, output = machine.execute(install + "/tmp/packages/net1.ipk 2>&1")
        assert "nix-profile-engine:" in output, output
        assert machine.succeed("readlink /opt/nix/profile").strip() == before
    with subtest("offline reinstall recovers with no network"):
        machine.succeed(install + "/tmp/packages/offline1.ipk")
        machine.succeed("test $(/opt/nix/profile/bin/ipk-tool) = 1")
    with subtest("native conffiles survive transport switches and upgrades"):
        machine.succeed("echo local > /etc/ipk-tool.conf")
        machine.succeed(install + "/tmp/packages/net1.ipk")
        machine.succeed("grep local /etc/ipk-tool.conf")
        machine.succeed(install + "/tmp/packages/offline2.ipk")
        machine.succeed("grep local /etc/ipk-tool.conf; test $(/opt/nix/profile/bin/ipk-tool) = 2")
    with subtest("native configuration interception batches package activation"):
        output = machine.succeed(install + "${
          impurifier.makeOfflineIpk {
            pkg = pkgs.hello;
            name = "batch-a";
            version = "1";
          }
        } ${
          impurifier.makeOfflineIpk {
            pkg = pkgs.hello;
            name = "batch-b";
            version = "1";
          }
        }")
        assert output.count("activated ") == 1, output
        machine.succeed("/opt/nix/profile/bin/hello | grep Hello")
        machine.succeed(opkg + "remove batch-a batch-b")
    with subtest("native service ownership and lifecycle preserve administrator intent"):
        machine.succeed(install + "/tmp/packages/service1.ipk")
        machine.wait_for_unit("ipk-service.service")
        machine.wait_until_succeeds("grep '^1$' /var/lib/ipk-service/version")
        machine.succeed("grep initialized /var/lib/ipk-service/initialized; test $(stat -c %U /var/lib/ipk-service) = ipk-service")
        machine.succeed(install + "/tmp/packages/service2.ipk")
        machine.wait_until_succeeds("grep '^2$' /var/lib/ipk-service/version")
        machine.succeed("grep '^2$' /var/lib/ipk-service/migrated")
        machine.succeed("systemctl disable --now ipk-service.service")
        machine.succeed(install + "/tmp/packages/service1.ipk")
        machine.fail("systemctl is-active --quiet ipk-service.service")
        machine.fail("systemctl is-enabled --quiet ipk-service.service")
        machine.succeed("systemctl enable --now ipk-service.service")
        machine.succeed(opkg + "remove ipk-service")
        machine.fail("systemctl is-active --quiet ipk-service.service")
    with subtest("cooperating native drivers request snapshot refresh"):
        code, output = machine.execute(install + "/tmp/packages/hardware.ipk 2>&1")
        assert code != 0 and "impurifier-host-driver" in output, output
        machine.succeed(install + "/tmp/packages/driver1.ipk /tmp/packages/hardware.ipk")
        machine.succeed("/opt/nix/profile/bin/hardware-tool | grep '^1$'")
        machine.succeed(install + "/tmp/packages/driver2.ipk")
        machine.succeed("/opt/nix/profile/bin/hardware-tool | grep '^2$'")
        machine.succeed(opkg + "remove hardware-tool")
        machine.succeed(opkg + "remove impurifier-host-driver")
    with subtest("offline-root maintainer scripts cannot activate the host"):
        before = machine.succeed("readlink /opt/nix/profile").strip()
        code, output = machine.execute(opkg + "--offline-root /tmp/foreign-root --force-postinstall --force-depends install /tmp/packages/offline1.ipk 2>&1")
        assert "target activation cannot run against an offline root" in output, output
        assert machine.succeed("readlink /opt/nix/profile").strip() == before
    with subtest("GC and native removal release profile intent"):
        machine.succeed("nix-store --gc; test $(/opt/nix/profile/bin/ipk-tool) = 2")
        machine.succeed(opkg + "remove ipk-tool")
        machine.fail("test -e /opt/nix/profile/bin/ipk-tool")
        machine.succeed("grep local /etc/ipk-tool.conf")
        machine.succeed("/usr/sbin/nix-profile-engine prune --keep 0; nix-store --gc; test -d /opt/nix/profile")
  '';
}
