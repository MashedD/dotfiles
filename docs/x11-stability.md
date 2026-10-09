# X11 stability trial: AMD hybrid-GPU laptop

## Confirmed failures

| Date (CEST) | GPU | Failure |
|---|---|---|
| 2026-10-01 14:48–14:49 | RX 6500M, PCI 03:00.0 | Xorg GPU-memory faults, gfx timeout, Mesa SIGABRT |
| 2026-10-06 10:10 | Radeon 660M, PCI 07:00.0 | Same fault/timeout/abort sequence |
| 2026-10-08 20:17:41–20:17:44 | RX 6500M, PCI 03:00.0 | Same sequence during ordinary desktop use |
| 2026-10-09 08:01:03–08:01:14 | RX 6500M, PCI 03:00.0 | Same sequence on 6.18.55-1-cachyos-lts |

The October 8 kernel journal attributes the faults and `gfx_0.0.0` timeout
to Xorg PID 1730 (`Xorg:cs0`, TID 1739). The core records SIGABRT with its
worker stack in `libgallium-26.2.4-arch3.1.so`. This matches the previous
GPU/Mesa failures, rather than an Openbox exit or OOM kill. Repeated Xorg
`drmmode_do_crtc_dpms cannot get last vblank counter` warnings are also
present, but do not independently establish the cause. The exact upstream
Mesa/kernel defect is **not identified**.

Baseline at collection:

- Running kernel: `7.2.9-1-cachyos`
- Installed LTS kernel: `6.18.55-1-cachyos-lts`
- Mesa and lib32-mesa: `3:26.2.4-1`
- xf86-video-amdgpu: `25.0.0-1.1`; xorg-server: `21.1.25-1.1`
- Both RandR providers: `cap: 0xf`, one associated provider each
- HDMI-A-1-0 active and primary: 2560×1440 at 144 Hz; eDP inactive

Logs, package versions, kernel, provider/output state, configuration, boot
status and compressed Xorg core were preserved privately under
`~/.local/state/x11-crash-20261008-xR2pnM/`. Core dumps can contain sensitive
application data; do not commit or publicly upload them without review.

## LTS result: failed

The LTS trial was actually booted and **did not fix the crash**. On October 9,
Xorg PID 1749 (`Xorg:cs0`, TID 1757) hit dGPU UTCL2/TCP permission faults at
08:01:03, a `gfx_0.0.0` timeout/reset at 08:01:13, then SIGABRT in the same
Mesa worker-stack offsets as October 8. Mesa and Xorg package versions were
unchanged. Both GPUs' startup logs show radeonsi using ACO on LTS too.

Evidence and the compressed core are preserved privately under
`~/.local/state/x11-crash-20261009-t1RLpu/`. This rules out switching to this
LTS build as a sufficient workaround, but does not prove whether the defect
is in Mesa, common kernel code, firmware or hardware. ACO is a shared variable,
not a demonstrated cause. Do not promote LTS to a permanent default as a fix.

A sanitized [report draft](x11-crash-report.md) records both kernel results.
Per the failed-trial policy, stop speculative configuration changes and seek
maintainer-guided driver isolation/debug symbols. The trial instructions below
are retained for reproducibility, not as an untested recommendation.

## Preserve HDMI support

Leave `/etc/X11/xorg.conf.d/10-amdgpu.conf` unchanged for the trial: iGPU
primary, dGPU output provider, Glamor enabled. Do **not** set
`AccelMethod "none"`: that experiment disabled DRI3 and gave both providers
`cap: 0x0`, preventing HDMI attachment. It was rolled back.

Keep the `xrandr --current` display-helper change. It reduces hardware/EDID
probing, but the October 8 failure proves it was not a complete crash fix.
Do not add desktop restart loops, duplicate daemons, GPU power overrides,
or partial Arch library downgrades.

## LTS trial: authorization and reboot required

The LTS package and `/usr/lib/modules/6.18.55-1-cachyos-lts/vmlinuz` were
verified. The machine uses **systemd-boot**; the original regular-kernel entry was
`linux-cachyos.conf`. `/boot` is root-only, so artifacts could not be inspected
by the agent. The user subsequently booted LTS successfully, confirmed by
`uname -r` and the crashed Xorg startup log. LTS nevertheless crashed.

Before rebooting, run:

```sh
sudo bootctl list --no-pager
sudo ls -l /boot/loader/entries
```

