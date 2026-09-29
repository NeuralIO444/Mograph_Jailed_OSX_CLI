# M3 macOS native media gate

1. Run `system.probe` and record whether `/usr/bin/mdls` and `/usr/bin/avmediainfo` are available.
2. Run `media.inspect` on a known-good local QuickTime/MP4 media file.
   - Confirm `ok:true`.
   - If `avmediainfo` is available, confirm `nativeProbe:"notRun"`; default inspection must not execute it.
   - Confirm any duration/dimension values are source-attributed to `mdls` and plausible.
3. Repeat with a filename containing spaces, apostrophe, and Unicode.
4. Repeat from an SMB-mounted source if available and note responsiveness.
5. Run `media.inspect` on a deliberately non-media/plain-text file.
   - It may still return filesystem/basic-type facts.
   - It must not claim native media validation or invent duration/dimensions.
6. Run `media.timing` on valid media.
   - If `avmediainfo` is unavailable, expect `UNSUPPORTED`.
   - If it is available, expect `UNSUPPORTED_STRUCTURED_OUTPUT`; V0.1 does not parse undocumented human-readable sample text.
7. Confirm source file size, mtime, and SHA-256 are unchanged after the disposable test set.
