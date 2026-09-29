# Core Image comparison spike — M6 lab

Status: **research design only; not production code**.

Core Image has reduction filters that are appropriate for low-cost deterministic image signatures, including area average and area histogram filters.

Candidate future comparison pipeline:

```text
CGImage / CIImage
  -> bounded working size
  -> area average + histogram signature
  -> optional difference image
  -> scalar distance metric
```

This is intentionally not an optical-flow system. The first promotion target would be a simple, interpretable frame-distance score suitable for coarse loop-seam candidate ranking.
