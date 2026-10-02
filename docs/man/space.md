# Disk space: caches

```text
mj space                              every known cache on this Mac, biggest first
mj space clean ae-disk-26.3           what emptying it would free (nothing is deleted)
mj space clean ae-disk-26.3 --yes     empty it
mj space clean leftovers --yes        empty every cache left over from versions no longer installed
```

Known caches: After Effects disk and 3D caches per version (including a custom disk-cache folder set in After Effects' preferences), the Adobe media cache, its database and audio waveform files, Redshift caches per Cinema 4D version, and the Cinema 4D Asset Browser cache (reported only; Cinema 4D manages it).

Safety: you name a cache by its id, never a path. Cleaning empties the folder but keeps it, never follows a link out of it, and refuses while the app that owns it is running, unless the cache belongs to a version that is no longer installed. Caches are rebuilt by the apps as needed; the first preview after cleaning is slower.
