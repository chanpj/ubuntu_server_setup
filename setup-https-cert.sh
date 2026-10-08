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

printf '%s\n' "Let's Encrypt HTTPS 설정 (Ubuntu 24.04)"
printf '%s\n' "도메인의 DNS가 이 서버를 가리키고, 외부에서 TCP 80/443 포트에 접속할 수 있어야 합니다."

read -r -p "HTTPS를 적용할 도메인(들, 공백 구분; 예: example.com www.example.com): " DOMAIN_INPUT
[[ -n "$DOMAIN_INPUT" ]] || fail "도메인을 한 개 이상 입력해야 합니다."
read -r -a DOMAINS <<< "$DOMAIN_INPUT"

for domain in "${DOMAINS[@]}"; do
    [[ "$domain" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$ ]] ||
        fail "유효한 도메인 형식이 아닙니다: $domain"
done

read -r -p "인증서 만료 알림을 받을 이메일 주소: " EMAIL
[[ "$EMAIL" =~ ^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$ ]] ||
    fail "유효한 이메일 주소를 입력해야 합니다."

sudo -v
sudo systemctl is-active --quiet nginx ||
    fail "Nginx가 실행 중이지 않습니다. 먼저 Flask/Nginx 설치를 완료하고 Nginx 상태를 확인하세요."
sudo nginx -t

NGINX_CONFIG="$(sudo nginx -T 2>&1)"
for domain in "${DOMAINS[@]}"; do
    if ! awk -v target="$domain" '
        $1 == "server_name" {
            for (i = 2; i <= NF; i++) {
                gsub(/[;{}]/, "", $i)
                if ($i == target) found = 1
            }
        }
        END { exit !found }
    ' <<< "$NGINX_CONFIG"; then
        fail "Nginx 설정에 '$domain'이 server_name으로 없습니다. 초기 설치 시 도메인을 설정하고 Nginx를 확인하세요."
    fi
done

printf '\nCertbot과 Nginx 플러그인을 설치합니다...\n'
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y certbot python3-certbot-nginx

if sudo ufw status | grep -q '^Status: active'; then
    sudo ufw allow 80/tcp
    sudo ufw allow 443/tcp
else
    printf '%s\n' "UFW가 비활성 상태이므로 변경하지 않았습니다."
fi

CERTBOT_ARGS=(--nginx --non-interactive --agree-tos --redirect --email "$EMAIL")
for domain in "${DOMAINS[@]}"; do
    CERTBOT_ARGS+=(-d "$domain")
done

printf '\n인증서를 발급하고 Nginx에 HTTPS 및 HTTP→HTTPS 리다이렉트를 설정합니다...\n'
sudo certbot "${CERTBOT_ARGS[@]}"

printf '\n인증서 자동 갱신 타이머를 활성화하고 갱신 테스트를 실행합니다...\n'
sudo systemctl enable --now certbot.timer
sudo certbot renew --dry-run

sudo nginx -t
sudo systemctl reload nginx

printf '\nHTTPS 설정이 완료되었습니다.\n'
printf '주소: https://%s/\n' "${DOMAINS[0]}"
printf '타이머 상태: sudo systemctl status certbot.timer\n'
printf '인증서 확인: sudo certbot certificates\n'
printf '수동 갱신 테스트: sudo certbot renew --dry-run\n'
printf '%s\n' "클라우드 서버라면 클라우드 방화벽/보안 규칙에서도 TCP 80 및 443 포트를 허용해야 합니다."
