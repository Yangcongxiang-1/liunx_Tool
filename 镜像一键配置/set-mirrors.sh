#!/usr/bin/env bash
# ============================================================
# 一键设置镜像源脚本 (Mirror Setup Script)
# 支持: npm / bun / pnpm / yarn / pip / gem / cargo / go
#       / conda / composer / apt / docker / nvm / flutter
# 镜像源: 阿里云 | 清华 TUNA | 中科大 USTC | 华为云
# ============================================================
# 作者: Sisyphus
# 适用系统: Linux / macOS
# ============================================================

set -euo pipefail
IFS=$'\n\t'

# ---------- 颜色定义 ----------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# ---------- 镜像源 URL 映射 ----------
# 索引: 1=阿里云, 2=清华, 3=中科大, 4=华为云, 0=恢复官方
MIRROR_NAME=("" "阿里云" "清华大学 TUNA" "中科大 USTC" "华为云")

# npm registry
NPM_URL=("https://registry.npmjs.org" \
         "https://registry.npmmirror.com" \
         "https://mirrors.tuna.tsinghua.edu.cn/npm-registry" \
         "https://mirrors.ustc.edu.cn/npm-registry" \
         "https://mirrors.huaweicloud.com/repository/npm")

# pip index
PIP_URL=("https://pypi.org/simple" \
         "https://mirrors.aliyun.com/pypi/simple" \
         "https://pypi.tuna.tsinghua.edu.cn/simple" \
         "https://pypi.mirrors.ustc.edu.cn/simple" \
         "https://mirrors.huaweicloud.com/repository/pypi/simple")

# gem source
GEM_URL=("https://rubygems.org" \
         "https://mirrors.aliyun.com/rubygems" \
         "https://mirrors.tuna.tsinghua.edu.cn/rubygems" \
         "https://mirrors.ustc.edu.cn/rubygems" \
         "https://mirrors.huaweicloud.com/repository/rubygems")

# cargo (Rust) - 用于 ~/.cargo/config.toml
CARGO_URL=("https://crates.io" \
           "https://mirrors.aliyun.com/crates" \
           "https://mirrors.tuna.tsinghua.edu.cn/git/crates.io-index.git" \
           "https://mirrors.ustc.edu.cn/crates.io-index" \
           "https://mirrors.huaweicloud.com/repository/cargo")

# go proxy
GO_PROXY=("https://proxy.golang.org,direct" \
          "https://mirrors.aliyun.com/goproxy,direct" \
          "https://goproxy.io,direct" \
          "https://goproxy.cn,direct" \
          "https://goproxy.huaweicloud.com,direct")

# conda 镜像 (channels)
CONDA_CHANNEL=("defaults" \
               "https://mirrors.aliyun.com/anaconda" \
               "https://mirrors.tuna.tsinghua.edu.cn/anaconda" \
               "https://mirrors.ustc.edu.cn/anaconda" \
               "https://mirrors.huaweicloud.com/anaconda")

# composer (PHP)
COMPOSER_URL=("https://packagist.org" \
              "https://mirrors.aliyun.com/composer" \
              "https://mirrors.tuna.tsinghua.edu.cn/composer" \
              "https://packagist.mirrors.ustc.edu.cn" \
              "https://mirrors.huaweicloud.com/repository/php")

# nvm mirror (node dist)
NVM_NODEJS_ORG_MIRROR=("https://nodejs.org/dist" \
                       "https://npmmirror.com/mirrors/node" \
                       "https://mirrors.tuna.tsinghua.edu.cn/node-release" \
                       "https://mirrors.ustc.edu.cn/node" \
                       "https://mirrors.huaweicloud.com/nodejs")

# flutter mirror
FLUTTER_STORAGE=("https://storage.googleapis.com" \
                 "https://mirrors.aliyun.com/flutter" \
                 "https://mirrors.tuna.tsinghua.edu.cn/flutter" \
                 "https://mirrors.ustc.edu.cn/flutter" \
                 "https://mirrors.huaweicloud.com/flutter")
DART_PUB=("https://pub.dev" \
          "https://pub.flutter-io.cn" \
          "https://mirrors.tuna.tsinghua.edu.cn/dart-pub" \
          "https://mirrors.ustc.edu.cn/dart-pub" \
          "https://mirrors.huaweicloud.com/dart-pub")

# docker mirror (daemon.json)
DOCKER_MIRROR=("" \
               "https://registry.cn-hangzhou.aliyuncs.com" \
               "https://docker.mirrors.tuna.tsinghua.edu.cn" \
               "https://docker.mirrors.ustc.edu.cn" \
               "https://docker.mirrors.huaweicloud.com")

# git 加速代理 (insteadOf + HTTP 代理)
# 模式: 0=恢复官方, 1=ghproxy, 2=自定义 HTTP 代理
GIT_ACCEL_MODE=("恢复官方" "ghproxy 加速" "自定义 HTTP 代理")
# ghproxy 服务列表 (用于 insteadOf 替换)
GHPROXY_URLS=("" \
              "https://ghproxy.net/https://github.com/" \
              "https://ghproxy.com/https://github.com/" \
              "https://gh.api.99988866.xyz/https://github.com/")
GHPROXY_NAME=("" "ghproxy.net" "ghproxy.com" "gh.api.99988866.xyz")

# ============================================================
# 工具函数
# ============================================================

print_banner() {
    cat << 'EOF'
  ╔══════════════════════════════════════════════════╗
  ║         🌐 一键镜像源配置工具 v2.1               ║
  ║      npm / bun / pnpm / yarn / pip / gem        ║
  ║     cargo / go / conda / composer / apt         ║
  ║     docker / nvm / flutter / homebrew           ║
  ║     🔥 git 加速 (ghproxy / HTTP 代理)           ║
  ╚══════════════════════════════════════════════════╝
EOF
}

