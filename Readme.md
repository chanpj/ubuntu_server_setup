# Flask + Gunicorn + Nginx 설정

이 저장소에는 **Ubuntu 24.04**용 초기 HTTP 웹 서버 설정 스크립트와, 나중에 Let's Encrypt HTTPS 인증서를 발급·설정하는 스크립트가 있습니다.

- `setup-flask-gunicon-nginx.sh`: Git 저장소의 Flask 프로젝트를 내려받아 Python 가상환경, Gunicorn(systemd 서비스), Nginx 리버스 프록시를 설정하고 웹 서버를 시작합니다.
- `setup-https.sh`: 실행 중인 Nginx에 Let's Encrypt 인증서를 발급·적용하고 자동 갱신을 설정합니다.

## 시작 전에 준비할 입력값

`setup-flask-gunicon-nginx.sh`를 실행하면 아래 값을 순서대로 입력합니다. 스크립트 안의 변수 이름도 함께 표시했으므로 실행 전에 필요한 정보를 준비할 수 있습니다. 이 변수들은 스크립트가 실행 중 입력을 받아 설정하며, 별도로 환경 변수로 지정할 필요는 없습니다.

| 변수 이름 | 준비할 값 | 필수 여부 및 기본값 |
| --- | --- | --- |
| `PROJECT_NAME` | 프로젝트 이름. 예: `myproject` | 필수. 영문자/숫자로 시작하고 영문자, 숫자, `_`, `-`만 사용할 수 있습니다. |
| `REPOSITORY_URL` | 배포할 Flask 프로젝트의 Git 저장소 URL | 필수. 서버에서 저장소에 접근할 수 있어야 합니다. |
| `GIT_BRANCH` | 내려받을 Git 브랜치 | 선택. 비워 두면 저장소의 기본 브랜치를 사용합니다. |
| `SERVER_NAME` | Nginx에 설정할 도메인 또는 서버 IP | 선택. 비워 두면 `_`를 사용합니다. 나중에 HTTPS를 설정하려면 도메인과 DNS를 준비해야 합니다. |
| `WSGI_APP` | Gunicorn 실행 진입점. 예: `wsgi:app` | 선택. 기본값은 `wsgi:app`입니다. 저장소에 지정한 모듈과 Flask 앱 객체가 있어야 합니다. |
| `ENABLE_UFW` | UFW 방화벽을 설정하고 활성화할지 여부 | 선택. `y`를 입력하면 SSH 및 HTTP 포트를 허용한 뒤 활성화합니다. 기본값은 아니요입니다. |
| `SSH_PORT` | 서버의 SSH 포트 | UFW 활성화 시 입력. 비워 두면 `22`를 사용합니다. |

특히 Git 저장소 URL과 사용할 브랜치, Gunicorn 진입점, 접속할 도메인/IP를 미리 확인하세요. UFW를 활성화할 경우 실제 SSH 포트도 확인해야 합니다.

## 사전 준비

- Ubuntu 24.04 서버와 `sudo` 권한이 있는 일반 사용자
- 배포할 Flask 프로젝트의 Git 저장소 URL
- Flask 앱의 Gunicorn 진입점. 기본값은 `wsgi:app`이며, 저장소에 `wsgi.py` 파일과 `app` 객체가 있어야 합니다.
- 서버 공인 IP 또는 연결할 도메인

프로젝트 저장소에 `requirements.txt`가 있으면 해당 파일의 패키지를 설치합니다. `pyproject.toml`만 있으면 프로젝트 
자체를 설치합니다. 어느 파일도 없으면 스크립트가 Flask와 Gunicorn을 설치합니다.

## 설치 및 실행

먼저 이 설치 스크립트를 Git으로 내려받은 뒤 실행합니다.

```bash
git clone <이 설치 스크립트 저장소 URL>
cd <내려받은 디렉터리>
chmod +x setup-flask-gunicon-nginx.sh
./setup-flask-gunicon-nginx.sh
```

**스크립트 저장소 URL과 배포할 Flask 프로젝트의 Git 저장소 URL은 서로 다를 수 있습니다.** 스크립트를 실행하면 배포할 Flask 프로젝트의 저장소 주소를 별도로 입력합니다.

스크립트 전체를 `sudo`로 실행하지 마세요. 설치 중 필요한 시스템 명령에만 `sudo`가 사용됩니다. 실행 시 sudo 비밀번호를 요청할 수 있습니다.

프로젝트 이름과 같은 디렉터리 또는 systemd/Nginx 설정이 이미 있으면 기존 항목을 덮어쓰지 않고 종료합니다.

## 설치 후 확인

브라우저에서 `http://<서버 공인 IP>/` 또는 입력한 도메인으로 접속합니다. 서비스 상태는 다음 명령으로 확인할 수 있습니다.

```bash
sudo systemctl status <프로젝트 이름>
sudo systemctl status nginx
```

클라우드 서버에서는 클라우드 방화벽/보안 규칙에서도 TCP 80 포트의 인바운드 접속을 허용해야 합니다. 이 스크립트는 HTTP 설정만 구성하며 HTTPS 인증서는 설정하지 않습니다.

## 나중에 HTTPS 인증서 설정하기

먼저 도메인의 DNS `A` 레코드(IPv6를 사용하는 경우 `AAAA` 레코드 포함)가 이 서버를 가리키도록 설정하고, 초기 설정에서 Nginx의 도메인(`server_name`)도 해당 도메인으로 구성해야 합니다. 도메인에 `www` 주소도 사용할 경우, 그 주소의 DNS와 Nginx 설정도 먼저 준비합니다. 인증서 발급 시 도메인을 IP 주소나 와일드카드(`*.example.com`)로 입력할 수 없습니다.

이 저장소를 서버에 내려받지 않았다면 먼저 clone한 뒤, 일반 사용자로 다음 명령을 실행합니다.

```bash
chmod +x setup-https.sh
./setup-https.sh
```

스크립트가 인증서에 포함할 도메인(여러 개면 공백으로 구분)과 만료 알림 이메일을 묻습니다. Certbot이 Nginx 설정을 HTTPS로 변경하고 HTTP 요청을 HTTPS로 리다이렉트합니다. 설치 후 `certbot.timer`가 인증서를 자동 갱신하며, 스크립트가 갱신 테스트도 실행합니다. 전체 과정을 `sudo`로 실행하지 마세요.

발급 및 갱신 검증을 위해 서버의 TCP 80 및 443 포트를 외부에서 접속할 수 있어야 합니다. UFW가 이미 활성화되어 있으면 스크립트가 두 포트를 허용합니다. UFW를 활성화하지는 않으므로, 클라우드 서버는 클라우드 방화벽/보안 규칙에서도 TCP 80과 443을 허용해야 합니다.

인증서와 자동 갱신 타이머를 확인하려면 다음 명령을 사용할 수 있습니다.

```bash
sudo certbot certificates
sudo systemctl status certbot.timer
sudo certbot renew --dry-run
```
