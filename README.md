# opkg-impurifier

Emit native IPK packages that project Nix application closures into a shared,
GC-rooted `/opt/nix/profile`. IPK/opkg is a separate contract from Alpine APK.
Original emitter/runtime code is MIT licensed. IPKs use the original gzip/tar
envelope, accepted by both upstream opkg and OpenWrt's fork. OpenWrt's extractor
does not support the Debian `ar` envelope and can otherwise report successful
installation without extracting the payload or maintainer scripts.

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

`makeRuntimeIpk` also accepts `stateDir` (default
`"/var/lib/opkg-impurifier"`). On OpenWrt, `/var` normally points into volatile
`/tmp`, so use persistent storage, for example
`stateDir = "/opt/nix/state/opkg-impurifier";`. State, profile generations and
indirect GC roots must survive reboots together. This is explicit runtime
policy; the emitter does not replace OpenWrt's `/var` layout.

`makeRepository { packages = [ runtime app.offline ]; }` emits `Packages`,
`Packages.gz`, exact SHA256 package hashes and canonical native filenames. It
rejects collisions. Copy it to a writable publication directory and run its
`sign-repository REPOSITORY PRIVATE-KEY` helper with native `usign` on PATH.
Private keys stay outside the Nix store. Install the publisher's public key
through your normal trusted channel with `opkg-key add`, then add a native
`src/gz` feed. Signing authenticates the uncompressed index; opkg checks each
package against its signed index hash. Select distinct releases or channels
for net/offline repository transport changes.

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
complete OpenEmbedded boot. A separate VM runs the unmodified opkg fork, usign, opkg-key and native database
from the official OpenWrt 24.10.4 x86_64 root filesystem. It checks native signed
feed verification, rejection and deletion of manipulated indexes, signed-index
SHA256 package corruption rejection, real provider dependencies, net
failure/offline recovery, conffiles/upgrades, ordinary-user launch and removal/GC.
The fixture selects persistent state under `/opt/nix` and shares real Nix state
and roots with its NixOS host. This covers application commands; procd service
integration, complete OpenWrt boot, router hardware and other architectures are
separate coverage. Native opkg update can exit zero after rejecting a feed's
signature; inspect verification diagnostics and list state, not exit status
alone.

The exported `runtimeVersion` follows the pinned core source timestamp. Application dependencies require that runtime version or newer, rather than accepting every engine as `0.1.0`. This supports ordinary native engine upgrades without project release tags. Consumer-provided Nix dependency expressions remain independent of the engine's own native version.