print_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_step()  { echo -e "\n${CYAN}━━━ $1 ━━━${NC}"; }
print_title() { echo -e "\n${BOLD}${BLUE}▶ $1${NC}"; }

# 检测命令是否存在
has_cmd() { command -v "$1" &>/dev/null; }

# 检查当前是否为 root/sudo
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_warn "部分操作需要 root 权限 (如 apt, docker)"
        print_info "建议使用: sudo bash $0"
        echo ""
        read -rp "是否继续? (y/n) " -n 1 ans
        echo ""
        [[ "$ans" != "y" && "$ans" != "Y" ]] && exit 1
    fi
}

# 备份文件
backup_file() {
    local f="$1"
    if [[ -f "$f" ]]; then
        cp "$f" "${f}.bak.$(date +%Y%m%d%H%M%S)"
        print_info "已备份: $f → ${f}.bak.*"
    fi
}

# ============================================================
# 镜像源选择菜单
# ============================================================

select_mirror() {
    local name="$1"
    echo ""
    echo "选择 ${name} 镜像源:"
    echo "  1) 阿里云"
    echo "  2) 清华大学 TUNA"
    echo "  3) 中科大 USTC"
    echo "  4) 华为云"
    echo "  0) 恢复官方源"
    echo ""
    read -rp "请输入编号 (默认 1): " choice
    # 默认阿里云
    choice=${choice:-1}
    # 检查是否为数字且在 0-4 范围
    if ! [[ "$choice" =~ ^[0-4]$ ]]; then
        print_warn "无效选择，使用阿里云 (1)"
        choice=1
    fi
    echo "$choice"
}

# ============================================================
# 各包管理器配置函数
# ============================================================

# ----- npm -----
setup_npm() {
    print_title "npm"
    local idx="$1"
    local url="${NPM_URL[$idx]}"
    if ! has_cmd npm; then
        print_warn "npm 未安装，跳过"
        return
    fi
    local current
    current=$(npm config get registry 2>/dev/null || echo "unknown")
    print_info "当前: $current"
    npm config set registry "$url" &>/dev/null
    print_info "设置: npm registry → $url"
    # 验证
    local verify
    verify=$(npm config get registry 2>/dev/null)
    if [[ "$verify" == "$url" ]]; then
        print_info "✅ npm registry 配置成功"
    else
        print_error "❌ npm registry 配置失败"
    fi
}

# ----- pnpm -----
setup_pnpm() {
    print_title "pnpm"
    local idx="$1"
    local url="${NPM_URL[$idx]}"
    if ! has_cmd pnpm; then
        print_warn "pnpm 未安装，跳过"
        return
    fi
    local current
    current=$(pnpm config get registry 2>/dev/null || echo "unknown")
    print_info "当前: $current"
    pnpm config set registry "$url" &>/dev/null
    print_info "设置: pnpm registry → $url"
    print_info "✅ pnpm registry 配置成功"
}

# ----- yarn -----
setup_yarn() {
    print_title "yarn"
    local idx="$1"
    local url="${NPM_URL[$idx]}"
    if ! has_cmd yarn; then
        print_warn "yarn 未安装，跳过"
        return
    fi
    local current
    current=$(yarn config get registry 2>/dev/null || echo "unknown")
    print_info "当前: $current"
    yarn config set registry "$url" &>/dev/null
    print_info "设置: yarn registry → $url"
    print_info "✅ yarn registry 配置成功"
}

# ----- bun -----
setup_bun() {
    print_title "bun"
    local idx="$1"
    local url="${NPM_URL[$idx]}"
    if ! has_cmd bun; then
        print_warn "bun 未安装，跳过"
        return
    fi
    # bun 读取 npm registry 配置，同时也支持自身配置
    # bun 的 registry 可以通过 BUN_CONFIG_REGISTRY 环境变量或 bunfig.toml 配置
    local config_file="$HOME/.bunfig.toml"
    if [[ -f "$config_file" ]]; then
        backup_file "$config_file"
    fi
    cat > "$config_file" <<< "[install]
registry = \"${url}\"
"
    print_info "设置: bun registry → $url (写入 ~/.bunfig.toml)"
    print_info "✅ bun registry 配置成功"
}

# ----- pip -----
setup_pip() {
    print_title "pip"
    local idx="$1"
    local url="${PIP_URL[$idx]}"
    if ! has_cmd pip; then
        print_warn "pip 未安装，跳过"
        return
    fi
    local pip_dir="$HOME/.pip"
    mkdir -p "$pip_dir"
    local config_file="$pip_dir/pip.conf"
    backup_file "$config_file"
    cat > "$config_file" <<< "[global]
index-url = ${url}
trusted-host = $(echo "$url" | sed -E 's|https?://([^/]+).*|\1|')
"
    print_info "设置: pip → $url (写入 ~/.pip/pip.conf)"
    # 验证
    local verify
    verify=$(pip config list 2>/dev/null | grep "index-url" || true)
    print_info "📋 pip 当前配置: $verify"
    print_info "✅ pip 配置成功"
}

# ----- gem (Ruby) -----
setup_gem() {
    print_title "gem (Ruby)"
    local idx="$1"
    local url="${GEM_URL[$idx]}"
    if ! has_cmd gem; then
        print_warn "gem 未安装，跳过"
        return
    fi
    local current
    current=$(gem sources -l 2>/dev/null | head -2 | tail -1 || echo "unknown")
    print_info "当前源: $current"

    if [[ $idx -eq 0 ]]; then
        # 恢复官方
        gem sources --remove "$(gem sources -l 2>/dev/null | grep -v '^\*\*\*' | head -1)" &>/dev/null || true
        gem sources --add "$url" &>/dev/null
    else
        # 移除当前源，添加新源
        gem sources --remove "$(gem sources -l 2>/dev/null | grep -v '^\*\*\*' | head -1)" &>/dev/null || true
        gem sources --add "$url" &>/dev/null
    fi
    print_info "设置: gem → $url"
    print_info "✅ gem 配置成功"
}

