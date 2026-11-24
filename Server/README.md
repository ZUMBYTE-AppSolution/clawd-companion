# Ranked arena service

The desktop apps use the JSON API at `https://zumbyte.de/api/clawd/v1`. Signed-in players can open a ranked round from the app. Local or idle rounds have no route for uploading a score.

## SSH deployment from the source checkout

Run the operator script from a workstation with Bash, Python 3, tar and OpenSSH. The target needs Python 3.11+, SQLite 3.35+, Gunicorn at `/usr/bin/gunicorn`, systemd and a running nginx TLS virtual host for `zumbyte.de`. Use your existing authorized SSH alias with a verified host key in known_hosts, and a root account or noninteractive sudo for deployment.

```sh
Scripts/deploy-arena.sh --archive ./Clawd-Arena-API-0.6.0.tar.gz --check-local
Scripts/deploy-arena.sh --host YOUR_SSH_ALIAS --archive ./Clawd-Arena-API-0.6.0.tar.gz
```

The helper connects to Zumbyte on SSH port **29**. Use `--port PORT` for a different host and `--identity FILE` to select a key. Use `--sha256 HEX` with the archive's entry from the release's SHA256SUMS file. The helper also compares the archive digest across the SSH transfer. `--check-local` inspects the archive without opening a connection. If several active files contain a matching TLS virtual host, pass `--nginx-site /etc/nginx/sites-available/YOUR_SITE`. The chosen file must appear in nginx's active configuration and contain a single direct `server_name zumbyte.de` and TLS listener on port 443. A previously configured matching inline location requires manual reconciliation.

On the server, the script stages a root-owned, versioned release under `/opt/clawd-arena/releases`. It preserves `/etc/clawd-arena.env` and the state database. It inserts one dedicated location include in the matching server block and backs up changed configuration in `/var/backups/clawd-arena/`. It validates nginx, checks the backend on loopback and checks the public HTTPS endpoint for the exact unauthorized JSON response. On a failed cutover it restores the previous configuration and service state. Running it again for the same archive repeats the health checks and leaves a healthy service running. The operator script lives in the source checkout; the release tar also supports the following manual installation.

## Production deployment

Use Python 3.11+ with SQLite 3.35+ and Gunicorn on a single Linux host with persistent local storage. The WSGI entry point is `Server.wsgi:application`. Deploy `Server/`, `Desktop/arcade.py` and its parent directory together under `/opt/clawd-companion`. The Python game engine uses the standard library. GUI packages are only imported when drawing a desktop surface.

Install the distribution's Gunicorn package or point the sample systemd unit at the executable in your virtual environment. As the host administrator, create the environment file exactly once. The command creates a new file exclusively with mode 0600 and writes a random key directly into it.

```sh
sudo python3 - <<'PY'
import base64, os, secrets
fd = os.open("/etc/clawd-arena.env", os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
with os.fdopen(fd, "w") as f:
    f.write("CLAWD_SECRET=" + base64.b64encode(secrets.token_bytes(32)).decode("ascii") + "\n")
PY
sudo install -m 0644 Server/deploy/clawd-arena.service /etc/systemd/system/clawd-arena.service
sudo systemctl daemon-reload
sudo systemctl enable --now clawd-arena
```

Include `Server/deploy/location.nginx` in the existing TLS virtual host for **zumbyte.de**. Run `nginx -t` before reloading. The proxy forwards the full request path. For an Apache/managed WSGI deployment that strips the mount prefix, provide the original mount as WSGI `SCRIPT_NAME`. The server requires HTTPS. The sample accepts forwarded scheme and client IP only from a loopback proxy configured with `CLAWD_TRUST_PROXY=1`. Leave that setting off for a TLS-aware WSGI host. Keep the backend port bound to loopback.

The systemd unit creates a private persistent state directory. Back up the SQLite database with its online backup interface and keep the environment key in the host's secret backup. The key indexes email addresses and throttling subjects. Keep the same key when moving or restoring the service. SQLite WAL is intended for a single machine, including multiple WSGI workers on that machine.

