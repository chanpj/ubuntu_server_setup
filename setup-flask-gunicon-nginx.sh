#!/usr/bin/env bash
set -Eeuo pipefail

fail() {
    printf '오류: %s\n' "$*" >&2
    exit 1
}

if [[ "${EUID}" -eq 0 ]]; then
    fail "sudo로 스크립트 전체를 실행하지 마세요. 일반 사용자로 실행하면 필요한 명령에만 sudo를 사용합니다."
fi

command -v sudo >/dev/null 2>&1 || fail "sudo가 설치되어 있어야 합니다."

if [[ -r /etc/os-release ]]; then
    # shellcheck source=/dev/null
    source /etc/os-release
    [[ "${ID:-}" == "ubuntu" && "${VERSION_ID:-}" == "24.04" ]] ||
        fail "이 스크립트는 Ubuntu 24.04용입니다. 현재 OS: ${PRETTY_NAME:-알 수 없음}"
else
    fail "/etc/os-release를 읽을 수 없습니다."
fi

DEPLOY_USER="$(id -un)"
DEPLOY_HOME="$(getent passwd "$DEPLOY_USER" | cut -d: -f6)"
[[ -n "$DEPLOY_HOME" && -d "$DEPLOY_HOME" ]] || fail "사용자 홈 디렉터리를 찾을 수 없습니다: $DEPLOY_USER"

printf '%s\n' "Flask + Gunicorn + Nginx 초기 설정 (Ubuntu 24.04)"
printf '배포 사용자: %s\n' "$DEPLOY_USER"

read -r -p "프로젝트 이름 (예: myproject): " PROJECT_NAME
[[ "$PROJECT_NAME" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]*$ ]] ||
    fail "프로젝트 이름은 영문자/숫자로 시작하고 영문자, 숫자, _ 또는 -만 사용할 수 있습니다."

read -r -p "Git 저장소 URL: " REPOSITORY_URL
[[ -n "$REPOSITORY_URL" ]] || fail "Git 저장소 URL은 필수입니다."

read -r -p "Git 브랜치 (기본 브랜치를 사용하려면 Enter): " GIT_BRANCH
read -r -p "도메인 또는 서버 IP (없으면 Enter, 기본값 _): " SERVER_NAME
SERVER_NAME="${SERVER_NAME:-_}"
[[ "$SERVER_NAME" =~ ^[A-Za-z0-9._-]+$ ]] ||
    fail "도메인/IP에는 영문자, 숫자, 점, 하이픈, 밑줄만 사용할 수 있습니다."

read -r -p "Gunicorn 앱 진입점 (기본값 wsgi:app): " WSGI_APP
WSGI_APP="${WSGI_APP:-wsgi:app}"
[[ "$WSGI_APP" =~ ^[A-Za-z_][A-Za-z0-9_.]*:[A-Za-z_][A-Za-z0-9_]*$ ]] ||
    fail "Gunicorn 진입점은 module:callable 형식이어야 합니다. 예: wsgi:app"

read -r -p "UFW 방화벽을 설정하고 활성화할까요? SSH 포트를 허용한 뒤 80 포트를 엽니다 [y/N]: " ENABLE_UFW
SSH_PORT=""
if [[ "$ENABLE_UFW" =~ ^[Yy]$ ]]; then
    read -r -p "SSH 포트 (기본값 22): " SSH_PORT
    SSH_PORT="${SSH_PORT:-22}"
    [[ "$SSH_PORT" =~ ^[0-9]+$ ]] && (( SSH_PORT >= 1 && SSH_PORT <= 65535 )) ||
        fail "SSH 포트는 1부터 65535 사이의 숫자여야 합니다."
fi

APP_DIR="$DEPLOY_HOME/$PROJECT_NAME"
VENV_DIR="$APP_DIR/venv"
SERVICE_FILE="/etc/systemd/system/$PROJECT_NAME.service"
NGINX_AVAILABLE="/etc/nginx/sites-available/$PROJECT_NAME"
NGINX_ENABLED="/etc/nginx/sites-enabled/$PROJECT_NAME"

