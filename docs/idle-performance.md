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

## Follow-up: exact statistics I/O, 2026-10-15

```sh
lua5.3 tests/probe-awesome-stats.lua             # 60 samples, 1 s sleep between batches
lua5.3 tests/probe-awesome-stats.lua --control   # fake/no-I/O overhead, no sleeping
```

Use a Lua interpreter with lgi/Gio/GLib. On this machine Awesome uses Lua 5.3.6
(`lua53 5.3.6-4.1`, `lua53-lgi 0.9.2-14`); the default `lua` is 5.5.1 and has no lgi.
No packages were installed. The real default probe was run once, standalone, without
concurrent private Awesome sessions, on the same `7.2.9-2-cachyos` kernel. Live Awesome
continued its normal polling; no injection, service calls or signals were used.

The probe preserves the original synchronous collector's order, Gio calls, battery selection/averaging and
network parsing. It times collection only: no widgets, notifications or rendering.
One second of sleep follows each batch, so the observed ~103 ms batch produces about
1.1 seconds between starts, not an accelerated hardware poll. Nested rows are
inclusive and must not be summed. File durations cover open + read-all + close.

| Operation | Successful samples | Median ms | p95 ms | Maximum ms |
| --- | ---: | ---: | ---: | ---: |
| Total batch | 60 | 103.360 | 104.368 | 104.977 |
| Battery subsystem | 60 | 102.723 | 103.471 | 103.737 |
| **BAT1/capacity** | **60** | **101.959** | **102.435** | **102.771** |
| BAT1/status | 60 | 0.068 | 0.089 | 0.117 |
| BAT1/type | 60 | 0.040 | 0.059 | 0.075 |
| Logitech hidpp_battery_0/capacity | 60 | 0.037 | 0.051 | 0.165 |
| Logitech hidpp_battery_0/status | 60 | 0.036 | 0.050 | 0.053 |
| Filesystem subsystem | 60 | 0.239 | 0.329 | 3.053 |
| Network read + parsing | 60 | 0.219 | 0.357 | 0.746 |
| /proc/stat | 60 | 0.105 | 0.139 | 0.347 |
| /proc/meminfo | 60 | 0.046 | 0.062 | 0.075 |

Enumeration open/next/close maxima were 0.182/0.230/0.053 ms. All real samples
succeeded; missing/error timings were not represented as zero-cost successes.
The 60-batch fake/no-I/O control, using the same three-supply enumeration shape,
measured total median 0.123 ms, p95 0.192 ms, maximum 0.275 ms. This bounds the
scale of observed instrumentation/control overhead, not an exact overhead subtraction:
the fake calls are not real Gio/sysfs operations and the control is warm/no-sleep.

**Conclusion:** the laptop's `/sys/class/power_supply/BAT1/capacity` operation is
the demonstrated blocker. Its ~102 ms delay accounts for nearly all the standalone
batch time and reproduces the previous ~105 ms collector tail. The Logitech mouse
read is not the culprit in this run. Different cadence, concurrent live reads and
kernel/device caching can explain differing distributions; this measurement does
not identify the underlying ACPI/kernel/firmware cause or quantify CPU savings.

**Smallest next fix to plan:** move the slow laptop-capacity sampling off Awesome's
main loop, using the existing shared collector lifecycle and unchanged cadence.
Keep fast proc/network/filesystem reads and per-screen widgets unchanged; explicitly
test pending requests, unplug/read failures, late completions, and last-sample/error
semantics. Verify the chosen async API really performs this sysfs read off the main
thread. Do not add a daemon or redesign every collector based on this result.
No production fix is part of this diagnostic pass.

Artifacts: `/tmp/stats-probe-60.log` and `/tmp/stats-probe-control.log` are ephemeral.
A separate one-sample smoke check verified invocation outside the repository root.

## Targeted fix: asynchronous laptop capacity

`sidebar-battery.lua` now dispatches only laptop capacity reads through Gio
`load_contents_async`. The shared one-second stats fetch publishes after completion;
fast filesystem/proc/network/mouse reads keep their original semantics. No new timer,
daemon, command, dependency or polling interval was introduced. Multi-battery order,
averaging, zero levels, missing-capacity omission and status fallback are retained.
Final-subscriber removal cancels outstanding Gio reads; generation guards reject late
callbacks. A read that stays pending does not overlap another request: the last sample
ages/stales normally while the independent clock and UI remain active.

A standalone native Gio check read the slow capacity file in 104.931 ms while a
10 ms GLib timer fired **10 times**. This verifies off-main-loop execution for this
installed Gio/sysfs combination, rather than merely assuming an async method name.
Fake adapter tests separately verify dispatch/finish and cancellation behavior.

After-fix audit: `python3 tests/audit-awesome-idle.py --skip-live --output
/tmp/awesome-idle-after-battery.json`, 180 seconds/case and 15 seconds warm-up, same
fixture topology and timer intervals. Live desktop configuration was not reloaded.

| Measurement | Before one / two | After one / two |
| --- | ---: | ---: |
| Synchronous stats median ms | 1.781 / 2.445 | 0.870 / 0.952 |
| Synchronous stats p95 ms | 104.125 / 104.909 | **1.163 / 1.126** |
| Synchronous stats maximum ms | 104.722 / 105.441 | 7.980 / 1.430 |
| Heartbeat lateness p95 ms | 53.077 / 105.920 | 9.945 / 95.943 |
| Completed stats requests | 180 / 180 | 180 / 180 |
| Awesome CPU % of one core | 5.189 / 10.661 | 8.228 / 17.444 |

The asynchronous request still takes real time (end-to-end median 53.503 / 104.355 ms,
p95 156.009 / 212.466 ms); it no longer occupies the main loop during the slow read.
Both profiles retained one shared service with two-screen subscriptions and no pending
refresh skips. The uninstrumented one-screen after-control used 8.528% CPU.

**This is a main-loop responsiveness fix, not a demonstrated CPU reduction.** CPU
was higher in the later run, and two-screen heartbeat spikes remain (maximum 453.474
ms). Runs were sequential, not paired under identical load; freed event-loop time,
rendering, scheduling and hardware-cache effects may all matter. The next independent
performance target remains per-screen drawing/layout. No claim is made that all
sysfs I/O is nonblocking: the previously fast type/status/mouse reads remain synchronous.
