# Report draft: recurring radeonsi/Xorg GPU faults on AMD hybrid laptop

Draft for CachyOS graphics maintainers / Mesa triage. Not submitted automatically.
Raw core dumps and full journals remain private; review attachments before sharing.

## Summary

Xorg aborts after AMD GPU-memory permission faults and a graphics-ring timeout,
ending the Openbox X11 session. Reproduced on both regular and LTS CachyOS
kernels with Mesa 26.2.4. No deterministic minimal reproducer is known;
at least one failure occurred during ordinary desktop use, not gaming.

## System

- MSI AMD hybrid-GPU laptop, X11/startx, Openbox, no active picom.
- iGPU: Rembrandt Radeon 660M, PCI 07:00.0, device 1002:1681.
- dGPU: Navi 24 RX 6500M, PCI 03:00.0, device 1002:743f.
- amdgpu kernel driver and xf86-video-amdgpu Xorg driver.
- iGPU primary; dGPU HDMI output attached through RandR PRIME.
- External HDMI: 2560×1440 at 144 Hz, primary; internal eDP disabled while HDMI active.
- Mesa / lib32-mesa: 3:26.2.4-1.
- xorg-server: 21.1.25-1.1; xf86-video-amdgpu: 25.0.0-1.1.
- Xorg logs identify radeonsi with **ACO** on both GPUs.

## Controlled kernel comparison (local times CEST)

| Kernel | Date/time | Result |
|---|---|---|
| 7.2.9-1-cachyos | 2026-10-08 20:17:41–20:17:44 | dGPU faults, gfx timeout, Xorg SIGABRT |
| 6.18.55-1-cachyos-lts | 2026-10-09 08:01:03–08:01:14 | Same failure, same Mesa abort-stack offsets |

Mesa and Xorg versions were unchanged between these two failures. Earlier
crashes affected the dGPU (October 1) and iGPU (October 6); therefore simply
switching GPU selection is not known to fix the problem.

## LTS kernel excerpt

```text
08:01:03 amdgpu 0000:03:00.0: [gfxhub] page fault (src_id:0 ring:24 vmid:3 pasid:7)
08:01:03 Process Xorg pid 1749 thread Xorg:cs0 pid 1757
08:01:03 in page starting at address 0x00008001440a1000 from client 0x1b (UTCL2)
08:01:03 GCVM_L2_PROTECTION_FAULT_STATUS:0x00301031
08:01:03 Faulty UTCL2 client ID: TCP (0x8)
08:01:03 MORE_FAULTS: 0x1; WALKER_ERROR: 0x0; PERMISSION_FAULTS: 0x3
08:01:03 MAPPING_ERROR: 0x0; RW: 0x0
08:01:13 ring gfx_0.0.0 timeout, signaled seq=229372, emitted seq=229373
08:01:13 Ring gfx_0.0.0 reset succeeded
08:01:13 device wedged, but recovered through reset
```

Multiple neighboring GPU addresses fault in the same burst. Xorg then aborts
in Mesa despite the kernel reporting a successful ring reset.

## Matching abort-worker stack

Thread Xorg:cs0 on both kernels:

```text
abort (libc.so.6)
libgallium-26.2.4-arch3.1.so + 0xbf98a7
libgallium-26.2.4-arch3.1.so + 0xbfeb05
libgallium-26.2.4-arch3.1.so + 0x5eb419
libgallium-26.2.4-arch3.1.so + 0x63736c
```

The LTS main thread waits through libgallium and amdgpu_drv.so. These are
unsymbolized frames; matching offsets do not establish the original fault's
root cause. Matching-build debug symbols are needed for meaningful triage.

## Experiments and constraints

- Replaced recurring `xrandr --query` polling with `--current`: reduced EDID
  log spam but did not prevent crashes.
- Disabled Xorg Glamor on both GPUs: broke HDMI, disabled DRI3 and removed
  RandR provider capabilities (0x0). Reverted; unsuitable as a workaround.
- Restored acceleration: both providers advertise 0xf and external HDMI works.
- Booted installed LTS: same crash; not a fix.
- Repeated Xorg vblank-counter warnings also occur, but are not treated as
  proof of the fault's cause.

No compiler, power-management or library-downgrade experiments have been
applied following the failed LTS trial. ACO is a common factor but is not
proven responsible; kernel/firmware/hardware causes remain possible.

## Requested triage

Please advise how to obtain matching Mesa debug symbols and which controlled
isolation test is appropriate while retaining accelerated PRIME HDMI support
(e.g. shader-compiler comparison or supported matched Mesa build). The two
kernel journals, Xorg startup logs, package lists and core metadata are
available after privacy review. Raw cores are available only via an agreed
secure transfer, not public issue attachments.
