# Remote client cannot reach a local bridge/service

Use when a phone/tablet/other PC "suddenly cannot connect" to a service on this host (e.g. the
Hermes Remote bridge). Goal: decide server-side vs client-side with evidence.

## Checklist (all no-root)
1. `ps -eo pid,user,etime,args | grep -i <name>` + `ss -ltnp`: list EVERY instance and port.
   Sibling instances on adjacent ports are common (a second copy running inside a container).
2. Probe each bind address per port with the scheme it actually serves. A service may serve
   plain HTTP on loopback/VPN but HTTPS only on LAN: an `http://LAN:PORT` probe returning `000`
   is then expected, not the fault. Read the startup log line ("listening on ...") for the scheme
   per address, then re-probe with `curl -sk https://...`.
3. Find the service's own log/state dir (`~/.local/state/<app>/`, `~/.config/<app>/`). An audit
   or access log with a `peer` field is the best evidence: filter out local/health-check peers
   and read the last remote hits and their timestamps (`date -d @<ts>`). Your own probes show up
   there too, which confirms logging works.
4. Check pairing/auth state (devices file: `revoked_at`, `last_seen_at`) and print it with
   secret fields filtered out (grep -v token/secret/hash/key).
5. VPN: `tailscale status` shows which peers are online now; firewall: rule files under
   `/etc/ufw/user.rules` are world-readable even when the live ruleset needs root.
6. `journalctl --user -u <unit>` can stop retaining entries while the service keeps running;
   when it is empty, fall back to the app's own log file rather than concluding "no traffic".

## Process belongs to a container
If `/proc/PID/cwd` or fd paths point at a home that does not exist on the host, the process
runs inside an nspawn/container: `cat /proc/PID/cgroup` shows `machine.slice/...`. Read its
files through `/proc/PID/root/<path>` (works as the same uid, no root needed).

## Verdict shapes
- All probes answer + no remote hit in the app log since the failure -> client side or path
  between; list device-side checks (VPN toggled off by battery saver, device on another Wi-Fi,
  host LAN IP changed by DHCP, re-pair if revoked).
- Remote hits present with 401/403 -> auth/pairing.
- Probes fail -> continue with the main procedure (bind, firewall, hang).