[[ ! -e "$APP_DIR" ]] || fail "프로젝트 경로가 이미 있습니다. 기존 파일을 덮어쓰지 않습니다: $APP_DIR"
sudo -v
for config_path in "$SERVICE_FILE" "$NGINX_AVAILABLE" "$NGINX_ENABLED"; do
    if sudo test -e "$config_path" || sudo test -L "$config_path"; then
        fail "같은 이름의 서비스 또는 Nginx 설정이 이미 있습니다. 기존 설정을 덮어쓰지 않습니다: $config_path"
    fi
done

printf '\n패키지를 설치하고 저장소를 내려받습니다...\n'
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
    build-essential git nginx python3-dev python3-pip python3-venv

if [[ -n "$GIT_BRANCH" ]]; then
    git clone --branch "$GIT_BRANCH" -- "$REPOSITORY_URL" "$APP_DIR"
else
    git clone -- "$REPOSITORY_URL" "$APP_DIR"
fi

python3 -m venv "$VENV_DIR"
"$VENV_DIR/bin/python" -m pip install --upgrade pip

if [[ -f "$APP_DIR/requirements.txt" ]]; then
    "$VENV_DIR/bin/pip" install -r "$APP_DIR/requirements.txt"
elif [[ -f "$APP_DIR/pyproject.toml" ]]; then
    "$VENV_DIR/bin/pip" install "$APP_DIR"
fi
"$VENV_DIR/bin/pip" install Flask gunicorn

printf 'Gunicorn systemd 서비스를 구성합니다...\n'
sudo tee "$SERVICE_FILE" >/dev/null <<EOF
[Unit]
Description=Gunicorn service for $PROJECT_NAME
After=network.target

[Service]
User=$DEPLOY_USER
Group=www-data
WorkingDirectory=$APP_DIR
RuntimeDirectory=$PROJECT_NAME
RuntimeDirectoryMode=0750
Environment="PATH=$VENV_DIR/bin"
Environment="PYTHONUNBUFFERED=1"
ExecStart=$VENV_DIR/bin/gunicorn --workers 3 --umask 007 --bind unix:/run/$PROJECT_NAME/$PROJECT_NAME.sock $WSGI_APP
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

printf 'Nginx 리버스 프록시를 구성합니다...\n'
sudo tee "$NGINX_AVAILABLE" >/dev/null <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name $SERVER_NAME;

    location / {
        include proxy_params;
        proxy_pass http://unix:/run/$PROJECT_NAME/$PROJECT_NAME.sock;
    }
}
EOF

sudo ln -s "$NGINX_AVAILABLE" "$NGINX_ENABLED"
if [[ -e /etc/nginx/sites-enabled/default ]]; then
    sudo rm /etc/nginx/sites-enabled/default
fi

if [[ "$ENABLE_UFW" =~ ^[Yy]$ ]]; then
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y ufw
    sudo ufw allow "$SSH_PORT/tcp"
    sudo ufw allow 80/tcp
    sudo ufw --force enable
fi

sudo systemctl daemon-reload
sudo systemctl enable --now "$PROJECT_NAME"
sudo nginx -t
sudo systemctl enable nginx
sudo systemctl restart nginx

sudo systemctl --no-pager --full status "$PROJECT_NAME"
printf '\n설정이 완료되었습니다.\n'
printf '프로젝트 경로: %s\n' "$APP_DIR"
if [[ "$SERVER_NAME" == "_" ]]; then
    printf '웹 주소: http://<서버 공인 IP>/\n'
else
    printf '웹 주소: http://%s/\n' "$SERVER_NAME"
fi
printf '상태 확인: sudo systemctl status %s\n' "$PROJECT_NAME"
printf '클라우드 서버라면 클라우드 방화벽/보안 규칙에서도 TCP 80 포트를 허용해야 합니다.\n'
