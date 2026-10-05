# Hosts

`host.detect` is the first real check. Phase 0 and Phase 1 were qualified against stub hosts. A workstation gate is still open.

```sh
mj host.detect
mj ae.render path=/work/hero.aep target="Main" output=/work/renders label=hero range=0-119
mj c4d.render path=/work/scene.c4d output=/work/renders label=scene
mj last
```

A real After Effects render needs a project and a licence. A real Cinema 4D render needs the licence configured. The receipt records the host version. One render at a time. The source file is not changed.