# ----- Bundler -----
setup_bundler() {
    print_title "bundler"
    local idx="$1"
    local url="${GEM_URL[$idx]}"
    if ! has_cmd bundle; then
        print_warn "bundler 未安装，跳过"
        return
    fi
    bundle config --global mirror.rubygems.org "$url" &>/dev/null || true
    print_info "设置: bundle mirror → $url"
    print_info "✅ bundler 配置成功"
}

# ----- cargo (Rust) -----
setup_cargo() {
    print_title "cargo (Rust)"
    local idx="$1"
    local url="${CARGO_URL[$idx]}"
    if ! has_cmd cargo; then
        print_warn "cargo 未安装，跳过"
        return
    fi
    local cfg_dir="$HOME/.cargo"
    mkdir -p "$cfg_dir"
    local config_file="$cfg_dir/config.toml"
    backup_file "$config_file"

    if [[ $idx -eq 0 ]]; then
        # 恢复官方——直接清空或删除
        rm -f "$config_file" 2>/dev/null || true
        print_info "已删除 cargo 镜像配置 (恢复官方)"
    else
        cat > "$config_file" <<< '[source.crates-io]
replace-with = "mirror"

[source.mirror]
registry = "'"${url}"'"
'
        print_info "设置: cargo → $url (写入 ~/.cargo/config.toml)"
    fi
    print_info "✅ cargo 配置成功"
}

# ----- rustup -----
setup_rustup() {
    print_title "rustup"
    local idx="$1"
    if ! has_cmd rustup; then
        print_warn "rustup 未安装，跳过"
        return
    fi
    local mirror=""
    case "$idx" in
        1) mirror="https://mirrors.aliyun.com/rustup" ;;
        2) mirror="https://mirrors.tuna.tsinghua.edu.cn/rustup" ;;
        3) mirror="https://mirrors.ustc.edu.cn/rustup-static" ;;
        4) mirror="https://mirrors.huaweicloud.com/rustup" ;;
        *) mirror="" ;; # 官方
    esac
    if [[ -n "$mirror" ]]; then
        print_info "如需设置 rustup 镜像，执行:"
        print_info "  export RUSTUP_DIST_SERVER=$mirror"
        print_info "建议添加到 ~/.bashrc 或 ~/.zshrc"
        # 写入 profile 辅助
        local profile_file="$HOME/.bashrc"
        [[ -f "$HOME/.zshrc" ]] && profile_file="$HOME/.zshrc"
        if ! grep -q "RUSTUP_DIST_SERVER" "$profile_file" 2>/dev/null; then
            {
                echo ""
                echo "# rustup mirror (by set-mirrors.sh)"
                echo "export RUSTUP_DIST_SERVER=$mirror"
                echo "export RUSTUP_UPDATE_ROOT=${mirror}/rustup"
            } >> "$profile_file"
            print_info "已追加环境变量到 $profile_file"
        fi
    else
        print_info "rustup 恢复官方源，请手动移除 ~/.bashrc 中的 RUSTUP_DIST_SERVER"
    fi
    print_info "✅ rustup 配置完成"
}

# ----- go -----
setup_go() {
    print_title "Go"
    local idx="$1"
    local proxy="${GO_PROXY[$idx]}"
    if ! has_cmd go; then
        print_warn "go 未安装，跳过"
        return
    fi
    local current
    current=$(go env GOPROXY 2>/dev/null || echo "unknown")
    print_info "当前 GOPROXY: $current"
    go env -w GOPROXY="$proxy" &>/dev/null
    print_info "设置: GOPROXY → $proxy"
    local verify
    verify=$(go env GOPROXY 2>/dev/null)
    if [[ "$verify" == "$proxy" ]]; then
        print_info "✅ Go proxy 配置成功"
    else
        print_error "❌ Go proxy 配置失败 (当前: $verify)"
    fi
}

# ----- conda -----
setup_conda() {
    print_title "conda"
    local idx="$1"
    local url="${CONDA_CHANNEL[$idx]}"
    if ! has_cmd conda; then
        print_warn "conda 未安装，跳过"
        return
    fi
    if [[ $idx -eq 0 ]]; then
        conda config --remove-key channels &>/dev/null || true
        conda config --add channels defaults &>/dev/null
        print_info "恢复 conda 官方 channels"
    else
        # conda 配置 channels
        conda config --remove-key channels &>/dev/null || true
        conda config --add channels "${url}/pkgs/main/" &>/dev/null
        conda config --add channels "${url}/pkgs/free/" &>/dev/null
        conda config --add channels "${url}/pkgs/r/" &>/dev/null
        conda config --add channels "${url}/pkgs/msys2/" &>/dev/null
        conda config --set show_channel_urls yes &>/dev/null
        print_info "设置: conda channels → $url"
    fi
    print_info "✅ conda 配置成功"
}

# ----- composer (PHP) -----
setup_composer() {
    print_title "composer (PHP)"
    local idx="$1"
    local url="${COMPOSER_URL[$idx]}"
    if ! has_cmd composer; then
        print_warn "composer 未安装，跳过"
        return
    fi
    if [[ $idx -eq 0 ]]; then
        composer config -g repos.packagist false &>/dev/null || true
        print_info "恢复 composer 官方源"
    else
        composer config -g repos.packagist composer "$url" &>/dev/null
        print_info "设置: composer → $url"
    fi
    print_info "✅ composer 配置成功"
}

