# MographJailed Recovery

## Shell recovery

Known-good shell files are stored under:

```text
~/Documents/MographJailed/config/shell/
```

Restore `.zshrc` only if necessary:

```text
cp ~/Documents/MographJailed/config/shell/zshrc.known-good ~/.zshrc
source ~/.zshrc
```

## Runtime rollback

Development updater backups use names like:

```text
~/Documents/MographJailed.backup-YYYYMMDD-HHMMSS
```

Do not remove the previous known-good runtime until the new build passes target-Mac qualification.

A rollback should be performed deliberately with Terminal closed out of the project folder. Avoid manually merging `dist/` files between releases.
