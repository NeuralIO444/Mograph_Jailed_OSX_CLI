# MographJailed Safety Model

This Mac is a production workstation. MographJailed therefore follows conservative rules.

## Never required

- sudo or administrator rights;
- Homebrew/MacPorts;
- Xcode or Command Line Tools;
- Python/pip;
- Node/npm;
- FFmpeg/OpenCV;
- background daemons or local servers.

## Source immutability

Original production media is read-only by default. Native may inspect, hash, or create temporary/derivative output, but must not overwrite, rename, move, delete, or clear metadata from source media.

## Destructive operations

Temporary cleanup and staging cleanup require ownership/containment evidence. Ambiguous cleanup fails closed.

## Shell boundary

MJ applications request named semantic operations. They do not receive an arbitrary shell-command API.

## Network storage

Network-sensitive operations may block or fail if an SMB/share path is slow or disappears. Writability is a hint, not a guarantee.