# ----- apt (Linux) -----
setup_apt() {
    print_title "apt (APT 软件源)"
    local idx="$1"
    if [[ ! -d /etc/apt ]]; then
        print_warn "非 APT 系统，跳过"
        return
    fi
    if [[ $EUID -ne 0 ]]; then
        print_warn "apt 配置需要 root 权限，请用 sudo 执行本脚本"
        print_info "跳过 apt 配置"
        return
    fi

    # 检测当前发行版
    local os_id=""
    local os_codename=""
    if [[ -f /etc/os-release ]]; then
        os_id=$(grep ^ID= /etc/os-release | cut -d= -f2 | tr -d '"')
        os_codename=$(grep ^VERSION_CODENAME= /etc/os-release | cut -d= -f2 | tr -d '"')
    fi
    if [[ -z "$os_id" || -z "$os_codename" ]]; then
        print_warn "无法检测发行版信息，跳过 apt 配置"
        return
    fi
    print_info "发行版: $os_id / $os_codename"

    local source_file="/etc/apt/sources.list"
    if [[ "$os_id" == "ubuntu" ]]; then
        backup_file "$source_file"
        case "$idx" in
            1) # 阿里云
                cat > "$source_file" <<< "deb https://mirrors.aliyun.com/ubuntu/ ${os_codename} main restricted universe multiverse
deb https://mirrors.aliyun.com/ubuntu/ ${os_codename}-security main restricted universe multiverse
deb https://mirrors.aliyun.com/ubuntu/ ${os_codename}-updates main restricted universe multiverse
deb https://mirrors.aliyun.com/ubuntu/ ${os_codename}-backports main restricted universe multiverse"
                ;;
            2) # 清华
                cat > "$source_file" <<< "deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ ${os_codename} main restricted universe multiverse
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ ${os_codename}-security main restricted universe multiverse
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ ${os_codename}-updates main restricted universe multiverse
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ ${os_codename}-backports main restricted universe multiverse"
                ;;
            3) # 中科大
                cat > "$source_file" <<< "deb https://mirrors.ustc.edu.cn/ubuntu/ ${os_codename} main restricted universe multiverse
deb https://mirrors.ustc.edu.cn/ubuntu/ ${os_codename}-security main restricted universe multiverse
deb https://mirrors.ustc.edu.cn/ubuntu/ ${os_codename}-updates main restricted universe multiverse
deb https://mirrors.ustc.edu.cn/ubuntu/ ${os_codename}-backports main restricted universe multiverse"
                ;;
            4) # 华为云
                cat > "$source_file" <<< "deb https://mirrors.huaweicloud.com/ubuntu/ ${os_codename} main restricted universe multiverse
deb https://mirrors.huaweicloud.com/ubuntu/ ${os_codename}-security main restricted universe multiverse
deb https://mirrors.huaweicloud.com/ubuntu/ ${os_codename}-updates main restricted universe multiverse
deb https://mirrors.huaweicloud.com/ubuntu/ ${os_codename}-backports main restricted universe multiverse"
                ;;
            0) # 官方
                cat > "$source_file" <<< "deb http://archive.ubuntu.com/ubuntu/ ${os_codename} main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu/ ${os_codename}-security main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu/ ${os_codename}-updates main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu/ ${os_codename}-backports main restricted universe multiverse"
                ;;
        esac
        print_info "写入: $source_file (${MIRROR_NAME[$idx]})"
        apt-get update --quiet=2 || print_warn "apt update 有错误，但已设置镜像源"
        print_info "✅ apt 源配置成功"
    elif [[ "$os_id" == "debian" ]]; then
        backup_file "$source_file"
        local debian_mirror=""
        case "$idx" in
            1) debian_mirror="https://mirrors.aliyun.com/debian" ;;
            2) debian_mirror="https://mirrors.tuna.tsinghua.edu.cn/debian" ;;
            3) debian_mirror="https://mirrors.ustc.edu.cn/debian" ;;
            4) debian_mirror="https://mirrors.huaweicloud.com/debian" ;;
            0) debian_mirror="http://deb.debian.org/debian" ;;
        esac
        cat > "$source_file" <<< "deb ${debian_mirror} ${os_codename} main contrib non-free
deb ${debian_mirror} ${os_codename}-updates main contrib non-free
deb ${debian_mirror} ${os_codename}-backports main contrib non-free
deb https://security.debian.org/debian-security ${os_codename}-security main contrib non-free"
        apt-get update --quiet=2 || print_warn "apt update 有错误"
        print_info "✅ Debian apt 源配置成功"
    else
        print_warn "不支持的发行版: $os_id，请手动配置 apt 源"
    fi
}

# ----- Docker -----
setup_docker() {
    print_title "Docker"
    local idx="$1"
    local url="${DOCKER_MIRROR[$idx]}"
    if ! has_cmd docker; then
        print_warn "docker 未安装，跳过"
        return
    fi
    if [[ $EUID -ne 0 ]]; then
        print_warn "docker 配置需要 root 权限，跳过"
        print_info "如需配置，请用 sudo 执行: bash $0"
        return
    fi
    local cfg_dir="/etc/docker"
    mkdir -p "$cfg_dir"
    local config_file="$cfg_dir/daemon.json"
    backup_file "$config_file"

    if [[ $idx -eq 0 ]]; then
        # 恢复官方——移除 registry-mirrors
        if [[ -f "$config_file" ]]; then
            # 简单处理：如果文件只包含 registry-mirrors 则删除，否则用 python3/jq 处理
            if has_cmd jq; then
                jq 'del(."registry-mirrors")' "$config_file" > "${config_file}.tmp" && mv "${config_file}.tmp" "$config_file"
            elif has_cmd python3; then
                python3 -c "
import json
with open('$config_file') as f: cfg = json.load(f)
cfg.pop('registry-mirrors', None)
with open('$config_file', 'w') as f: json.dump(cfg, f, indent=2)
"
            else
                print_warn "需要 jq 或 python3 来处理 JSON，跳过"
                return
            fi
        fi
        print_info "已移除 docker registry-mirrors"
    else
        local mirror_json="[\"${url}\"]"
        if [[ -f "$config_file" ]]; then
            if has_cmd jq; then
                jq --argjson m "$mirror_json" '."registry-mirrors" = $m' "$config_file" > "${config_file}.tmp" && mv "${config_file}.tmp" "$config_file"
            elif has_cmd python3; then
                python3 -c "
import json
with open('$config_file') as f: cfg = json.load(f)
cfg['registry-mirrors'] = $mirror_json
with open('$config_file', 'w') as f: json.dump(cfg, f, indent=2)
" 2>/dev/null
            else
                cat > "$config_file" <<< "{
  \"registry-mirrors\": $mirror_json
}"
            fi
        else
            cat > "$config_file" <<< "{
  \"registry-mirrors\": $mirror_json
}"
        fi
        print_info "设置: docker registry-mirror → $url (写入 /etc/docker/daemon.json)"
        # 重启 docker
        print_info "重启 Docker 服务..."
        systemctl daemon-reload 2>/dev/null || true
        systemctl restart docker 2>/dev/null || service docker restart 2>/dev/null || print_warn "请手动重启 Docker"
        print_info "✅ Docker 镜像加速器配置成功"
    fi
}

