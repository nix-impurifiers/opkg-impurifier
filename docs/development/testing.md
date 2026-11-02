# Testing

`nix flake check -L` runs shared engine contracts, emitter metadata/closure checks,
and actual opkg 0.8 transactions in a QEMU NixOS VM. Offline tests disable the
network and assert the application closure was initially absent. Test failure
and recovery explicitly: opkg discards deferred callback status, so native exit
success does not establish activation success. Installation batches; removal
reconciles per package. See the README for covered operations and limitations.

The fixture provides actual preinstalled Nix/Python/systemd with a native
inventory provider. It is not a Nix installer, OpenWrt procd test, or claim of
OpenWrt-fork compatibility. Driver fixtures explicitly request reconciliation;
there is no native arbitrary-file trigger assumption.
