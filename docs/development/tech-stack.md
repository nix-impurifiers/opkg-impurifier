# Technology

Nix/Caisson composes the standalone flake. Native IPK/opkg artifacts carry descriptors and optional complete local NAR caches. A pinned non-flake impurifier source input supplies the Python engine and payload compiler. Native systemd handles services; consumers supply an existing Nix/Python runtime. No duplicated engine lives here.
