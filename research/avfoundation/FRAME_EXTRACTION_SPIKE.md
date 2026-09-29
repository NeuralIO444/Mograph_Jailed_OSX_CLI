# AVFoundation frame extraction spike — M6 lab

Status: **research design only; not production code**.

The API surface is technically suitable:

- `AVAssetImageGenerator(asset:)` generates images from a video asset.
- `maximumSize` bounds generated image dimensions.
- `requestedTimeToleranceBefore` and `requestedTimeToleranceAfter` can be set to zero for frame-accurate requests, at additional decode cost.
- image-generation APIs report the actual generated time as well as the requested time.
- pending asynchronous generation can be cancelled.

A production candidate would need to return, for each requested sample:

```text
requestedTime
actualTime
width
height
frame extraction status
```

No JXA implementation is promoted from this document. JXA representation of Core Media structures, asynchronous callbacks, error pointers, framework import behavior, and managed-Mac security behavior must be verified on target machines first.
