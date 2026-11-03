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