# ----- nvm / node 镜像 -----
setup_nvm() {
    print_title "nvm / Node.js"
    local idx="$1"
    local url="${NVM_NODEJS_ORG_MIRROR[$idx]}"

    # 设置 NVM_NODEJS_ORG_MIRROR
    if has_cmd nvm; then
        print_info "nvm 已安装"
    fi
    if [[ -d "$HOME/.nvm" ]]; then
        print_info "检测到 ~/.nvm"

        # 写入 nvm 配置
        local nvm_cfg_file="$HOME/.nvm/nvm.sh"
        if [[ $idx -eq 0 ]]; then
            print_info "移除 NVM_NODEJS_ORG_MIRROR 环境变量设置"
            # 提示手动处理
        else
            # 追加到 .bashrc/.zshrc
            local rc_file="$HOME/.bashrc"
            [[ -f "$HOME/.zshrc" ]] && rc_file="$HOME/.zshrc"
            if ! grep -q "NVM_NODEJS_ORG_MIRROR" "$rc_file" 2>/dev/null; then
                {
                    echo ""
                    echo "# nvm mirror (by set-mirrors.sh)"
                    echo "export NVM_NODEJS_ORG_MIRROR=${url}"
                } >> "$rc_file"
                print_info "已追加 NVM_NODEJS_ORG_MIRROR 到 $rc_file"
            else
                print_info "NVM_NODEJS_ORG_MIRROR 已存在 $rc_file 中"
            fi
            print_info "设置: NVM_NODEJS_ORG_MIRROR → $url"
        fi
    else
        print_warn "nvm 未安装，跳过"
        return
    fi
    print_info "✅ nvm 镜像配置成功"
}

# ----- Flutter / Dart -----
setup_flutter() {
    print_title "Flutter / Dart"
    local idx="$1"
    local flutter_url="${FLUTTER_STORAGE[$idx]}"
    local pub_url="${DART_PUB[$idx]}"
    if ! has_cmd flutter && ! has_cmd dart; then
        print_warn "Flutter/Dart 未安装，跳过"
        return
    fi
    # 设置 Flutter 环境变量
    local rc_file="$HOME/.bashrc"
    [[ -f "$HOME/.zshrc" ]] && rc_file="$HOME/.zshrc"

    for var_name in "FLUTTER_STORAGE_BASE_URL" "PUB_HOSTED_URL"; do
        if grep -q "$var_name" "$rc_file" 2>/dev/null; then
            print_info "$var_name 已存在 $rc_file 中"
        else
            local val="$flutter_url"
            [[ "$var_name" == "PUB_HOSTED_URL" ]] && val="$pub_url"
            {
                echo ""
                echo "# flutter/dart mirror (by set-mirrors.sh)"
                echo "export $var_name=${val}"
            } >> "$rc_file"
            print_info "已追加 $var_name 到 $rc_file"
        fi
    done

    # 如果是恢复官方
    if [[ $idx -eq 0 ]]; then
        print_info "如需移除镜像配置，请手动编辑 $rc_file 中相关行"
    fi
    print_info "✅ Flutter/Dart 镜像配置成功"
}

# ----- Homebrew (macOS/Linux) -----
setup_brew() {
    print_title "Homebrew"
    local idx="$1"
    if ! has_cmd brew; then
        print_warn "Homebrew 未安装，跳过"
        return
    fi
    # brew 更换镜像主要通过 git remote 和 HOMEBREW_* 环境变量
    local brew_path
    brew_path=$(brew --repo 2>/dev/null || echo "")
    [[ -z "$brew_path" ]] && { print_warn "brew repo 路径获取失败"; return; }

    local brew_core=""
    local brew_bottle=""
    case "$idx" in
        1) # 阿里云 — brew 没有阿里云镜像
            print_warn "阿里云没有 Homebrew 镜像，推荐清华或中科大"
            return
            ;;
        2) # 清华
            brew_core="https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/homebrew-core.git"
            brew_bottle="https://mirrors.tuna.tsinghua.edu.cn/homebrew-bottles"
            ;;
        3) # 中科大
            brew_core="https://mirrors.ustc.edu.cn/homebrew-core.git"
            brew_bottle="https://mirrors.ustc.edu.cn/homebrew-bottles"
            ;;
        4) # 华为云
            brew_core="https://mirrors.huaweicloud.com/git/homebrew/homebrew-core.git"
            brew_bottle="https://mirrors.huaweicloud.com/homebrew-bottles"
            ;;
        0) # 官方
            brew_core="https://github.com/Homebrew/homebrew-core.git"
            brew_bottle=""
            ;;
    esac

    if [[ -n "$brew_core" ]]; then
        cd "$brew_path" && git remote set-url origin "$brew_core" 2>/dev/null || true
        print_info "设置 brew core 镜像: $brew_core"
    fi
    if [[ -n "$brew_bottle" ]]; then
        local rc_file="$HOME/.bashrc"
        [[ -f "$HOME/.zshrc" ]] && rc_file="$HOME/.zshrc"
        if ! grep -q "HOMEBREW_BOTTLE_DOMAIN" "$rc_file" 2>/dev/null; then
            {
                echo ""
                echo "# homebrew mirror (by set-mirrors.sh)"
                echo "export HOMEBREW_BOTTLE_DOMAIN=${brew_bottle}"
            } >> "$rc_file"
            print_info "已追加 HOMEBREW_BOTTLE_DOMAIN 到 $rc_file"
        fi
        print_info "设置: HOMEBREW_BOTTLE_DOMAIN → $brew_bottle"
    fi
    print_info "✅ Homebrew 镜像配置成功"
}