Inspect the LTS entry shown by those commands with `sudo less` and verify
its `linux` and every `initrd` path exist and are nonempty under `/boot`.
For a UKI entry, verify its `efi` path instead. Check that the regular
kernel entry remains available too. Do not guess an entry ID or rewrite
the bootloader. If the LTS entry or an artifact is absent, stop: the exact
missing entry/artifact must be repaired before this trial can proceed.

Once verified, save work and reboot manually. Hold **Space** during startup
to show systemd-boot's menu and select the verified CachyOS LTS entry for
this boot only. Do not change the permanent default yet.

After booting:

```sh
uname -r
xrandr --listproviders
xrandr --current
```

`uname -r` must contain `cachyos-lts`; installing the package or rebooting
into `7.2.9-1-cachyos` does not test LTS. Keep Mesa, firmware and Xorg
configuration unchanged for this comparison. Record any intervening package
updates so they are not mistaken for a kernel-only result.

## Acceptance checklist

After saving work, verify:

- [ ] Nonzero provider capabilities and successful dGPU/iGPU association.
- [ ] External HDMI primary at 2560×1440/144 Hz.
- [ ] Unplug HDMI: internal panel becomes usable; reconnect: HDMI returns.
- [ ] Kitty and browser render normally.
- [ ] Lock/unlock, blank/wake and one suspend/resume cycle work.
- [ ] At least **seven days** of ordinary use, including idle/wake, without
      another Xorg core, GPU-memory fault or graphics-ring timeout.

Record the start/end times, kernel and test results. Inspect failures since
the start of the LTS boot (old cores are not new trial failures):

```sh
journalctl -k -b --no-pager | grep -E 'page fault|ring .*timeout|Process Xorg|GPU reset'
coredumpctl list /usr/lib/Xorg --no-pager
```

Repository-only checks, safe without altering displays:

```sh
python3 tests/test-openbox-display.py
sh -n dotfiles/.local/bin/openbox-display
```

Successful startup alone is not evidence of a permanent fix. Only after
all checks and the observation interval pass should LTS become the normal
boot choice; retain the regular kernel as a recovery option.

## Capture another failure before restarting X

Run promptly after the failure. The directory is private and uniquely named;
no previous evidence is overwritten. If running from a console, display
queries may fail; their captured errors are expected.

```sh
umask 077
state="${XDG_STATE_HOME:-$HOME/.local/state}"
mkdir -p "$state"
evidence=$(mktemp -d "$state/x11-crash-$(date +%Y%m%d-%H%M%S)-XXXXXX") || exit 1
cp -a "$HOME"/.local/share/xorg/Xorg.*.log* "$evidence/"
journalctl -b --since '20 minutes ago' --no-pager > "$evidence/crash-journal.txt"
coredumpctl -1 info /usr/lib/Xorg --no-pager > "$evidence/xorg-core-info.txt"
coredumpctl -1 dump /usr/lib/Xorg --output="$evidence/Xorg.core"
pacman -Q > "$evidence/packages.txt"
uname -a > "$evidence/kernel.txt"
xrandr --listproviders > "$evidence/providers.txt" 2>&1
xrandr --current > "$evidence/outputs.txt" 2>&1
cp -a /etc/X11/xorg.conf.d/10-amdgpu.conf "$evidence/"
printf 'Evidence: %s\n' "$evidence"
```

If collection happens later, repeat the journal capture with explicit
`--since`/`--until` timestamps around the core's time and the correct boot
(`journalctl --list-boots`). If no core is accessible, retain the error and
logs rather than discarding the evidence. Check that the latest core really
belongs to the new failure before comparing results.

## Recovery and escalation

If LTS cannot boot or breaks HDMI/rendering, select the retained regular
kernel in systemd-boot. Do not disable Glamor again. No reboot, default-entry
change or session termination is performed automatically by this repository.

If the same crash occurs on LTS, preserve the new evidence and stop speculative
configuration changes. Prepare an AMD/Mesa/Xorg report with both kernel
versions, full package versions, GPU PCI IDs, external-monitor topology,
ordinary-use context, timestamps, kernel fault/timeout sequence and Xorg
stack trace. Include both trial outcomes and explicitly state the rejected
Glamor experiment. Review logs for private information before sharing; keep
raw cores private unless a maintainer requests a secure transfer. At that
point the LTS trial has **not** established a fix.
