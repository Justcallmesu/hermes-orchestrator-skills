---
name: service-unresponsive-triage
description: "Use when a local service hangs or a remote can't connect."
---

# Unresponsive local service triage

Goal: tell the user in one line WHERE the failure is (host network, container networking, or the
process itself) with evidence, then the fix and what is not verified.

## Procedure
1. Identify what the user's name really refers to before assuming a hypervisor. "VM" is often a
   container: `ps -eo pid,comm,args | grep -iE 'qemu|vbox|nspawn|incus|lxd|docker|<name>'`,
   `machinectl list`, `docker ps`. Read the unit / `.nspawn` / compose config for its network mode
   (e.g. `VirtualEthernet=no` means host networking, so a missing `ve-*` link is expected).
2. Find the listener: `ss -ltnp` (process names show only for your own uid). Map each port to its
   owning process and user; a sibling instance of the same software is the best control.
3. Probe every bind address with a timeout:
   `curl -s -o /dev/null -m 5 -w '%{http_code} %{time_total}s\n' http://IP:PORT/` on loopback,
   LAN and VPN IPv4. Skip raw IPv6 literals in URLs (they trigger a security approval prompt).
4. Classify with socket states: `ss -tn '( sport = :PORT )'`.
   - connection refused -> nothing listening / wrong bind.
   - timeout + many `CLOSE-WAIT` with non-zero Recv-Q (and listen Recv-Q > 0) -> the kernel
     accepts but the app never reads or closes. Network is fine. This does NOT yet prove an app
     bug: run step 4b before calling it a hung event loop or recommending a restart.
   - works on loopback only -> bind address / firewall.
4b. Check the process state and host health before blaming the app (cheap, no root):
   `ps -o stat=,wchan:25= -p PID` sampled 3x, `free -h`, `cat /proc/pressure/memory /proc/pressure/io`,
   `swapon --show`, and `ps -eo stat,pid,comm | awk '$1 ~ /^D/'`.
   - `D` state with wchan `folio_wait_bit_common` / `filemap_fault` (kernel stack in page fault),
     swap near 100% and PSI `full` in the tens of percent -> the host is thrashing; many unrelated
     processes will also be in `D`. The app is fine; free memory and it recovers with NO restart.
     Follow `references/memory-pressure.md`.
   - `S` state, healthy memory, threads parked in `futex_wait`/`epoll_wait` but no progress ->
     genuine app hang (deadlock or blocking call on the loop): capture step 5, then restart.
5. Capture before restart, because a restart destroys the evidence of where it hung:
   `/proc/PID/task/*/stack` + `wchan`, fd count, `py-spy dump --pid PID` for Python, container
   journal via `journalctl -D /var/lib/machines/<name>/var/log/journal`.

5b. A freshly built feature fails in the user's local run with an app error message (not a hang):
   check the setup before reading code. One probe script: which ports listen (`ss -ltnp`), whether
   the feature's migration is in the DB's migrations table and its column exists
   (`information_schema.columns`), the new route's status without auth (401/403 = route exists, 404 =
   old process still running), and each proxied path's health through the dev server (502 = the
   backing service is not running). Usually it is an unapplied migration or an unstarted service;
   give the exact restart order. Running the migration against the user's DB is theirs to do.

6. "Remote client cannot connect" (phone/tablet -> bridge): if every probe in step 3 answers, the
   server is healthy; prove whether the client ever ARRIVED by reading the service's own request/
   audit log for the last non-local peer, not by restarting. No hit since the failure -> client
   side (VPN off on the device, changed LAN IP, wrong scheme/port, revoked pairing). Ask the user
   for the device, target address and exact error text before guessing further.

Depth: `references/memory-pressure.md` (thrashing diagnosis, finding RAM+swap hogs, Gradle
daemon cleanup, container swap cap); `references/remote-client-reachability.md` (bridge/remote
reachability checklist, container-owned processes, scheme-per-interface pitfalls).

## Root-only steps
- Check reachability first: `sudo -n true; grep NoNewPrivs /proc/self/status`.
- If the agent shell cannot get root, never stop at "needs sudo". Write the step as a read-only
  script (write_file; output to a scratch file, `chown` it back to the user), give the user the
  one-line `sudo bash <script>`, and read the file when they say done.
- Treat privilege consistently: route privileged reads and privileged fixes the same way. Refusing
  a root log read while offering a root restart as if you could do it angers the user; never offer
  an action you cannot execute yourself without saying who runs it.

## Commands handed to the user
- Bundle the whole fix into one idempotent root script (write_file + `bash -n` check) with a
  `== verify ==` section, and give a single `sudo bash <script>` line. The user wants it all at
  once, not a drip of separate commands.
- Never print config-file contents in a block that looks like shell commands: the user will paste
  it into the terminal. Either have the script append the file, or label the block as file
  contents with its exact path.
- The user's interactive shell is fish: one-liners must be fish-safe (no heredocs, no `$(...)`,
  no `&&` assumptions); `printf '%s\n' ... | sudo tee -a FILE` works in both.
- `.properties` files only treat `#` as a comment at line start; never put trailing `# ...`
  comments on value lines.
- Paths inside an nspawn container's home are `/var/lib/machines/<name>/home/<user>/...` and are
  root-only from the host, so writes there go in the root script.

## Report
Table of checks -> results, the verdict, the fix command (and who runs it), and explicitly what
was not read (logs, root cause) plus the command that gets it.
