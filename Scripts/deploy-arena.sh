#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'HELP'
Usage: Scripts/deploy-arena.sh --host SSH_ALIAS --archive API.tar.gz [options]
  --port PORT          Zumbyte SSH port (default 29, range 1–65535)
  --identity FILE      SSH identity; otherwise use your normal SSH configuration
  --nginx-site PATH    Select an active remote nginx configuration file
  --sha256 HEX         Compare the archive against its published SHA256SUMS entry
  --check-local        Inspect the archive locally without SSH or host changes
HELP
}
host="" archive="" port=29 identity="" site="" checksum="" local_only=0
while (($#)); do
  case "$1" in
    --host|--archive|--port|--identity|--nginx-site|--sha256)
      (($# >= 2)) || { usage >&2; exit 2; }
      case "$1" in
        --host) host=$2;; --archive) archive=$2;; --port) port=$2;;
        --identity) identity=$2;; --nginx-site) site=$2;; --sha256) checksum=$2;;
      esac
      shift 2;;
    --check-local) local_only=1; shift;;
    --help|-h) usage; exit 0;;
    *) usage >&2; exit 2;;
  esac
done

[[ -f "$archive" ]] || { echo "Supply an existing --archive." >&2; exit 2; }
script_dir=$(cd "$(dirname "$0")" && pwd)
umask 077
stage=$(mktemp -d "${TMPDIR:-/tmp}/clawd-arena-send.XXXXXXXX")
trap 'rm -rf -- "$stage"' EXIT
cp -- "$archive" "$stage/release.tar.gz"
cp "$script_dir/deploy_arena_host.py" "$stage/deploy.py"
python3 "$stage/deploy.py" --inspect "$stage/release.tar.gz" "$checksum" "$site" "$stage/options.json"
((local_only == 0)) || exit 0

[[ "$host" =~ ^([A-Za-z0-9_][A-Za-z0-9_.-]*@)?[A-Za-z0-9][A-Za-z0-9_.:-]*$ ]] || {
  echo "Supply an SSH host or user@host alias with --host." >&2; exit 2;
}
ssh_args=(-T -o BatchMode=yes -o StrictHostKeyChecking=yes -o ClearAllForwardings=yes -o ForwardAgent=no -o ConnectTimeout=12)
[[ "$port" =~ ^[0-9]{1,5}$ ]] && ((10#$port >= 1 && 10#$port <= 65535)) || { echo "Invalid SSH port." >&2; exit 2; }
ssh_args+=(-p "$port")
if [[ -n "$identity" ]]; then
  [[ -f "$identity" ]] || { echo "Identity file unavailable." >&2; exit 2; }
  ssh_args+=(-o IdentitiesOnly=yes -i "$identity")
fi
# All operator values travel in JSON or as SSH argv. The remote shell program is fixed.
COPYFILE_DISABLE=1 tar -C "$stage" -cf - deploy.py options.json release.tar.gz |
  ssh "${ssh_args[@]}" "$host" 'set -eu
    umask 077
    stage=$(mktemp -d /tmp/clawd-arena-deploy.XXXXXXXX)
    trap '\''rm -rf -- "$stage"'\'' EXIT
    tar --no-same-owner -xf - -C "$stage" deploy.py options.json release.tar.gz
    if [ "$(id -u)" = 0 ]; then
      python3 -I "$stage/deploy.py" --apply "$stage"
    else
      sudo -n -- python3 -I "$stage/deploy.py" --apply "$stage"
    fi'
