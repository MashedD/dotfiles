# Awesome idle performance audit

Measured 2026-10-15. **No production configuration or refresh intervals changed.**
The strongest lead is occasional synchronous statistics stalls; there is no evidence
that volume/media polling needs an event-subscription rewrite.

## Reproduce

```sh
python3 tests/audit-awesome-idle.py --output /tmp/awesome-idle-audit.json
```

This opt-in command first samples live Awesome through `/proc` only, then runs an
uninstrumented control, one-screen profile and two-screen profile sequentially.
Each private case warms up for 15 seconds and measures 180 seconds. Use `--skip-live`
to omit live sampling; `--duration 2 --warmup 1` is a tooling smoke test, not a useful
performance benchmark. JSON and a detailed Markdown table are saved beside the output
path. The long audit is not part of `tests/run.sh`.

Environment: CachyOS kernel `7.2.9-2-cachyos`, Awesome 4.3/Lua 5.3 (compiled against
5.3.6), lgi 0.9.2, Python 3.14.8, Xvfb `21.1.25-1.1`, D-Bus `1.16.2-1.1`.
Private Xvfb root: 2560×800; logical screens: one/two 1280×800 screens. No Picom;
this does not measure compositor/GPU-driver performance. Nonfatal Xvfb keymap/AMDGPU
initialization warnings occurred; private displays and processes started successfully.

## CPU and memory

CPU is percent of **one logical core**, from delta utime+stime over actual elapsed
time; RSS is sampled once per second. These values exclude child-process CPU.
All four cases produced 181 samples over approximately 180.001 seconds.

| Case | CPU % | Mean RSS MiB | Peak RSS MiB |
| --- | ---: | ---: | ---: |
| Live, ordinary use | 5.467 | 164.35 | 164.35 |
| Private one-screen control | 5.278 | 110.13 | 125.84 |
| Private one-screen instrumented | 5.189 | 107.93 | 122.08 |
| Private two-screen instrumented | 10.661 | 143.50 | 173.14 |

Live sampling happened before private sessions, with no live Lua injection, tracing,
service calls or signals. It was not controlled idle activity and is not directly
comparable with private fixtures. One run per case is not a confidence interval.
Instrumentation's observed CPU difference from control was -0.089 percentage points:
within uncontrolled run-to-run variation, **not proof of zero profiling overhead**.
No two-screen uninstrumented control was measured.

## Requests and subprocesses

Same deterministic fixtures in every private case: five todo entries, one calendar
event, fixed successful weather/crypto/quota/audio/media shell responses, and a local
Trash directory containing 32 files (the collector reads only the first entry).
The private copy redirects Trash enumeration to that directory, avoiding real Trash
or GVfs services. Statistics still read the host's proc/sysfs/filesystem information.
Sections remain unfolded; the default analog clock and all refresh intervals remain.

| Collector | Interval s | Expected in 180 s (±1 boundary) | One screen | Two screens |
| --- | ---: | ---: | ---: | ---: |
| Clock | 1 | 180 | 180 | 180 |
| Statistics | 1 | 180 | 180 | 180 |
| Volume | 3 | 60 | 60 | 60 |
| Media | 5 | 36 | 36 | 36 |
| Trash | 30 | 6 | 6 | 6 |
| Crypto | 60 | 3 | 3 | 3 |
| Quota | 60 | 3 | 3 | 3 |
| Weather | 1800 | 0 or 1, phase-dependent | 0 | 0 |

Each collector made one startup request in each profile. The 15-second warm-up
added 15 clock/stats, five volume and three media requests; startup/warm-up samples
are not included in steady-state timing below. Weather's single startup stub request
says nothing about a real 30-minute refresh or network latency. Three-sample results
are low-count observations, not stable estimates.

Both profiles made **102 measured easy_async launch requests**: 60 wpctl, 36
playerctl, three crypto and three quota; all completed with status 0. Production's
timeout wrapper remains around each. This counts API launch requests, not traced
kernel process creations. Collector launches did **not** multiply with monitor count:
all eight collectors shared one service, with one versus two listeners. No pending
refresh skips were observed. Unchanged volume/media/etc. values generated no repeated
measured notifications; clock/statistics notifications remained active.

## Synchronous work and scheduling

Durations include the wrapped operation and its synchronous notifications/widget
work; they are wall time, not CPU time. Spawned-command latency includes scheduling
and local stub execution, **not real backend latency**. p95 uses nearest rank.

| Operation | Samples one / two | Median ms one / two | p95 ms one / two | Maximum ms one / two |
| --- | ---: | ---: | ---: | ---: |
| Statistics fetch, synchronous | 180 / 180 | 1.781 / 2.445 | 104.125 / 104.909 | 104.722 / 105.441 |
| Clock fetch, synchronous | 180 / 180 | 0.467 / 0.884 | 0.676 / 1.254 | 0.803 / 2.705 |
| Trash fetch, synchronous | 6 / 6 | 0.291 / 0.283 | 0.632 / 0.421 | 0.632 / 0.421 |
| Calendar refresh, screen 1 | 3 / 3 | 12.594 / 19.860 | 14.682 / 22.368 | 14.682 / 22.368 |
| Todo refresh, screen 1 | 3 / 3 | 1.372 / 2.220 | 1.605 / 2.512 | 1.605 / 2.512 |
| Heartbeat lateness | 1715 / 1642 | 0.229 / 0.462 | 53.077 / 105.920 | 327.639 / 414.192 |

The second screen added three calendar refreshes (median 19.411 ms, maximum 22.671 ms)
and three todo refreshes (median 2.258 ms, maximum 2.586 ms); those remain per-screen.
Each clock notification took median 0.440 / 0.851 ms, while statistics notifications
took 0.325 / 0.565 ms. Subscriber growth alone does not explain ~100 ms stat stalls.

The 100 ms heartbeat records lateness relative to the previous callback, not missed
frames. For lateness above 10 ms, synchronous statistics intervals overlapped 164 /
179 heartbeat gaps; every document refresh also overlapped such a gap. Intervals
are nested and a gap may include several operations: overlap is not attribution,
those counts are not unique causal events, and redraw/host scheduling may intervene.
The profiler does not isolate individual battery/proc/filesystem reads or rendering.

## Ranked next steps

1. **Investigate statistics sub-read latency first (high confidence lead).** Its
   ~104–105 ms upper tail is repeatable across screen counts. Profile battery/sysfs,
   proc and filesystem substeps in isolation before choosing a fix. If avoidable,
   improvement could remove ~100 ms main-loop stalls; CPU savings are unknown.
2. **Profile per-screen drawing/layout next (medium confidence).** Two-screen CPU
   roughly doubled despite identical shared collector launch counts. That supports
   examining repaint costs, not duplicating or slowing collectors. This run does
   not identify a particular widget as the cause or quantify an optimization benefit.
3. **Leave polling and document architecture alone for now.** Volume/media synchronous
   spawn setup was about 5 ms median per call in the one-screen fixture; launches are
   already shared. Calendar's ~20 ms refresh on a second screen occurs once per minute.
   Event subscriptions or a document-cache layer add complexity without demonstrated
   large benefit. Real command latency and large documents need separate evidence.
4. **Do not claim real Trash is nonblocking.** Local fixture enumeration stayed below
   1 ms; that does not establish remote/GVfs or slow-storage behavior. Async Trash is
   a plausible defensive change, not a demonstrated bottleneck from this audit.

Raw run artifacts: `/tmp/awesome-idle-audit.json` and `.md` (ephemeral; rerun the command
to regenerate). No optimization, daemon, dependency, live-service change or default
README expansion was introduced by this audit.
