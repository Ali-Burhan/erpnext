#!/usr/bin/env bash
#
# setup-frappe.sh - one-shot Frappe + ERPNext development setup (Ubuntu 22.04/24.04, Debian 12)
#
# Usage:
#   chmod +x setup-frappe.sh
#   ./setup-frappe.sh
#
# Run as a NORMAL user with sudo access (not root).
# The script asks for 3 things up front (site name, MariaDB root password,
# Administrator password) and then runs unattended.
#
# Optional overrides (environment variables):
#   FRAPPE_BRANCH Frappe branch (default: version-16; BRANCH remains an alias)
#   ERPNEXT_BRANCH ERPNext branch (default: feature/ai-purchase-invoice-draft)
#   OLLAMA_MODEL  model to install (default: qwen2:7b)
#   FRAPPE_REPO   default https://github.com/Ali-Burhan/frappe
#   ERPNEXT_REPO  default https://github.com/Ali-Burhan/erpnext
#   BENCH_DIR     default: a 'frappe-bench' folder next to this script
#   SITE_NAME     skip the prompt
#   DB_ROOT_PW    skip the prompt (MariaDB root password to SET)
#   ADMIN_PW      skip the prompt (ERPNext Administrator password)
#   EXTRA_APPS    space-separated git URLs of extra apps (e.g. your custom app)
#
# Example overriding the repository URLs:
#   FRAPPE_REPO=https://github.com/Ali-Burhan/frappe \
#   ERPNEXT_REPO=https://github.com/Ali-Burhan/erpnext \
#   FRAPPE_BRANCH=version-16 \
#   ERPNEXT_BRANCH=feature/ai-purchase-invoice-draft \
#   ./setup-frappe.sh

set -eo pipefail

# ---------------------------------------------------------------- helpers
log()  { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m!!  %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31mxx  %s\033[0m\n' "$*" >&2; exit 1; }

prompt_secret() { # prompt_secret VAR "Label"
  local var="$1" label="$2" a b
  [ -n "${!var:-}" ] && return 0
  while true; do
    read -rsp "$label: " a; echo
    read -rsp "Confirm $label: " b; echo
    if [ -n "$a" ] && [ "$a" = "$b" ]; then break; fi
    warn "Empty or not matching, try again."
  done
  printf -v "$var" '%s' "$a"
}

# bench new-site / install-app need bench's OWN two Redis servers (cache + queue,
# normally started by 'bench start'). We start them temporarily and stop them again,
# so nothing is left behind to block 'bench start' or supervisor later.
REDIS_STARTED=()
start_bench_redis() {
  local kind conf port i
  for kind in cache queue; do
    conf="$BENCH_DIR/config/redis_${kind}.conf"
    [ -f "$conf" ] || die "Missing $conf (bench init did not finish?)"
    port="$(awk '$1=="port"{print $2}' "$conf")"
    if redis-cli -p "$port" ping >/dev/null 2>&1; then
      continue   # already running, leave it alone
    fi
    log "Starting temporary Redis ($kind) on port $port"
    redis-server "$conf" --daemonize yes >/dev/null
    for i in $(seq 1 30); do
      redis-cli -p "$port" ping >/dev/null 2>&1 && break
      sleep 0.5
    done
    redis-cli -p "$port" ping >/dev/null 2>&1 || die "Could not start Redis on port $port (is another program using it?)"
    REDIS_STARTED+=("$port")
  done
}
stop_bench_redis() {
  local port
  for port in "${REDIS_STARTED[@]}"; do
    redis-cli -p "$port" shutdown nosave >/dev/null 2>&1 || true
  done
  REDIS_STARTED=()
}
trap stop_bench_redis EXIT

# ---------------------------------------------------------------- config
FRAPPE_BRANCH="${FRAPPE_BRANCH:-${BRANCH:-version-16}}"
ERPNEXT_BRANCH="${ERPNEXT_BRANCH:-feature/ai-purchase-invoice-draft}"
OLLAMA_MODEL="${OLLAMA_MODEL:-qwen2:7b}"
FRAPPE_REPO="${FRAPPE_REPO:-https://github.com/Ali-Burhan/frappe}"
ERPNEXT_REPO="${ERPNEXT_REPO:-https://github.com/Ali-Burhan/erpnext}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BENCH_DIR="${BENCH_DIR:-$SCRIPT_DIR/frappe-bench}"
EXTRA_APPS="${EXTRA_APPS:-}"

case "$FRAPPE_BRANCH" in
  version-16|develop) : "${PY_VER:=3.14}"; : "${NODE_VER:=24}" ;;
  version-15)         : "${PY_VER:=3.11}"; : "${NODE_VER:=18}" ;;
  *) die "Unsupported FRAPPE_BRANCH '$FRAPPE_BRANCH'. Use version-16, version-15 or develop." ;;
esac

