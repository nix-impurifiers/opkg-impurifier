# Commands

```sh
nix flake check -L
nix fmt
```

For shared engine changes, use a temporary `--override-input impurifier path:../impurifier --no-write-lock-file` while developing. Publish the core, converge consumer pins with the workspace tool, and verify published pins before landing. Never commit local path overrides.