# ----- Git 加速 -----
setup_git() {
    print_title "Git 加速"
    local mode="$1"
    # mode: 0=恢复官方, 1=ghproxy, 2=自定义 HTTP 代理

    if ! has_cmd git; then
        print_warn "git 未安装，跳过"
        return
    fi

    # 先展示当前配置
    local current_insteadOf
    current_insteadOf=$(git config --global --get-regexp 'url\.' 2>/dev/null || echo "(无)")
    local current_proxy
    current_proxy=$(git config --global --get http.proxy 2>/dev/null || echo "(无)")
    print_info "当前 insteadOf: $current_insteadOf"
    print_info "当前 HTTP 代理: $current_proxy"

    case "$mode" in
        0)
            # 恢复官方——移除所有 insteadof 和代理
            local urls
            urls=$(git config --global --get-regexp 'url\.' 2>/dev/null | awk '{print $1}' | sed 's/\.insteadof$//' | sort -u) || true
            while IFS= read -r u; do
                [[ -z "$u" ]] && continue
                git config --global --unset-all "${u}.insteadof" 2>/dev/null || true
                print_info "已移除 insteadof: ${u}.insteadof"
            done <<< "$urls"
            git config --global --unset http.proxy 2>/dev/null || true
            git config --global --unset https.proxy 2>/dev/null || true
            print_info "✅ Git 已恢复官方配置 (无加速)"
            ;;
        1)
            # ghproxy 加速
            echo ""
            echo "选择 ghproxy 服务:"
            for i in "${!GHPROXY_NAME[@]}"; do
                [[ $i -eq 0 ]] && continue
                echo "  $i) ${GHPROXY_NAME[$i]}"
            done
            echo ""
            read -rp "请输入编号 (默认 1): " gidx
            gidx=${gidx:-1}
            if ! [[ "$gidx" =~ ^[1-3]$ ]]; then gidx=1; fi

            local proxy_url="${GHPROXY_URLS[$gidx]}"
            local proxy_name="${GHPROXY_NAME[$gidx]}"

            # 先清理已有的 insteadof 配置
            local old_urls
            old_urls=$(git config --global --get-regexp 'url\.' 2>/dev/null | awk '{print $1}' | sed 's/\.insteadof$//' | sort -u) || true
            while IFS= read -r u; do
                [[ -z "$u" ]] && continue
                git config --global --unset-all "${u}.insteadof" 2>/dev/null || true
            done <<< "$old_urls"

            # 设置 insteadof
            git config --global "url.${proxy_url}.insteadof" "https://github.com/"
            print_info "设置 insteadof: \"${proxy_url}\" → \"https://github.com/\""

            # 同时清理 HTTP 代理（ghproxy 方式不需要）
            git config --global --unset http.proxy 2>/dev/null || true
            git config --global --unset https.proxy 2>/dev/null || true

            echo ""
            print_info "✅ Git ghproxy 加速已启用 (${proxy_name})"
            print_info "所有 git clone/pull/fetch GitHub 仓库将自动走加速代理"
            print_info "例: git clone https://github.com/user/repo.git  → 自动加速"
            ;;
        2)
            # 自定义 HTTP 代理
            echo ""
            read -rp "请输入 HTTP 代理地址 (例如 http://127.0.0.1:7890): " proxy_addr
            if [[ -z "$proxy_addr" ]]; then
                print_warn "代理地址为空，跳过"
                return
            fi

            # 清理 insteadof (HTTP 代理方式不需要 insteadof)
            local old_urls2
            old_urls2=$(git config --global --get-regexp 'url\.' 2>/dev/null | awk '{print $1}' | sed 's/\.insteadof$//' | sort -u) || true
            while IFS= read -r u; do
                [[ -z "$u" ]] && continue
                git config --global --unset-all "${u}.insteadof" 2>/dev/null || true
            done <<< "$old_urls2"

            git config --global http.proxy "$proxy_addr"
            git config --global https.proxy "$proxy_addr"
            print_info "设置 http.proxy / https.proxy → $proxy_addr"

            print_info "✅ Git HTTP 代理已配置"
            print_info "所有 git 操作将通过代理: $proxy_addr"
            ;;
        *)
            print_error "无效的 Git 加速模式: $mode"
            ;;
    esac

    # 验证
    echo ""
    print_info "📋 Git 当前加速配置:"
    local git_config_now
    git_config_now=$(git config --global --get-regexp 'url\.' 2>/dev/null || true)
    if [[ -n "$git_config_now" ]]; then
        echo "$git_config_now" | while IFS= read -r line; do echo "    $line"; done
    else
        echo "    (无 insteadof 配置)"
    fi
    local http_proxy
    http_proxy=$(git config --global --get http.proxy 2>/dev/null || true)
    [[ -n "$http_proxy" ]] && echo "    http.proxy = $http_proxy"
    local https_proxy
    https_proxy=$(git config --global --get https.proxy 2>/dev/null || true)
    [[ -n "$https_proxy" ]] && echo "    https.proxy = $https_proxy"
    echo "    SSH config: ~/.ssh/config (如需 SSH 代理，请手动配置)"
    print_info "✅ Git 加速配置完成"
}

# ============================================================
# 主逻辑
# ============================================================

