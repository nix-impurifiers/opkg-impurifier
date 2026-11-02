# Product

Compile Nix application intent into native IPK/opkg artifacts, with native configuration and host integration and a shared atomic, rooted Nix profile. The boundary follows the package manager; consumers select distribution-specific runtime dependencies. Original project code is MIT licensed. See [the public API](../../README.md).

The Nix provider/installer remains deferred, not excluded. Hardware bridging is explicit and opt-in; fake-driver VM coverage does not establish real GPU ABI compatibility.