An unauthenticated `GET https://zumbyte.de/api/clawd/v1/me` should return HTTP 401 and `{"error":"unauthorized"}`. Check registration, login, logout and a complete ranked round using an explicitly designated test account after deployment. The public endpoint starts serving accounts when the operator installs and enables the service on the domain.

## App protocol

Paths below are relative to `/api/clawd/v1`. POST bodies are JSON objects with `Content-Type: application/json`. Authenticated requests use `Authorization: Bearer TOKEN`. The API rejects requests with a browser Origin and sends no CORS headers. Clients never embed a shared secret. Any client that implements the protocol can use it with valid user credentials.

| Method and path | Body or response |
| --- | --- |
| POST /register | Send `username`, `email`, `password`. Returns `{username,token}`. |
| POST /login | Send `username` (name or email) and `password`. Returns `{username,token}`. |
| POST /logout | Send `{}`. Immediately revokes the current bearer token and returns `{ok:true}`. |
| GET /me | Returns `{username,kills,deaths,kd,wins,score}`. |
| GET /leaderboard | Returns `{players:[{rank,username,kills,deaths,kd,wins,score}]}`, up to 100 participating accounts, sorted by score. |
| POST /runs | Send `{}`. Starts a round or resumes the current active round for this account. |
| GET /runs/ID | Returns a frame of the authenticated player's round. Poll at 3–4 Hz. |
| POST /runs/ID/click | Send `{seq,x,y}`. Coordinates are on a 300 × 160 playfield with a top-left origin. Sequence numbers start at 1. Send one click at a time. |

A frame contains `id,phase,wave,hp,hero,enemies,pickups,shots,kills,assists,ranked,seq,score`. Hero and shot positions use `x,y`. Shots have a `hostile` boolean. Enemies carry `id,kind,x,y,radius,hp,maxHP`. Pickups carry `id,kind,x,y,radius`. The phase is one of `wave,boss,dead,victory,expired`. Repeating the same click sequence only retrieves current state. A sequence gap returns HTTP 409; fetch the current frame and resume at `seq + 1`. An invalid or expired token returns 401, excess requests return 429.

## Ranking rules

A completed death puts that account's ranked arena on a five-minute cooldown. Starting a round from another device during this period returns HTTP 409 with the code `reviving`.

The service owns each round's seed, sprite masks, enemy health, movement, damage, time and terminal result. It advances the shared fixed-step game engine using host time. Clients send pixel coordinates. A click must land on visible enemy or pickup pixels; the game debounces hits. Player kills count only for manual finishing hits. Each gives 100 points. A victory with a manual hit on the boss gives one win and 500 extra points. Only a round with an effective click can score a death or enter the board. A played round abandoned for 25 seconds or exceeding three minutes ends as a death. Unassisted idle rounds earn nothing. Personal kills, deaths, wins and total score are added once in the same write transaction that closes the round. K/D is kills divided by deaths, rounded to two decimal places. At zero deaths it is mathematically undefined and comes across the wire as JSON null, including when kills are also zero.

The server validates game actions and cannot distinguish a person from software sending valid, timed clicks. It never accepts client-supplied scores, clocks, HP, target identities or outcomes.

## Accounts and retention

Usernames accept 3–24 ASCII letters, digits, underscores, dots and hyphens, beginning with a letter or digit. Passwords accept 12–128 characters at registration. Password verifiers use scrypt with a unique random salt per account (N=32768, r=8, p=3). Email lookups use a keyed HMAC, including for case-insensitive login. Email addresses are excluded from profiles and the leaderboard. Registration does not send email.

Session tokens contain 32 random bytes, expire after 30 days, and only their SHA-256 digest is persisted. Each account retains at most eight live sessions. The API limits registration, login, polling, starts and clicks. SQLite transactions serialize scoring across workers. Terminal run state is pruned after seven days; aggregate account stats persist.

Run the service tests from the repository root with `python3 -m unittest discover -s Server/tests -v`. They use temporary databases, isolated sessions, a controlled clock and the production WSGI request handler.