# 显示当前配置概要
show_current() {
    print_title "当前镜像源概览"
    echo ""
    has_cmd npm      && echo -e "  npm     : $(npm config get registry 2>/dev/null || echo 'N/A')"
    has_cmd pnpm     && echo -e "  pnpm    : $(pnpm config get registry 2>/dev/null || echo 'N/A')"
    has_cmd yarn     && echo -e "  yarn    : $(yarn config get registry 2>/dev/null || echo 'N/A')"
    has_cmd bun      && echo -e "  bun     : bun registry in ~/.bunfig.toml"
    has_cmd pip      && echo -e "  pip     : $(pip config list 2>/dev/null | grep index-url || echo 'N/A')"
    has_cmd gem      && echo -e "  gem     : $(gem sources -l 2>/dev/null | grep -v '^\*\*\*' | head -1 || echo 'N/A')"
    has_cmd cargo    && echo -e "  cargo   : ~/.cargo/config.toml"
    has_cmd go       && echo -e "  go      : $(go env GOPROXY 2>/dev/null || echo 'N/A')"
    has_cmd conda    && echo -e "  conda   : $(conda config --show channels 2>/dev/null | head -3 || echo 'N/A')"
    has_cmd composer && echo -e "  composer: $(composer config -g repos.packagist 2>/dev/null || echo 'N/A')"
    has_cmd docker   && echo -e "  docker  : /etc/docker/daemon.json"
    has_cmd flutter  && echo -e "  flutter : FLUTTER_STORAGE_BASE_URL / PUB_HOSTED_URL"
    if has_cmd git; then
        local git_accel
        git_accel=$(git config --global --get-regexp 'url\.' 2>/dev/null | head -1 || true)
        local git_proxy
        git_proxy=$(git config --global --get http.proxy 2>/dev/null || true)
        if [[ -n "$git_accel" ]]; then
            echo -e "  git     : ghproxy 加速 (insteadOf)"
        elif [[ -n "$git_proxy" ]]; then
            echo -e "  git     : HTTP 代理 ($git_proxy)"
        else
            echo -e "  git     : 官方直连 (无加速)"
        fi
    fi
    echo ""
}

# 命令行模式：一键设置所有
set_all_mirrors() {
    local idx="$1"
    print_info "使用镜像源: ${MIRROR_NAME[$idx]}"
    echo ""
    setup_npm "$idx"
    setup_pnpm "$idx"
    setup_yarn "$idx"
    setup_bun "$idx"
    setup_pip "$idx"
    setup_gem "$idx"
    setup_bundler "$idx"
    setup_cargo "$idx"
    setup_rustup "$idx"
    setup_go "$idx"
    setup_conda "$idx"
    setup_composer "$idx"
    setup_apt "$idx"
    setup_docker "$idx"
    setup_nvm "$idx"
    setup_flutter "$idx"
    setup_brew "$idx"
    # git 加速：镜像源 1-4 → ghproxy, 0 → 恢复官方
    echo ""
    if [[ $idx -eq 0 ]]; then
        setup_git 0
    else
        setup_git 1
    fi
    echo ""
    print_info "全部配置完成！请重新加载 shell 配置: source ~/.bashrc (或 source ~/.zshrc)"
}

# 交互菜单
interactive_mode() {
    while true; do
        clear
        print_banner
        echo ""
        echo -e "${BOLD}请选择操作:${NC}"
        echo "  ┌─────────────────────────────────────────────┐"
        echo "  │  ${GREEN}1${NC})  选择镜像源并一键设置所有                    │"
        echo "  │  ${GREEN}2${NC})  选择性配置单项 (含 🔥 git 加速)              │"
        echo "  │  ${GREEN}3${NC})  查看当前镜像源配置                        │"
        echo "  │  ${GREEN}0${NC})  退出                                    │"
        echo "  └─────────────────────────────────────────────┘"
        echo ""
        read -rp "请输入编号: " main_choice

        case "$main_choice" in
            1)
                clear
                print_banner
                echo ""
                echo "选择镜像源:"
                echo "  1) 阿里云        (国内首选，速度快)"
                echo "  2) 清华大学 TUNA (教育网推荐)"
                echo "  3) 中科大 USTC   (教育网推荐)"
                echo "  4) 华为云        (企业用户推荐)"
                echo "  0) 恢复官方源"
                echo ""
                echo -e "${YELLOW}注: 同时会自动配置 Git ghproxy 加速 (0 则恢复)${NC}"
                echo ""
                read -rp "请输入编号 (默认 1): " idx
                idx=${idx:-1}
                if ! [[ "$idx" =~ ^[0-4]$ ]]; then idx=1; fi
                clear
                print_banner
                echo ""
                echo -e "${BOLD}━━━ 一键设置所有镜像源 (${MIRROR_NAME[$idx]}) ━━━${NC}\n"
                set_all_mirrors "$idx"
                echo ""
                read -rp "按回车键返回主菜单..."
                ;;
            2)
                clear
                print_banner
                echo ""
                idx=$(select_mirror "所有单项")
                clear
                print_banner
                echo ""
                echo -e "${BOLD}请选择要配置的项:${NC}"
                echo "  ┌─────────────────────────────────────────────┐"
                echo "  │  ${GREEN}a${NC})  npm                    ${GREEN}b${NC})  pnpm              │"
                echo "  │  ${GREEN}c${NC})  yarn                   ${GREEN}d${NC})  bun               │"
                echo "  │  ${GREEN}e${NC})  pip                    ${GREEN}f${NC})  gem               │"
                echo "  │  ${GREEN}g${NC})  bundler                ${GREEN}h${NC})  cargo             │"
                echo "  │  ${GREEN}i${NC})  rustup                 ${GREEN}j${NC})  go                │"
                echo "  │  ${GREEN}k${NC})  conda                  ${GREEN}l${NC})  composer          │"
                echo "  │  ${GREEN}m${NC})  apt                    ${GREEN}n${NC})  docker            │"
                echo "  │  ${GREEN}o${NC})  nvm                    ${GREEN}p${NC})  flutter/dart      │"
                echo "  │  ${GREEN}q${NC})  homebrew               ${GREEN}s${NC})  🔥 git 加速      │"
                echo "  │  ${GREEN}r${NC})  全部                                                  │"
                echo "  └─────────────────────────────────────────────┘"
                echo ""
                read -rp "请输入字母: " sub
                clear
                print_banner
                echo ""
                case "$sub" in
                    a) setup_npm "$idx" ;;
                    b) setup_pnpm "$idx" ;;
                    c) setup_yarn "$idx" ;;
                    d) setup_bun "$idx" ;;
                    e) setup_pip "$idx" ;;
                    f) setup_gem "$idx" ;;
                    g) setup_bundler "$idx" ;;
                    h) setup_cargo "$idx" ;;
                    i) setup_rustup "$idx" ;;
                    j) setup_go "$idx" ;;
                    k) setup_conda "$idx" ;;
                    l) setup_composer "$idx" ;;
                    m) setup_apt "$idx" ;;
                    n) setup_docker "$idx" ;;
                    o) setup_nvm "$idx" ;;
                    p) setup_flutter "$idx" ;;
                    q) setup_brew "$idx" ;;
                    s)
                        clear
                        print_banner
                        echo ""
                        echo -e "${BOLD}Git 加速模式选择:${NC}"
                        echo "  1) ghproxy 加速   (推荐，自动代理 GitHub 请求)"
                        echo "  2) 自定义 HTTP 代理 (适合已有代理的用户)"
                        echo "  0) 恢复官方配置    (移除所有加速)"
                        echo ""
                        read -rp "请输入编号 (默认 1): " gmode
                        gmode=${gmode:-1}
                        if ! [[ "$gmode" =~ ^[0-2]$ ]]; then gmode=1; fi
                        setup_git "$gmode"
                        ;;
                    r) set_all_mirrors "$idx" ;;
                    *) print_warn "无效选择" ;;
                esac
                echo ""
                read -rp "按回车键返回主菜单..."
                ;;
            3)
                clear
                print_banner
                show_current
                read -rp "按回车键返回主菜单..."
                ;;
            0)
                print_info "退出。祝开发愉快！ 🚀"
                exit 0
                ;;
            *)
                print_warn "无效选择，请重新输入"
                sleep 1
                ;;
        esac
    done
}