[[ "$OLLAMA_MODEL" =~ ^[A-Za-z0-9._:-]+$ ]] || die "Invalid Ollama model name."

# ---------------------------------------------------------------- preflight
[ "$(id -u)" -ne 0 ] || die "Run as a normal user with sudo access, not as root."
command -v sudo >/dev/null || die "sudo is required."
. /etc/os-release
case "$ID" in
  ubuntu|debian) ;;
  *) die "Only Ubuntu/Debian are supported (found: $ID)." ;;
esac

case "$BENCH_DIR" in
  /mnt/[a-z]/*)
    die "The bench would be created on the Windows drive ($BENCH_DIR). Linux file operations fail there. Copy this script to your Linux home (e.g. ~/erpnext) and run it from there."
    ;;
esac

if [ -z "${SITE_NAME:-}" ]; then
  read -rp "Site name [mysite.localhost]: " SITE_NAME
  SITE_NAME="${SITE_NAME:-mysite.localhost}"
fi
prompt_secret DB_ROOT_PW "MariaDB root password (will be SET to this)"
prompt_secret ADMIN_PW   "ERPNext Administrator password"

log "Plan: Frappe $FRAPPE_BRANCH + ERPNext $ERPNEXT_BRANCH | Python $PY_VER | Node $NODE_VER | bench at $BENCH_DIR | site $SITE_NAME"
sudo -v

# ---------------------------------------------------------------- 1. system packages
log "Installing system packages"
sudo apt-get update -y
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
  git curl wget ca-certificates cron build-essential pkg-config \
  libffi-dev libssl-dev \
  redis-server mariadb-server mariadb-client libmariadb-dev libmariadb-dev-compat \
  xvfb libfontconfig fontconfig libxrender1 xfonts-75dpi xfonts-base tesseract-ocr

sudo systemctl enable --now cron   || true
sudo systemctl enable --now redis-server || true

# ---------------------------------------------------------------- 2. wkhtmltopdf (patched Qt, needed for PDFs)
if wkhtmltopdf --version 2>/dev/null | grep -q "with patched qt"; then
  log "wkhtmltopdf (patched qt) already installed"
else
  log "Installing wkhtmltopdf 0.12.6.1-3 (patched qt)"
  ARCH="$(dpkg --print-architecture)"
  case "$ARCH" in amd64|arm64) ;; *) die "No wkhtmltopdf build for architecture $ARCH" ;; esac
  TMP_DEB="$(mktemp --suffix=.deb)"
  wget -qO "$TMP_DEB" "https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-3/wkhtmltox_0.12.6.1-3.jammy_${ARCH}.deb"
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "$TMP_DEB"
  rm -f "$TMP_DEB"
fi

# ---------------------------------------------------------------- 3. MariaDB config + root password
log "Configuring MariaDB (utf8mb4 + root password)"
sudo systemctl enable --now mariadb
sudo tee /etc/mysql/mariadb.conf.d/99-frappe.cnf >/dev/null <<'EOF'
[mysqld]
character-set-client-handshake = FALSE
character-set-server = utf8mb4
collation-server = utf8mb4_unicode_ci

[mysql]
default-character-set = utf8mb4
EOF
sudo systemctl restart mariadb

# Keep unix_socket login (so `sudo mariadb` still works) AND allow password login (needed by bench).
SQL_PW=${DB_ROOT_PW//\\/\\\\}
SQL_PW=${SQL_PW//\'/\\\'}
sudo mariadb -e "ALTER USER 'root'@'localhost' IDENTIFIED VIA unix_socket OR mysql_native_password USING PASSWORD('${SQL_PW}'); FLUSH PRIVILEGES;"

# ---------------------------------------------------------------- 4. uv + Python + bench
log "Installing uv, Python $PY_VER and bench"
export PATH="$HOME/.local/bin:$PATH"
if ! command -v uv >/dev/null; then
  curl -LsSf https://astral.sh/uv/install.sh | sh
fi
export PATH="$HOME/.local/bin:$PATH"
uv python install "$PY_VER"
PY_BIN="$(uv python find "$PY_VER")"
uv tool install frappe-bench || uv tool upgrade frappe-bench
uv tool update-shell >/dev/null 2>&1 || true
bench --version

# ---------------------------------------------------------------- 5. Node + yarn
log "Installing Node $NODE_VER and yarn (via nvm)"
export NVM_DIR="$HOME/.nvm"
if [ ! -s "$NVM_DIR/nvm.sh" ]; then
  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
fi
# shellcheck disable=SC1091
. "$NVM_DIR/nvm.sh"
nvm install "$NODE_VER"
nvm alias default "$NODE_VER" >/dev/null
nvm use "$NODE_VER" >/dev/null
npm install -g yarn
node -v

# ---------------------------------------------------------------- 6. Ollama + model
log "Installing Ollama and model $OLLAMA_MODEL in WSL"
if ! command -v ollama >/dev/null; then
  curl -fsSL https://ollama.com/install.sh | sh
fi
sudo systemctl enable --now ollama
ollama pull "$OLLAMA_MODEL"

# ---------------------------------------------------------------- 7. bench + apps + site
log "Creating bench (Frappe $FRAPPE_BRANCH)"
mkdir -p "$(dirname "$BENCH_DIR")"
cd "$(dirname "$BENCH_DIR")"
if [ -d "$BENCH_DIR/apps/frappe" ]; then
  warn "Bench already exists at $BENCH_DIR, skipping bench init"
  CURRENT_FRAPPE_BRANCH="$(git -C "$BENCH_DIR/apps/frappe" branch --show-current)"
  [ "$CURRENT_FRAPPE_BRANCH" = "$FRAPPE_BRANCH" ] || die "Existing Frappe checkout is on '$CURRENT_FRAPPE_BRANCH', expected '$FRAPPE_BRANCH'."
else
  bench init --frappe-path "$FRAPPE_REPO" --frappe-branch "$FRAPPE_BRANCH" --python "$PY_BIN" "$(basename "$BENCH_DIR")"
fi

cd "$BENCH_DIR"

if [ -d apps/erpnext ]; then
  warn "ERPNext app already present, skipping get-app"
  CURRENT_ERPNEXT_BRANCH="$(git -C apps/erpnext branch --show-current)"
  [ "$CURRENT_ERPNEXT_BRANCH" = "$ERPNEXT_BRANCH" ] || die "Existing ERPNext checkout is on '$CURRENT_ERPNEXT_BRANCH', expected '$ERPNEXT_BRANCH'."
else
  log "Fetching ERPNext"
  bench get-app --branch "$ERPNEXT_BRANCH" "$ERPNEXT_REPO"
fi

for url in $EXTRA_APPS; do
  app="$(basename "$url" .git)"
  if [ -d "apps/$app" ]; then
    warn "App $app already present, skipping"
  else
    log "Fetching extra app: $app"
    bench get-app "$url"
  fi
done

start_bench_redis

CREATE_SITE=1
if [ -f "sites/$SITE_NAME/site_config.json" ]; then
  # Site folder exists: is it complete (ERPNext installed) or a leftover from a failed run?
  if APPS_OUT="$(bench --site "$SITE_NAME" list-apps 2>&1)"; then
    if printf '%s\n' "$APPS_OUT" | grep -qw erpnext; then
      CREATE_SITE=0
      warn "Site $SITE_NAME already exists with ERPNext installed, skipping new-site"
    else
      warn "Site $SITE_NAME exists but ERPNext is not installed (failed earlier run). Recreating it."
    fi
  else
    die "Site $SITE_NAME exists but could not be inspected:
$APPS_OUT
Fix that error, or remove the site yourself (bench drop-site $SITE_NAME) and re-run."
  fi
fi

if [ "$CREATE_SITE" -eq 1 ]; then
  log "Creating site $SITE_NAME and installing ERPNext"
  bench new-site "$SITE_NAME" \
    --mariadb-root-username root \
    --mariadb-root-password "$DB_ROOT_PW" \
    --force \
    --admin-password "$ADMIN_PW" \
    --install-app erpnext
fi

for url in $EXTRA_APPS; do
  app="$(basename "$url" .git)"
  bench --site "$SITE_NAME" install-app "$app" || warn "Could not install $app (already installed?)"
done

bench use "$SITE_NAME"

# ---------------------------------------------------------------- configure AI extraction
log "Configuring AI invoice extraction"
bench --site "$SITE_NAME" set-config ollama_base_url http://127.0.0.1:11434
bench --site "$SITE_NAME" set-config ollama_model "$OLLAMA_MODEL"
bench --site "$SITE_NAME" migrate
printf '%s\n' "$OLLAMA_MODEL" > "$BENCH_DIR/.ollama-model"
install -m 755 "$SCRIPT_DIR/start-ai-erpnext.sh" "$BENCH_DIR/start-ai-erpnext.sh"
bench build --app erpnext

stop_bench_redis

# ---------------------------------------------------------------- done
cat <<EOF

=====================================================================
 Done.

 Start ERPNext and Ollama together:
     cd $BENCH_DIR
     ./start-ai-erpnext.sh

 Then open:   http://$SITE_NAME:8000
 Login:       Administrator  /  (the password you chose)

 Ollama and $OLLAMA_MODEL are installed inside WSL. The first model load can take
 a while and needs several GB of available memory.

 If 'bench' or 'node' is not found in a new terminal, run:
     source ~/.bashrc

 Handy commands (from inside $BENCH_DIR):
     bench --site $SITE_NAME mariadb          # SQL shell on the site DB
     bench --site $SITE_NAME backup --with-files
     bench --site $SITE_NAME migrate          # after pulling code changes
     bench build --app erpnext                # rebuild JS/CSS
=====================================================================
EOF