# Testing

`nix flake check -L` runs shared engine contracts, emitter metadata/closure checks,
and actual opkg 0.8 transactions in a QEMU NixOS VM. Offline tests disable the
network and assert the application closure was initially absent. Test failure
and recovery explicitly: opkg discards deferred callback status, so native exit
success does not establish activation success. Installation batches; removal
reconciles per package. See the README for covered operations and limitations.

The fixture provides actual preinstalled Nix/Python/systemd with a native
inventory provider. A separate VM runs the official OpenWrt 24.10.4 userspace,
its actual opkg fork and native usign/opkg-key verification against emitted
signed feeds. It checks manipulated index deletion, package SHA256 rejection,
net failure/offline recovery, upgrades/configuration, persistent state selection,
ordinary-user launch and removal/GC. Neither fixture is a Nix installer or a
complete OpenWrt/procd boot test. Driver fixtures explicitly request reconciliation;
there is no native arbitrary-file trigger assumption.

The native-owned target-root suite runs without a target Nix executable, daemon
socket or database. It tests shared-object dependencies, execution, corruption
and restoration, upgrades, retained siblings and complete payload removal. It
uses native dependency-protected orphan removal for the internal solver's shallow
autoremove behavior, then checks that the installed inventory is empty before
removing leftover empty directory parents. No regular files are removed outside
opkg. Upstream `verify` diagnostics are checked because mismatches do not change
its exit status.

Two bundled-client variants repeat the complete upstream opkg and signed native
OpenWrt lifecycle suites with an incompatible external candidate and an actual
static Nix client. The existing native signature, checksum, service, host,
configuration, state-path, ordinary-user and GC checks remain enabled.