# ============================================================
# 命令行参数支持
# ============================================================
# 用法: bash set-mirrors.sh [镜索引]        # 一键设置所有
#       镜索引: 1=阿里云 2=清华 3=中科大 4=华为云 0=官方
#       bash set-mirrors.sh interactive     # 交互模式
#       bash set-mirrors.sh show            # 查看当前配置
# ============================================================

main() {
    # 检查 root
    if [[ $# -eq 0 ]]; then
        # 无参数 → 交互模式
        interactive_mode
    else
        case "$1" in
            interactive|i|menu)
                interactive_mode
                ;;
            show|status|s)
                print_banner
                show_current
                ;;
            all|a)
                local idx="${2:-1}"
                if ! [[ "$idx" =~ ^[0-4]$ ]]; then idx=1; fi
                print_banner
                echo ""
                echo -e "${BOLD}━━━ 一键设置所有镜像源 (${MIRROR_NAME[$idx]}) ━━━${NC}\n"
                set_all_mirrors "$idx"
                ;;
            npm|pip|gem|cargo|go|conda|composer|apt|docker|nvm|flutter|brew|bun|pnpm|yarn|bundler|rustup)
                local idx="${2:-1}"
                if ! [[ "$idx" =~ ^[0-4]$ ]]; then idx=1; fi
                print_banner
                echo -e "\n${BOLD}配置 $1 (${MIRROR_NAME[$idx]})${NC}\n"
                "setup_$1" "$idx"
                ;;
            git)
                local gmode="${2:-1}"
                if ! [[ "$gmode" =~ ^[0-2]$ ]]; then gmode=1; fi
                print_banner
                local mode_name=""
                case "$gmode" in
                    0) mode_name="恢复官方" ;;
                    1) mode_name="ghproxy 加速" ;;
                    2) mode_name="HTTP 代理" ;;
                esac
                echo -e "\n${BOLD}配置 Git 加速 ($mode_name)${NC}\n"
                setup_git "$gmode"
                ;;
            help|h|--help|-h)
                print_banner
                echo ""
                echo "用法:"
                echo "  bash $0                   # 交互菜单模式"
                echo "  bash $0 interactive       # 交互菜单模式"
                echo "  bash $0 show              # 查看当前配置"
                echo "  bash $0 all [镜索引]       # 一键全部设置"
                echo "  bash $0 npm [镜索引]       # 单独设置 npm"
                echo "  bash $0 git [模式]         # Git 加速: 1=ghproxy 2=HTTP代理 0=恢复"
                echo "  ..."
                echo ""
                echo "镜索引:"
                echo "  1 = 阿里云 (默认)"
                echo "  2 = 清华大学 TUNA"
                echo "  3 = 中科大 USTC"
                echo "  4 = 华为云"
                echo "  0 = 恢复官方源"
                echo ""
                echo "Git 加速模式:"
                echo "  1 = ghproxy 加速 (默认)"
                echo "  2 = 自定义 HTTP 代理"
                echo "  0 = 恢复官方"
                echo ""
                echo "示例:"
                echo "  bash $0 all 2             # 全用清华源 + git ghproxy"
                echo "  bash $0 pip 3             # pip 用中科大"
                echo "  bash $0 go 4              # go 用华为云"
                echo "  bash $0 git               # git ghproxy 加速"
                echo "  bash $0 git 2             # git 自定义 HTTP 代理"
                ;;
            *)
                print_error "未知参数: $1"
                echo "用法: bash $0 [interactive|show|all|npm|pip|...] [镜索引]"
                exit 1
                ;;
        esac
    fi
}

main "$@"
