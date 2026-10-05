# Install

MographJailed does not call the network. The bundle is the file you install.

```sh
sh scripts/build.zsh
# Install MographJailed.command, or point mj at dist/mograph-jailed.zsh
```

Dimension is a local binary, not a service.

```sh
dimension --version
# or
export MJ_DIMENSION_BIN=/path/to/dimension
```

`dimension.probe` returns the profile catalog inside the MJ envelope. If the binary is missing, the prong says so. It does not reach out.
