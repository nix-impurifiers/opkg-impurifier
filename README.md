# opkg-impurifier

Emit native IPK packages that project Nix application closures into a shared,
GC-rooted `/opt/nix/profile`. IPK/opkg is a separate contract from Alpine APK.
Original emitter/runtime code is MIT licensed.

```nix
let impurifier = inputs.opkg-impurifier.lib.opkg-impurifier { inherit pkgs; };
in impurifier.makePackage { pkg = pkgs.hello; }
```

`makePackage` returns `net` and `offline`. Individual constructors are `makeIpk`,
`makeNetIpk`, and `makeOfflineIpk`. Both flavors have the same native package
identity and version. Select transport explicitly when installing local files:

```sh
sudo opkg --force-reinstall install ./hello-offline.ipk
sudo opkg --force-reinstall install ./hello-net.ipk
sudo opkg remove hello
```

Export the two Nix artifacts under distinct local filenames. A repository needs
separate flavor channels or distinct releases; two artifacts cannot occupy one
native repository filename. Net packages use administrator-configured Nix
caches. Offline packages carry the full closure cache, select only that cache,
and disable remote builders during import. Neither changes global cache trust.

`makeRuntimeIpk { nixDependency = "nix"; pythonDependency = "python3"; }` makes
native runtime requirements consumer policy. The runtime requires working Nix
and Python; the impure Nix provider/installer remains deferred, not excluded.
The runtime archive contains the engine's MIT license notice.

`configFiles`, `files`, `users`, `directories`, `systemd`, `openrc`, `lifecycle`,
and `hardware` use the shared core API. Configurations belong to native opkg
conffile handling. Service host dependencies default to `[ "systemd" ]`; consumers
using OpenRC select its native dependencies. This does not claim OpenWrt procd
or every embedded image's supervisor has been implemented.

## Native transaction behavior

Application post-install scripts enqueue one callback in `OPKG_INTERCEPT_DIR`
when opkg is configuring a transaction. Without that context the helper runs
reconciliation immediately. Removal reconciles per package; opkg does not expose
the same transaction-wide removal/file-trigger contract as dpkg or RPM.

**opkg 0.8 discards deferred intercept-script exit statuses.** A native command
can succeed while profile activation failed. The engine prints diagnostics and
preserves the old profile on fetch/composition failure. After correcting cache
availability or installing an offline artifact, run:

```sh
sudo /usr/sbin/nix-profile-engine reconcile
sudo /usr/sbin/nix-profile-engine status
sudo /usr/sbin/nix-profile-engine prune --keep 2
```

Service/lifecycle failure may occur after publication and retains retry state.
Hooks must be idempotent. Forced offline-root maintainer-script execution is
rejected rather than activating the build host. Image-time activation belongs
to the separate image adapter.

There is no claim of automatic library-directory triggers in opkg. Native driver
packages can call `/usr/sbin/opkg-impurifier-activate` after changing selected
libraries; it uses the same configuration batching. Otherwise explicitly
reconcile after an upstream driver upgrade. Snapshots retain old user-space
libraries but cannot establish GPU ABI or kernel-module compatibility.

## Verification

`nix flake check -L` runs engine contracts, native archive/dependency metadata and
reference-free closure checks, and a QEMU VM using actual opkg/Nix/systemd. The
network-disabled VM checks fetch failure, offline reinstall, edited conffiles,
upgrades, native install batching, lifecycle hooks, account/directory ownership,
administrator service intent, removal, cooperating driver upgrades and GC.
It uses NixOS with mutable native-style unit directories, not an OpenWrt or
complete OpenEmbedded boot. OpenWrt's opkg fork remains separate compatibility
coverage rather than an assumed equivalent of the tested upstream version.
