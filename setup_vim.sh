#!/usr/bin/env bash
set -Eeuo pipefail

fail() {
    printf '오류: %s\n' "$*" >&2
    exit 1
}

if [[ "${EUID}" -eq 0 ]]; then
    fail "sudo로 스크립트 전체를 실행하지 마세요. 필요한 시스템 명령에만 sudo를 사용합니다."
fi

command -v sudo >/dev/null 2>&1 || fail "sudo가 필요합니다."

if [[ ! -r /etc/os-release ]]; then
    fail "운영체제 정보를 확인할 수 없습니다."
fi

# Vim 플러그인 설정은 Ubuntu/Debian 계열 Linux를 대상으로 합니다.
# shellcheck source=/dev/null
source /etc/os-release
[[ "${ID:-}" == "ubuntu" || "${ID:-}" == "debian" ]] ||
    fail "Ubuntu 또는 Debian에서 실행해 주세요. 현재 OS: ${PRETTY_NAME:-알 수 없음}"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
VIMRC_SOURCE="$SCRIPT_DIR/.vimrc"
[[ -f "$VIMRC_SOURCE" ]] || fail ".vimrc를 찾을 수 없습니다: $VIMRC_SOURCE"

printf '%s\n' "Vim/Neovim 설정 및 vim-plug 플러그인 설치"
printf '%s\n' "이 스크립트는 .vimrc를 적용하고, vim-plug와 그 설정에 등록된 플러그인을 설치합니다."
printf '%s\n' "설치 중에는 편집기가 열립니다. 플러그인 설치가 끝날 때까지 기다린 뒤 :qa 로 종료하세요."
printf '\n'

read -r -p "사용할 편집기를 선택하세요 [1: Vim (기본값), 2: Neovim]: " EDITOR_CHOICE
case "$EDITOR_CHOICE" in
    ""|1)
        EDITOR_BIN="vim"
        PLUG_DIR="$HOME/.vim/autoload"
        PLUGIN_DIR="$HOME/.vim/plugged"
        CONFIG_PATH="$HOME/.vimrc"
        ;;
    2)
        EDITOR_BIN="nvim"
        PLUG_DIR="$HOME/.config/nvim/autoload"
        PLUGIN_DIR="$HOME/.config/nvim/plugged"
        CONFIG_PATH="$HOME/.config/nvim/init.vim"
        ;;
    *)
        fail "선택 항목은 1 또는 2여야 합니다."
        ;;
esac

printf '\n필요한 패키지(git, curl, Python 3, flake8, ack 및 편집기)를 설치합니다...\n'
sudo apt-get update
if [[ "$EDITOR_BIN" == "vim" ]]; then
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
        ack curl git python3 python3-flake8 vim
else
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
        ack curl git neovim python3 python3-flake8
fi

printf '\n저장소의 .vimrc를 편집기 설정 경로에 복사합니다...\n'
mkdir -p "$(dirname "$CONFIG_PATH")"
if [[ -e "$CONFIG_PATH" || -L "$CONFIG_PATH" ]]; then
    BACKUP_PATH="$CONFIG_PATH.backup.$(date +%Y%m%d%H%M%S)"
    mv -- "$CONFIG_PATH" "$BACKUP_PATH"
    printf '기존 설정을 백업했습니다: %s\n' "$BACKUP_PATH"
fi
cp -- "$VIMRC_SOURCE" "$CONFIG_PATH"

printf '\nvim-plug 플러그인 매니저를 설치하거나 확인합니다...\n'
mkdir -p "$PLUG_DIR"
PLUG_FILE="$PLUG_DIR/plug.vim"
if [[ ! -s "$PLUG_FILE" ]]; then
    curl -fLo "$PLUG_FILE" \
        https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
else
    printf 'vim-plug가 이미 설치되어 있습니다: %s\n' "$PLUG_FILE"
fi

printf '\n등록된 Vim 플러그인을 설치합니다...\n'
printf '%s\n' "편집기가 열리면 설치 완료를 기다린 후 :qa 를 입력해 종료하세요."
mkdir -p "$PLUGIN_DIR"
"$EDITOR_BIN" +PlugInstall

printf '\n설정이 완료되었습니다.\n'
printf '설정 파일: %s\n' "$CONFIG_PATH"
printf 'vim-plug: %s\n' "$PLUG_FILE"
printf '플러그인 디렉터리: %s\n' "$PLUGIN_DIR"
printf '나중에 플러그인을 다시 설치/업데이트하려면 편집기에서 :PlugInstall 또는 :PlugUpdate 를 실행하세요.\n'
printf '%s\n' "Python 검사 기능은 flake8, 프로젝트 검색 기능은 ack 패키지를 사용합니다."
printf '%s\n' "파일 아이콘을 사용하려면 Nerd Font를 터미널 글꼴로 별도 설정해야 합니다."
