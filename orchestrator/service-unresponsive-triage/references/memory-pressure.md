# Host memory pressure making a service look hung

## Confirm
- `free -h`: available < ~1 GB and swap (often zram) ~100% used.
- `/proc/pressure/io` and `/proc/pressure/memory`: `full avg10` well above ~10% = thrashing.
- Victim process `D` state, kernel stack `filemap_fault` / `folio_wait_bit_common`; many unrelated
  `D` processes (postgres, systemd, loginctl, loop kworker).
- Container cgroup: `/sys/fs/cgroup/machine.slice/systemd-nspawn@<name>.service/memory.{max,swap.max,peak,swap.peak,events}`.
  `memory.max` set but `memory.swap.max = max` means the container can't hit OOM and swaps forever
  instead (`oom_kill 0`, huge `swap.peak`).

## Find the consumers (RAM + swap, not RSS alone)
RSS hides swapped-out hogs. Rank by `VmRSS + VmSwap` from `/proc/*/status`, then group by
cmdline keyword (GradleDaemon, KotlinCompileDaemon, jest, browser, hermes). Write this as a
script file; the inline loop trips the command scanner.

The usual culprit on build hosts is idle Gradle and Kotlin daemons. Gradle keeps one daemon per distinct
JVM-args/version combination for up to 3 h idle, and each project's `-Xmx` (3g/4g/8g) can spawn
its own.

## Immediate relief
`pkill -f 'GradleDaemon|KotlinCompileDaemon'`. Risk: kills an in-flight build, which must be
rerun. Gradle respawns a daemon on the next build. Then re-probe the port; it should recover
without a restart (expect swap to drain gradually).

## Prevention (one root script)
1. Cap container swap so memory exhaustion OOM-kills the biggest process instead of freezing
   everything: `systemctl set-property systemd-nspawn@<name>.service MemorySwapMax=2G` (live and
   persistent). Trade-off: a build may get killed and need a rerun.
2. User-home `~/.gradle/gradle.properties` (overrides per-project values):
   ```
   org.gradle.daemon.idletimeout=600000
   org.gradle.jvmargs=-Xmx3g -XX:MaxMetaspaceSize=1g -Dfile.encoding=UTF-8
   kotlin.daemon.jvmargs=-Xmx2g
   ```
   Append idempotently (grep for the key first), `chown` to the container user's uid.
3. Verify: `systemctl show <unit> -p MemoryMax -p MemorySwapMax` and `cat .../memory.swap.max`.
