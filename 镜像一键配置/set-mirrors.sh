#!/usr/bin/env bash
# ==============================================================================
#  🌐 一键镜像源配置工具 v2.1
#  适用系统: Linux / macOS
#  包管理器支持: 16 种 + 🔥 Git 加速
#  内置镜像源: 阿里云 / 清华大学 TUNA / 中科大 USTC / 华为云
# ==============================================================================

set -eE
# 调试模式开关：set -x 可取消注释以调试

# ----- 版本与元数据 -----
VERSION="2.1"
SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ----- 颜色定义 -----
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color
OK_ICON="${GREEN}✅${NC}"
ERR_ICON="${RED}❌${NC}"
INFO_ICON="${BLUE}ℹ️${NC}"
WARN_ICON="${YELLOW}⚠️${NC}"

# ----- 辅助函数 -----

# 彩色 echo
info()  { echo -e "${INFO_ICON} ${BLUE}$1${NC}"; }
ok()    { echo -e "${OK_ICON} ${GREEN}$1${NC}"; }
warn()  { echo -e "${WARN_ICON} ${YELLOW}$1${NC}"; }
error() { echo -e "${ERR_ICON} ${RED}$1${NC}"; }
header(){ echo -e "\n${BOLD}${MAGENTA}═══════════════════════════════════════${NC}"; }
sub_header(){ echo -e "${CYAN}--- $1 ---${NC}"; }

# 检测命令是否存在
has_cmd() { command -v "$1" &>/dev/null; }

# 检测操作系统
detect_os() {
    case "$(uname -s)" in
        Linux)  echo "linux"  ;;
        Darwin) echo "macos"  ;;
        *)      echo "unknown" ;;
    esac
}
OS="$(detect_os)"

# 获取当前用户的 shell 配置文件
get_shell_rc() {
    if [[ -n "$ZSH_VERSION" || -f "$HOME/.zshrc" ]]; then
        echo "$HOME/.zshrc"
    elif [[ -n "$BASH_VERSION" || -f "$HOME/.bashrc" ]]; then
        echo "$HOME/.bashrc"
    else
        echo "$HOME/.profile"
    fi
}
SHELL_RC="$(get_shell_rc)"

# 获取当前时间戳（用于备份）
get_timestamp() {
    date +"%Y%m%d_%H%M%S"
}

# ----- 备份函数 -----
backup_file() {
    local filepath="$1"
    if [[ -f "$filepath" ]]; then
        local bak_path="${filepath}.bak.$(get_timestamp)"
        cp "$filepath" "$bak_path"
        info "已备份: $filepath → $bak_path"
    fi
}

# 检查脚本是否以 sudo 运行
is_sudo() {
    [[ $EUID -eq 0 ]]
}

# 提示用户是否需要 sudo（交互模式下使用）
check_sudo_and_run() {
    local cmd="$1"
    if is_sudo; then
        eval "$cmd"
    elif has_cmd sudo; then
        warn "此操作需要 sudo 权限: $cmd"
        echo -n "是否使用 sudo 执行？[Y/n]: "
        read -r ans
        if [[ -z "$ans" || "$ans" =~ ^[Yy]$ ]]; then
            eval "sudo bash \"$SCRIPT_DIR/$SCRIPT_NAME\" $cmd"
        else
            warn "已跳过。如需手动执行: sudo bash $SCRIPT_NAME $cmd"
        fi
    else
        error "需要 root 权限但未找到 sudo，请以 root 执行。"
    fi
}

# ==============================================================================
#  镜像源 URL 字典
#  参数: $1 = 源编号 (1/2/3/4/0), $2 = 包管理器名称
#  输出: 对应的镜像源 URL（写入 stdout）
# ==============================================================================
get_mirror_url() {
    local src="$1"
    local pkg="$2"

    # src: 1=阿里云, 2=清华, 3=中科大, 4=华为云, 0=官方源
    case "${src}-${pkg}" in
        # ---- npm ----
        1-npm) echo "https://registry.npmmirror.com" ;;
        2-npm) echo "https://mirrors.tuna.tsinghua.edu.cn/npm-registry/" ;;
        3-npm) echo "https://mirrors.ustc.edu.cn/npm-registry/" ;;
        4-npm) echo "https://mirrors.huaweicloud.com/npm-registry/" ;;
        0-npm) echo "https://registry.npmjs.org" ;;

        # ---- pip ----
        1-pip) echo "https://mirrors.aliyun.com/pypi/simple/" ;;
        2-pip) echo "https://pypi.tuna.tsinghua.edu.cn/simple/" ;;
        3-pip) echo "https://pypi.mirrors.ustc.edu.cn/simple/" ;;
        4-pip) echo "https://mirrors.huaweicloud.com/pypi/simple/" ;;
        0-pip) echo "https://pypi.org/simple/" ;;

        # ---- gem (RubyGems) ----
        1-gem) echo "https://mirrors.aliyun.com/rubygems/" ;;
        2-gem) echo "https://mirrors.tuna.tsinghua.edu.cn/rubygems/" ;;
        3-gem) echo "https://mirrors.ustc.edu.cn/rubygems/" ;;
        4-gem) echo "https://mirrors.huaweicloud.com/rubygems/" ;;
        0-gem) echo "https://rubygems.org" ;;

        # ---- bundler (Ruby) ----
        1-bundler) echo "https://mirrors.aliyun.com/rubygems/" ;;
        2-bundler) echo "https://mirrors.tuna.tsinghua.edu.cn/rubygems/" ;;
        3-bundler) echo "https://mirrors.ustc.edu.cn/rubygems/" ;;
        4-bundler) echo "https://mirrors.huaweicloud.com/rubygems/" ;;
        0-bundler) echo "https://rubygems.org" ;;

        # ---- cargo (Rust) ----
        1-cargo) echo "https://mirrors.aliyun.com/crates.io-index" ;;
        2-cargo) echo "https://mirrors.tuna.tsinghua.edu.cn/git/crates.io-index.git" ;;
        3-cargo) echo "https://mirrors.ustc.edu.cn/crates.io-index" ;;
        4-cargo) echo "https://mirrors.huaweicloud.com/crates.io-index" ;;
        0-cargo) echo "https://github.com/rust-lang/crates.io-index" ;;

        # ---- rustup ----
        1-rustup) echo "https://mirrors.aliyun.com/rustup" ;;
        2-rustup) echo "https://mirrors.tuna.tsinghua.edu.cn/rustup" ;;
        3-rustup) echo "https://mirrors.ustc.edu.cn/rustup" ;;
        4-rustup) echo "https://mirrors.huaweicloud.com/rustup" ;;
        0-rustup) echo "https://static.rust-lang.org/rustup" ;;

        # ---- go ----
        1-go) echo "https://goproxy.cn,direct" ;;
        2-go) echo "https://goproxy.cn,direct" ;;
        3-go) echo "https://goproxy.cn,direct" ;;
        4-go) echo "https://mirrors.huaweicloud.com/goproxy/,direct" ;;
        0-go) echo "https://proxy.golang.org,direct" ;;

        # ---- conda ----
        1-conda) echo "https://mirrors.aliyun.com/anaconda/" ;;
        2-conda) echo "https://mirrors.tuna.tsinghua.edu.cn/anaconda/" ;;
        3-conda) echo "https://mirrors.ustc.edu.cn/anaconda/" ;;
        4-conda) echo "https://mirrors.huaweicloud.com/anaconda/" ;;
        0-conda) echo "https://repo.anaconda.com" ;;

        # ---- composer (PHP) ----
        1-composer) echo "https://mirrors.aliyun.com/composer/" ;;
        2-composer) echo "https://mirrors.tuna.tsinghua.edu.cn/composer/" ;;
        3-composer) echo "https://mirrors.ustc.edu.cn/composer/" ;;
        4-composer) echo "https://mirrors.huaweicloud.com/composer/" ;;
        0-composer) echo "https://packagist.org" ;;

        # ---- apt (Ubuntu/Debian) ----
        1-apt) echo "http://mirrors.aliyun.com/ubuntu/" ;;
        2-apt) echo "https://mirrors.tuna.tsinghua.edu.cn/ubuntu/" ;;
        3-apt) echo "https://mirrors.ustc.edu.cn/ubuntu/" ;;
        4-apt) echo "https://mirrors.huaweicloud.com/ubuntu/" ;;
        0-apt) echo "" ;;  # 特殊处理，恢复官方需要根据版本重新生成

        # ---- docker (registry mirror) ----
        1-docker_mirror) echo "https://registry.cn-hangzhou.aliyuncs.com" ;;
        2-docker_mirror) echo "https://docker.mirrors.tuna.tsinghua.edu.cn" ;;
        3-docker_mirror) echo "https://docker.mirrors.ustc.edu.cn" ;;
        4-docker_mirror) echo "https://docker.mirrors.huaweicloud.com" ;;
        0-docker_mirror) echo "" ;;

        # ---- homebrew ----
        1-homebrew) echo "https://mirrors.aliyun.com/homebrew/" ;;
        2-homebrew) echo "https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/" ;;
        3-homebrew) echo "https://mirrors.ustc.edu.cn/homebrew/" ;;
        4-homebrew) echo "https://mirrors.huaweicloud.com/homebrew/" ;;
        0-homebrew) echo "" ;;

        # ---- nvm (node mirror) ----
        1-nvm) echo "https://mirrors.aliyun.com/nodejs-release/" ;;
        2-nvm) echo "https://mirrors.tuna.tsinghua.edu.cn/nodejs-release/" ;;
        3-nvm) echo "https://mirrors.ustc.edu.cn/nodejs-release/" ;;
        4-nvm) echo "https://mirrors.huaweicloud.com/nodejs-release/" ;;
        0-nvm) echo "https://nodejs.org/dist" ;;

        # ---- flutter/dart ----
        1-flutter) echo "https://mirrors.aliyun.com/flutter/" ;;
        2-flutter) echo "https://mirrors.tuna.tsinghua.edu.cn/flutter/" ;;
        3-flutter) echo "https://mirrors.ustc.edu.cn/flutter/" ;;
        4-flutter) echo "https://mirrors.huaweicloud.com/flutter/" ;;
        0-flutter) echo "https://storage.googleapis.com" ;;

        # ---- bun (bunfig.toml 用) ----
        1-bun) echo "https://registry.npmmirror.com" ;;
        2-bun) echo "https://mirrors.tuna.tsinghua.edu.cn/npm-registry/" ;;
        3-bun) echo "https://mirrors.ustc.edu.cn/npm-registry/" ;;
        4-bun) echo "https://mirrors.huaweicloud.com/npm-registry/" ;;
        0-bun) echo "https://registry.npmjs.org" ;;

        *) echo "" ;;
    esac
}

# 获取镜像源名称
get_source_name() {
    case "$1" in
        1) echo "阿里云" ;;
        2) echo "清华大学 TUNA" ;;
        3) echo "中科大 USTC" ;;
        4) echo "华为云" ;;
        0) echo "官方源" ;;
        *) echo "未知" ;;
    esac
}

# 打印带颜色的镜像源名称
get_source_name_colored() {
    case "$1" in
        1) echo "${RED}阿里云${NC}" ;;
        2) echo "${MAGENTA}清华大学 TUNA${NC}" ;;
        3) echo "${BLUE}中科大 USTC${NC}" ;;
        4) echo "${CYAN}华为云${NC}" ;;
        0) echo "${YELLOW}官方源${NC}" ;;
        *) echo "未知" ;;
    esac
}

# ==============================================================================
#  各包管理器配置函数
#  参数: $1 = 镜像源编号 (1/2/3/4/0)
#  返回值: 0=成功, 1=跳过(未安装), 2=失败
# ==============================================================================

# ----- 1. npm -----
configure_npm() {
    local src="$1"
    local url
    url="$(get_mirror_url "$src" "npm")"
    [[ -z "$url" ]] && { error "npm: 未找到镜像源 URL"; return 2; }

    if ! has_cmd npm; then
        warn "npm 未安装，跳过"
        return 1
    fi

    local current
    current="$(npm config get registry 2>/dev/null)"

    if [[ "$src" == "0" ]]; then
        npm config delete registry 2>/dev/null || true
        ok "npm: 已恢复官方源"
    else
        npm config set registry "$url"
        ok "npm: registry → $url"
    fi

    # 输出变更对比
    local new
    new="$(npm config get registry 2>/dev/null)"
    info "  npm registry: ${current:-}(未设置) → ${new}"

    return 0
}

# ----- 2. pnpm -----
configure_pnpm() {
    local src="$1"
    local url
    url="$(get_mirror_url "$src" "npm")"
    [[ -z "$url" ]] && { error "pnpm: 未找到镜像源 URL"; return 2; }

    if ! has_cmd pnpm; then
        warn "pnpm 未安装，跳过"
        return 1
    fi

    if [[ "$src" == "0" ]]; then
        pnpm config delete registry 2>/dev/null || true
        ok "pnpm: 已恢复官方源"
    else
        pnpm config set registry "$url"
        ok "pnpm: registry → $url"
    fi

    return 0
}

# ----- 3. yarn -----
configure_yarn() {
    local src="$1"
    local url
    url="$(get_mirror_url "$src" "npm")"
    [[ -z "$url" ]] && { error "yarn: 未找到镜像源 URL"; return 2; }

    if ! has_cmd yarn; then
        warn "yarn 未安装，跳过"
        return 1
    fi

    if [[ "$src" == "0" ]]; then
        yarn config delete registry 2>/dev/null || true
        ok "yarn: 已恢复官方源"
    else
        yarn config set registry "$url"
        ok "yarn: registry → $url"
    fi

    return 0
}

# ----- 4. bun -----
configure_bun() {
    local src="$1"
    local url
    url="$(get_mirror_url "$src" "bun")"
    [[ -z "$url" ]] && { error "bun: 未找到镜像源 URL"; return 2; }

    if ! has_cmd bun; then
        warn "bun 未安装，跳过"
        return 1
    fi

    local bunfig="$HOME/.bunfig.toml"

    if [[ "$src" == "0" ]]; then
        if [[ -f "$bunfig" ]]; then
            backup_file "$bunfig"
            # 移除 registry 行
            grep -v '^registry\s*=' "$bunfig" > "${bunfig}.tmp" 2>/dev/null && mv "${bunfig}.tmp" "$bunfig" || true
        fi
        ok "bun: 已恢复官方源"
    else
        backup_file "$bunfig"
        # 写入或更新 registry
        if [[ -f "$bunfig" ]]; then
            if grep -q '^registry\s*=' "$bunfig"; then
                sed -i.bak "s|^registry\s*=.*|registry = \"$url\"|" "$bunfig"
            else
                echo "registry = \"$url\"" >> "$bunfig"
            fi
        else
            echo "registry = \"$url\"" > "$bunfig"
        fi
        ok "bun: registry → $url"
    fi

    return 0
}

# ----- 5. pip -----
configure_pip() {
    local src="$1"
    local url
    url="$(get_mirror_url "$src" "pip")"
    [[ -z "$url" ]] && { error "pip: 未找到镜像源 URL"; return 2; }

    if ! has_cmd pip && ! has_cmd pip3; then
        warn "pip/pip3 未安装，跳过"
        return 1
    fi

    # pip.conf 路径
    local pip_dir="$HOME/.pip"
    local pip_conf="$pip_dir/pip.conf"
    mkdir -p "$pip_dir"

    if [[ "$src" == "0" ]]; then
        # 恢复官方源：删除 index-url 行
        if [[ -f "$pip_conf" ]]; then
            backup_file "$pip_conf"
            # 保留其他配置，移除 index-url 和 trusted-host 相关
            grep -v -E '^\s*index-url\s*=|^\s*trusted-host\s*=' "$pip_conf" > "${pip_conf}.tmp" 2>/dev/null || true
            mv "${pip_conf}.tmp" "$pip_conf" 2>/dev/null || true
        fi
        ok "pip: 已恢复官方源"
    else
        backup_file "$pip_conf"

        # 从 URL 提取 host
        local host
        host="$(echo "$url" | sed -E 's|https?://([^/]+).*|\1|')"

        cat > "$pip_conf" <<EOF
[global]
index-url = $url
trusted-host = $host
EOF
        ok "pip: index-url → $url"
    fi

    return 0
}

# ----- 6. gem -----
configure_gem() {
    local src="$1"
    local url
    url="$(get_mirror_url "$src" "gem")"
    [[ -z "$url" ]] && { error "gem: 未找到镜像源 URL"; return 2; }

    if ! has_cmd gem; then
        warn "gem 未安装，跳过"
        return 1
    fi

    if [[ "$src" == "0" ]]; then
        # 恢复官方源：移除所有源，添加官方源
        gem sources --remove "$(gem sources -l 2>/dev/null | grep -v '^\*' | head -1)" 2>/dev/null || true
        gem sources --add "https://rubygems.org/" 2>/dev/null || true
        ok "gem: 已恢复官方源"
    else
        # 移除现有源，添加镜像源
        gem sources --remove "https://rubygems.org/" 2>/dev/null || true
        gem sources --add "$url"
        ok "gem: sources → $url"
    fi

    return 0
}

# ----- 7. bundler -----
configure_bundler() {
    local src="$1"
    local url
    url="$(get_mirror_url "$src" "bundler")"
    [[ -z "$url" ]] && { error "bundler: 未找到镜像源 URL"; return 2; }

    if ! has_cmd bundle; then
        warn "bundler 未安装，跳过"
        return 1
    fi

    if [[ "$src" == "0" ]]; then
        bundle config --delete mirror.https://rubygems.org 2>/dev/null || true
        ok "bundler: 已恢复官方源"
    else
        bundle config mirror.https://rubygems.org "$url"
        ok "bundler: mirror → $url"
    fi

    return 0
}

# ----- 8. cargo (Rust) -----
configure_cargo() {
    local src="$1"
    local url
    url="$(get_mirror_url "$src" "cargo")"
    [[ -z "$url" ]] && { error "cargo: 未找到镜像源 URL"; return 2; }

    if ! has_cmd cargo; then
        warn "cargo 未安装，跳过"
        return 1
    fi

    local cargo_dir="$HOME/.cargo"
    local cargo_config="$cargo_dir/config.toml"
    mkdir -p "$cargo_dir"

    if [[ "$src" == "0" ]]; then
        if [[ -f "$cargo_config" ]]; then
            backup_file "$cargo_config"
            # 移除 [source.crates-io] 相关配置块
            awk 'BEGIN{skip=0} /^\[source\.crates-io\]/{skip=1; print; next} skip && /^\[/{skip=0} !skip' "$cargo_config" > "${cargo_config}.tmp" && mv "${cargo_config}.tmp" "$cargo_config"
        fi
        ok "cargo: 已恢复官方源"
    else
        backup_file "$cargo_config"

        # 构建配置内容
        local replace_with
        replace_with="$(echo "$url" | sed 's|/$||')"  # 去除尾部斜杠

        # 判断是否已有 [source.crates-io] 配置
        if [[ -f "$cargo_config" ]] && grep -q '\[source\.crates-io\]' "$cargo_config"; then
            # 替换已有的 registry 值
            sed -i.bak "s|replace-with = \".*\"|replace-with = \"mirror\"|" "$cargo_config"
            # 如果已有 [source.mirror] 则更新，否则追加
            if grep -q '\[source\.mirror\]' "$cargo_config"; then
                sed -i.bak "s|registry = \".*\"|registry = \"${replace_with}\"|" "$cargo_config"
            else
                cat >> "$cargo_config" <<EOF

[source.mirror]
registry = "${replace_with}"
EOF
            fi
        else
            cat >> "$cargo_config" <<EOF

[source.crates-io]
replace-with = "mirror"

[source.mirror]
registry = "${replace_with}"
EOF
        fi
        ok "cargo: mirror → $url"
    fi

    return 0
}

# ----- 9. rustup -----
configure_rustup() {
    local src="$1"
    local url
    url="$(get_mirror_url "$src" "rustup")"
    [[ -z "$url" ]] && { error "rustup: 未找到镜像源 URL"; return 2; }

    if ! has_cmd rustup; then
        warn "rustup 未安装，跳过"
        return 1
    fi

    # rustup 使用环境变量，写入 shell rc
    local export_line="export RUSTUP_DIST_SERVER=\"$url\""
    local comment="# rustup mirror (configured by set-mirrors.sh)"

    if [[ "$src" == "0" ]]; then
        # 从 shell rc 中移除
        if [[ -f "$SHELL_RC" ]]; then
            backup_file "$SHELL_RC"
            grep -v "RUSTUP_DIST_SERVER" "$SHELL_RC" > "${SHELL_RC}.tmp" && mv "${SHELL_RC}.tmp" "$SHELL_RC"
        fi
        # 同时移除 RUSTUP_UPDATE_ROOT
        if [[ -f "$SHELL_RC" ]]; then
            grep -v "RUSTUP_UPDATE_ROOT" "$SHELL_RC" > "${SHELL_RC}.tmp" && mv "${SHELL_RC}.tmp" "$SHELL_RC"
        fi
        ok "rustup: 已从 ${SHELL_RC} 移除镜像配置"
    else
        backup_file "$SHELL_RC"

        # 移除旧行再添加新行
        grep -v "RUSTUP_DIST_SERVER" "$SHELL_RC" > "${SHELL_RC}.tmp" || true
        echo "$comment" >> "${SHELL_RC}.tmp"
        echo "$export_line" >> "${SHELL_RC}.tmp"

        # 同时设置 RUSTUP_UPDATE_ROOT
        local update_root_url
        update_root_url="$(echo "$url" | sed 's|/*$||')"
        echo "export RUSTUP_UPDATE_ROOT=\"${update_root_url}/rustup\"" >> "${SHELL_RC}.tmp"

        mv "${SHELL_RC}.tmp" "$SHELL_RC"
        # 立即生效当前环境
        export RUSTUP_DIST_SERVER="$url"
        export RUSTUP_UPDATE_ROOT="${update_root_url}/rustup"

        ok "rustup: RUSTUP_DIST_SERVER → $url (已写入 ${SHELL_RC})"
    fi

    return 0
}

# ----- 10. go -----
configure_go() {
    local src="$1"
    local url
    url="$(get_mirror_url "$src" "go")"
    [[ -z "$url" ]] && { error "go: 未找到镜像源 URL"; return 2; }

    if ! has_cmd go; then
        warn "go 未安装，跳过"
        return 1
    fi

    if [[ "$src" == "0" ]]; then
        go env -w GOPROXY="https://proxy.golang.org,direct"
        ok "go: GOPROXY → https://proxy.golang.org,direct"
    else
        go env -w GOPROXY="$url"
        ok "go: GOPROXY → $url"
    fi

    return 0
}

# ----- 11. conda -----
configure_conda() {
    local src="$1"
    local url
    url="$(get_mirror_url "$src" "conda")"
    [[ -z "$url" ]] && { error "conda: 未找到镜像源 URL"; return 2; }

    if ! has_cmd conda; then
        warn "conda 未安装，跳过"
        return 1
    fi

    if [[ "$src" == "0" ]]; then
        conda config --remove-key channels 2>/dev/null || true
        # 恢复默认频道
        conda config --add channels defaults 2>/dev/null || true
        ok "conda: 已恢复官方源"
    else
        # 清除现有频道设置
        conda config --remove-key channels 2>/dev/null || true
        conda config --add channels "defaults" 2>/dev/null || true
        conda config --set show_channel_urls yes 2>/dev/null || true

        # 添加镜像源（根据 conda 版本不同方式不同）
        # 移除尾部斜杠用于 channel 配置
        local channel_url
        channel_url="$(echo "$url" | sed 's|/*$||')"

        # conda 配置频道
        conda config --add channels "${channel_url}/pkgs/main/" 2>/dev/null || true
        conda config --add channels "${channel_url}/pkgs/free/" 2>/dev/null || true

        # 对于清华/中科大还有额外的频道
        if [[ "$src" == "2" ]]; then
            conda config --add channels "${channel_url}/pkgs/msys2/" 2>/dev/null || true
            conda config --add channels "${channel_url}/cloud/conda-forge/" 2>/dev/null || true
        elif [[ "$src" == "3" ]]; then
            conda config --add channels "${channel_url}/msys2/" 2>/dev/null || true
            conda config --add channels "${channel_url}/cloud/conda-forge/" 2>/dev/null || true
        fi

        # 设置镜像的 channel_alias
        conda config --set channel_alias "${channel_url}/" 2>/dev/null || true

        ok "conda: channels 已配置为 $url"
    fi

    return 0
}

# ----- 12. composer (PHP) -----
configure_composer() {
    local src="$1"
    local url
    url="$(get_mirror_url "$src" "composer")"
    [[ -z "$url" ]] && { error "composer: 未找到镜像源 URL"; return 2; }

    if ! has_cmd composer; then
        warn "composer 未安装，跳过"
        return 1
    fi

    if [[ "$src" == "0" ]]; then
        composer config -g --unset repos.packagist 2>/dev/null || {
            composer config -g repos.packagist false 2>/dev/null || true
        }
        ok "composer: 已恢复官方源"
    else
        composer config -g repos.packagist "composer" "$url"
        ok "composer: repos.packagist → $url"
    fi

    return 0
}

# ----- 13. apt (Ubuntu/Debian) -----
configure_apt() {
    local src="$1"

    if ! is_sudo && [[ "$OS" == "linux" ]]; then
        error "配置 apt 需要 root 权限，请使用 sudo 执行！"
        warn "命令: sudo bash $SCRIPT_NAME apt $src"
        return 2
    fi

    if [[ "$OS" != "linux" ]]; then
        warn "apt 仅支持 Linux，跳过"
        return 1
    fi

    # 判断是否 Ubuntu/Debian
    if [[ ! -f /etc/os-release ]]; then
        warn "未检测到 /etc/os-release，不是 Debian/Ubuntu 系，跳过"
        return 1
    fi

    local os_id os_version os_codename
    source /etc/os-release 2>/dev/null || true
    os_id="${ID,,}"       # ubuntu / debian
    os_codename="${VERSION_CODENAME}"
    if [[ -z "$os_codename" ]]; then
        # 尝试从 VERSION 中提取
        os_codename="$(echo "$VERSION" | grep -oP '\(\K[^)]+' || true)"
    fi
    if [[ -z "$os_codename" ]]; then
        os_codename="$(lsb_release -c 2>/dev/null | awk '{print $2}')" || true
    fi
    if [[ -z "$os_codename" ]]; then
        warn "无法检测系统版本代号，跳过 apt 配置"
        return 1
    fi

    local sources_list="/etc/apt/sources.list"

    if [[ "$src" == "0" ]]; then
        # 恢复官方源 - 从备份恢复
        local bak_file
        bak_file="$(ls -t "${sources_list}.bak."* 2>/dev/null | head -1)" || true
        if [[ -n "$bak_file" ]]; then
            cp "$bak_file" "$sources_list"
            ok "apt: 已从备份 $bak_file 恢复官方源"
        else
            warn "apt: 未找到备份文件，无法自动恢复。请手动编辑 /etc/apt/sources.list"
            return 1
        fi
        return 0
    fi

    local mirror_url
    mirror_url="$(get_mirror_url "$src" "apt")"
    [[ -z "$mirror_url" ]] && { error "apt: 未找到镜像源 URL"; return 2; }

    backup_file "$sources_list"

    # 生成新的 sources.list
    # Ubuntu 官方源格式: deb http://ports.ubuntu.com/ubuntu-ports <codename> main ...
    # 我们用镜像替换

    # 检测架构 (arm64/amd64)
    local arch
    arch="$(dpkg --print-architecture 2>/dev/null || uname -m)"

    # Debian 系处理
    if [[ "$os_id" == "ubuntu" ]]; then
        cat > "$sources_list" <<EOF
# Ubuntu 镜像源 - 由 set-mirrors.sh 自动配置
# 源: $(get_source_name "$src") ($mirror_url)

deb ${mirror_url} ${os_codename} main restricted universe multiverse
deb ${mirror_url} ${os_codename}-updates main restricted universe multiverse
deb ${mirror_url} ${os_codename}-backports main restricted universe multiverse
deb ${mirror_url} ${os_codename}-security main restricted universe multiverse

# 源码仓库（如不需要可注释）
# deb-src ${mirror_url} ${os_codename} main restricted universe multiverse
# deb-src ${mirror_url} ${os_codename}-updates main restricted universe multiverse
# deb-src ${mirror_url} ${os_codename}-backports main restricted universe multiverse
# deb-src ${mirror_url} ${os_codename}-security main restricted universe multiverse
EOF
        ok "apt: Ubuntu ${os_codename} 镜像源已配置为 $(get_source_name "$src")"
    elif [[ "$os_id" == "debian" ]]; then
        cat > "$sources_list" <<EOF
# Debian 镜像源 - 由 set-mirrors.sh 自动配置
# 源: $(get_source_name "$src") ($mirror_url)

deb ${mirror_url} ${os_codename} main contrib non-free
deb ${mirror_url} ${os_codename}-updates main contrib non-free
deb ${mirror_url} ${os_codename}-backports main contrib non-free

# 安全更新
deb http://security.debian.org/debian-security ${os_codename}-security main contrib non-free

# 源码仓库（如不需要可注释）
# deb-src ${mirror_url} ${os_codename} main contrib non-free
# deb-src ${mirror_url} ${os_codename}-updates main contrib non-free
EOF
        ok "apt: Debian ${os_codename} 镜像源已配置为 $(get_source_name "$src")"
    else
        warn "不支持的系统: $os_id，跳过 apt 配置"
        return 1
    fi

    info "建议运行 sudo apt update 刷新源"

    return 0
}

# ----- 14. docker -----
configure_docker() {
    local src="$1"
    local mirror_url
    mirror_url="$(get_mirror_url "$src" "docker_mirror")"
    # 官方源不需要 mirror

    if ! is_sudo && [[ "$OS" == "linux" ]]; then
        error "配置 docker 需要 root 权限，请使用 sudo 执行！"
        warn "命令: sudo bash $SCRIPT_NAME docker $src"
        return 2
    fi

    if ! has_cmd docker; then
        warn "docker 未安装，跳过"
        return 1
    fi

    local docker_dir="/etc/docker"
    local daemon_json="$docker_dir/daemon.json"
    mkdir -p "$docker_dir"

    if [[ "$src" == "0" ]]; then
        # 恢复官方 - 移除 registry-mirrors
        if [[ -f "$daemon_json" ]]; then
            backup_file "$daemon_json"
            # 用 python3 或 jq 处理 JSON
            if has_cmd jq; then
                jq 'del(."registry-mirrors")' "$daemon_json" > "${daemon_json}.tmp" && mv "${daemon_json}.tmp" "$daemon_json"
            elif has_cmd python3; then
                python3 -c "
import json
with open('$daemon_json') as f:
    cfg = json.load(f)
cfg.pop('registry-mirrors', None)
with open('${daemon_json}.tmp', 'w') as f:
    json.dump(cfg, f, indent=4)
" && mv "${daemon_json}.tmp" "$daemon_json"
            else
                # 简单 sed 处理（不完美但可用）
                grep -v 'registry-mirrors' "$daemon_json" > "${daemon_json}.tmp" && mv "${daemon_json}.tmp" "$daemon_json"
            fi
            ok "docker: 已移除 registry-mirrors 配置"
        fi
        # 重启 docker
        if systemctl is-active docker &>/dev/null; then
            systemctl restart docker
            ok "docker: 服务已重启"
        fi
        return 0
    fi

    backup_file "$daemon_json"

    # 构建新的 daemon.json
    if has_cmd jq; then
        if [[ -f "$daemon_json" ]]; then
            jq ". + {\"registry-mirrors\": [\"$mirror_url\"]}" "$daemon_json" > "${daemon_json}.tmp" && mv "${daemon_json}.tmp" "$daemon_json"
        else
            echo "{\"registry-mirrors\": [\"$mirror_url\"]}" > "$daemon_json"
        fi
    elif has_cmd python3; then
        python3 -c "
import json
cfg = {}
try:
    with open('$daemon_json') as f:
        cfg = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    pass
cfg['registry-mirrors'] = ['$mirror_url']
with open('$daemon_json', 'w') as f:
    json.dump(cfg, f, indent=4)
"
    else
        # fallback: 直接写入（覆盖原有内容，谨慎）
        warn "未找到 jq 或 python3，将覆盖写入 daemon.json（原有内容将丢失）"
        cat > "$daemon_json" <<EOF
{
  "registry-mirrors": ["$mirror_url"]
}
EOF
    fi

    ok "docker: registry-mirrors → $mirror_url"

    # 重启 docker 服务
    if systemctl is-active docker &>/dev/null; then
        systemctl restart docker
        ok "docker: 服务已重启"
    else
        warn "docker: 服务未运行，请手动重启以生效"
    fi

    return 0
}

# ----- 15. nvm -----
configure_nvm() {
    local src="$1"
    local url
    url="$(get_mirror_url "$src" "nvm")"
    [[ -z "$url" ]] && { error "nvm: 未找到镜像源 URL"; return 2; }

    # nvm 是 shell 函数而非独立二进制，检测 nvm.sh 是否可加载
    export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
    if ! command -v nvm &>/dev/null && [[ ! -s "$NVM_DIR/nvm.sh" ]]; then
        warn "nvm 未安装，跳过"
        return 1
    fi

    local export_line="export NVM_NODEJS_ORG_MIRROR=\"$url\""
    local comment="# nvm mirror (configured by set-mirrors.sh)"

    if [[ "$src" == "0" ]]; then
        if [[ -f "$SHELL_RC" ]]; then
            backup_file "$SHELL_RC"
            grep -v "NVM_NODEJS_ORG_MIRROR" "$SHELL_RC" > "${SHELL_RC}.tmp" && mv "${SHELL_RC}.tmp" "$SHELL_RC"
        fi
        ok "nvm: 已从 ${SHELL_RC} 移除镜像配置"
    else
        backup_file "$SHELL_RC"
        grep -v "NVM_NODEJS_ORG_MIRROR" "$SHELL_RC" > "${SHELL_RC}.tmp" || true
        echo "$comment" >> "${SHELL_RC}.tmp"
        echo "$export_line" >> "${SHELL_RC}.tmp"
        mv "${SHELL_RC}.tmp" "$SHELL_RC"
        export NVM_NODEJS_ORG_MIRROR="$url"
        ok "nvm: NVM_NODEJS_ORG_MIRROR → $url (已写入 ${SHELL_RC})"
    fi

    return 0
}

# ----- 16. flutter/dart -----
configure_flutter() {
    local src="$1"
    local url
    url="$(get_mirror_url "$src" "flutter")"
    [[ -z "$url" ]] && { error "flutter: 未找到镜像源 URL"; return 2; }

    if ! has_cmd flutter; then
        warn "flutter 未安装，跳过"
        return 1
    fi

    # Flutter 使用多个环境变量
    local storage_url
    storage_url="$(echo "$url" | sed 's|/*$||')"

    if [[ "$src" == "0" ]]; then
        if [[ -f "$SHELL_RC" ]]; then
            backup_file "$SHELL_RC"
            grep -v -E 'FLUTTER_STORAGE_BASE_URL|PUB_HOSTED_URL' "$SHELL_RC" > "${SHELL_RC}.tmp" && mv "${SHELL_RC}.tmp" "$SHELL_RC"
        fi
        ok "flutter: 已从 ${SHELL_RC} 移除镜像配置"
    else
        backup_file "$SHELL_RC"
        grep -v -E 'FLUTTER_STORAGE_BASE_URL|PUB_HOSTED_URL' "$SHELL_RC" > "${SHELL_RC}.tmp" || true

        cat >> "${SHELL_RC}.tmp" <<EOF
# flutter mirror (configured by set-mirrors.sh)
export FLUTTER_STORAGE_BASE_URL="${storage_url}"
export PUB_HOSTED_URL="${storage_url}/pub-cache"
EOF
        mv "${SHELL_RC}.tmp" "$SHELL_RC"
        export FLUTTER_STORAGE_BASE_URL="${storage_url}"
        export PUB_HOSTED_URL="${storage_url}/pub-cache"

        ok "flutter: FLUTTER_STORAGE_BASE_URL → ${storage_url} (已写入 ${SHELL_RC})"
    fi

    return 0
}

# ----- 17. homebrew (macOS/Linux) -----
configure_homebrew() {
    local src="$1"

    if ! has_cmd brew; then
        warn "homebrew 未安装，跳过"
        return 1
    fi

    if [[ "$src" == "0" ]]; then
        # 恢复官方源
        warn "homebrew 恢复官方源较为复杂，建议手动执行："
        info "git -C \"\$(brew --repo)\" remote set-url origin https://github.com/Homebrew/brew.git"
        info "git -C \"\$(brew --repo homebrew/core)\" remote set-url origin https://github.com/Homebrew/homebrew-core.git"
        info "git -C \"\$(brew --repo homebrew/cask)\" remote set-url origin https://github.com/Homebrew/homebrew-cask.git"
        return 0
    fi

    local mirror_base
    mirror_base="$(get_mirror_url "$src" "homebrew")"
    [[ -z "$mirror_base" ]] && { error "homebrew: 未找到镜像源 URL"; return 2; }

    mirror_base="$(echo "$mirror_base" | sed 's|/*$||')"

    # 根据镜像源设置不同的 URL
    case "$src" in
        1) # 阿里云
            local brew_mirror="${mirror_base}/brew.git"
            local core_mirror="${mirror_base}/homebrew-core.git"
            local cask_mirror="${mirror_base}/homebrew-cask.git"
            local bottles_url="${mirror_base}/bottles"
            ;;
        2) # 清华
            local brew_mirror="${mirror_base}/brew.git"
            local core_mirror="${mirror_base}/homebrew-core.git"
            local cask_mirror="${mirror_base}/homebrew-cask.git"
            local bottles_url="https://mirrors.tuna.tsinghua.edu.cn/homebrew-bottles"
            ;;
        3) # 中科大
            local brew_mirror="${mirror_base}/brew.git"
            local core_mirror="${mirror_base}/homebrew-core.git"
            local cask_mirror="${mirror_base}/homebrew-cask.git"
            local bottles_url="${mirror_base}/bottles"
            ;;
        4) # 华为云
            local brew_mirror="${mirror_base}/brew.git"
            local core_mirror="${mirror_base}/homebrew-core.git"
            local cask_mirror="${mirror_base}/homebrew-cask.git"
            local bottles_url="${mirror_base}/bottles"
            ;;
    esac

    # 替换 brew 仓库 remote
    if [[ -d "$(brew --repo 2>/dev/null)" ]]; then
        git -C "$(brew --repo)" remote set-url origin "$brew_mirror" 2>/dev/null || true
    fi
    if [[ -d "$(brew --repo homebrew/core 2>/dev/null)" ]]; then
        git -C "$(brew --repo homebrew/core)" remote set-url origin "$core_mirror" 2>/dev/null || true
    fi
    if [[ -d "$(brew --repo homebrew/cask 2>/dev/null)" ]]; then
        git -C "$(brew --repo homebrew/cask)" remote set-url origin "$cask_mirror" 2>/dev/null || true
    fi

    # 设置 bottles 环境变量
    backup_file "$SHELL_RC"
    grep -v "HOMEBREW_BOTTLE_DOMAIN" "$SHELL_RC" > "${SHELL_RC}.tmp" || true
    echo "# homebrew mirror (configured by set-mirrors.sh)" >> "${SHELL_RC}.tmp"
    echo "export HOMEBREW_BOTTLE_DOMAIN=\"${bottles_url}\"" >> "${SHELL_RC}.tmp"
    mv "${SHELL_RC}.tmp" "$SHELL_RC"
    export HOMEBREW_BOTTLE_DOMAIN="${bottles_url}"

    ok "homebrew: 已配置为 $(get_source_name "$src") 镜像"
    info "brew 仓库 remote 已更新，bottles 环境变量已写入 ${SHELL_RC}"
    info "运行 brew update 测试: brew update"

    return 0
}

# ==============================================================================
#  🔥 Git 加速配置
#  模式: 1=ghproxy 加速, 2=HTTP 代理, 0=恢复官方
# ==============================================================================

# 显示 ghproxy 节点选择菜单
select_ghproxy_node() {
    echo "" >&2
    echo "选择 ghproxy 服务:" >&2
    echo "  1) ghproxy.net" >&2
    echo "  2) ghproxy.com" >&2
    echo "  3) gh.api.99988866.xyz" >&2
    echo "" >&2
    echo -n "请输入编号 [默认 1]: " >&2
    read -r node_choice
    case "${node_choice:-1}" in
        1) echo "https://ghproxy.net" ;;
        2) echo "https://ghproxy.com" ;;
        3) echo "https://gh.api.99988866.xyz" ;;
        *) echo "https://ghproxy.net" ;;
    esac
}

configure_git() {
    local mode="$1"

    if ! has_cmd git; then
        error "git 未安装！"
        return 1
    fi

    case "$mode" in
        1|"")
            # ghproxy 加速
            local ghproxy_url
            ghproxy_url="$(select_ghproxy_node)"

            # 设置 insteadof
            git config --global "url.${ghproxy_url}/https://github.com/.insteadof" "https://github.com/"
            ok "git: 已配置 ghproxy 加速 → ${ghproxy_url}"
            info "配置内容: url.${ghproxy_url}/https://github.com/.insteadof = https://github.com/"

            # 也配置 SSH 方式提示
            info "注意: SSH 方式 (git@github.com) 不受影响，如需要 SSH 代理请手动配置 ~/.ssh/config"
            ;;

        2)
            # HTTP 代理
            echo ""
            echo -n "请输入 HTTP 代理地址 (例如 http://127.0.0.1:7890): "
            read -r proxy_url
            if [[ -z "$proxy_url" ]]; then
                error "代理地址不能为空！"
                return 1
            fi

            git config --global http.proxy "$proxy_url"
            git config --global https.proxy "$proxy_url"
            ok "git: HTTP 代理已配置 → $proxy_url"
            ;;

        0)
            # 恢复官方直连
            # 移除 ghproxy 相关
            local current_urls
            current_urls="$(git config --global --get-regexp 'url\..*\.insteadof' 2>/dev/null | awk '{print $1}' | sed 's/\.insteadof//')" || true
            if [[ -n "$current_urls" ]]; then
                while IFS= read -r url_key; do
                    git config --global --unset "url.${url_key}.insteadof" 2>/dev/null || true
                done <<< "$current_urls"
            fi

            # 移除 HTTP 代理
            git config --global --unset http.proxy 2>/dev/null || true
            git config --global --unset https.proxy 2>/dev/null || true

            # 移除 SSH 代理配置（如果之前设置过）
            warn "SSH 代理配置（~/.ssh/config）需要手动移除"

            ok "git: 已恢复官方直连"
            info "如需确认: git config --global --get-regexp 'url\\.'"
            ;;

        *)
            error "Git 加速模式错误: $mode (支持: 1=ghproxy, 2=HTTP代理, 0=恢复官方)"
            return 2
            ;;
    esac

    return 0
}

# ==============================================================================
#  查看当前配置
# ==============================================================================
show_status() {
    header
    echo -e "  ${BOLD}▶ 当前镜像源配置概览${NC}"
    header

    # 检测各包管理器配置
    # npm
    if has_cmd npm; then
        local npm_registry
        npm_registry="$(npm config get registry 2>/dev/null)"
        echo -e "  ${CYAN}npm${NC}     : ${npm_registry:-未设置}"
    fi

    # pnpm
    if has_cmd pnpm; then
        local pnpm_registry
        pnpm_registry="$(pnpm config get registry 2>/dev/null)"
        echo -e "  ${CYAN}pnpm${NC}    : ${pnpm_registry:-未设置}"
    fi

    # yarn
    if has_cmd yarn; then
        local yarn_registry
        yarn_registry="$(yarn config get registry 2>/dev/null)"
        echo -e "  ${CYAN}yarn${NC}    : ${yarn_registry:-未设置}"
    fi

    # bun
    if has_cmd bun; then
        if [[ -f "$HOME/.bunfig.toml" ]]; then
            local bun_registry
            bun_registry="$(grep '^registry\s*=' "$HOME/.bunfig.toml" 2>/dev/null | head -1 | sed 's/^registry\s*=\s*"\(.*\)"/\1/')"
            echo -e "  ${CYAN}bun${NC}     : ${bun_registry:-已配置(见 ~/.bunfig.toml)}"
        else
            echo -e "  ${CYAN}bun${NC}     : 未配置"
        fi
    fi

    # pip
    if has_cmd pip || has_cmd pip3; then
        local pip_conf="$HOME/.pip/pip.conf"
        if [[ -f "$pip_conf" ]]; then
            local pip_index
            pip_index="$(grep 'index-url' "$pip_conf" 2>/dev/null | head -1 | awk '{print $3}')"
            echo -e "  ${CYAN}pip${NC}     : ${pip_index:-已配置(见 ~/.pip/pip.conf)}"
        else
            echo -e "  ${CYAN}pip${NC}     : 未配置"
        fi
    fi

    # gem
    if has_cmd gem; then
        local gem_sources
        gem_sources="$(gem sources -l 2>/dev/null | grep -v '^\*' | head -3 | tr '\n' ' ')"
        echo -e "  ${CYAN}gem${NC}     : ${gem_sources:-未配置}"
    fi

    # cargo
    if has_cmd cargo; then
        local cargo_config="$HOME/.cargo/config.toml"
        if [[ -f "$cargo_config" ]] && grep -q 'replace-with' "$cargo_config"; then
            local cargo_mirror
            cargo_mirror="$(grep -A2 '\[source\.mirror\]' "$cargo_config" 2>/dev/null | grep 'registry' | awk '{print $3}')"
            echo -e "  ${CYAN}cargo${NC}   : ${cargo_mirror:-已配置(见 ~/.cargo/config.toml)}"
        else
            echo -e "  ${CYAN}cargo${NC}   : 未配置"
        fi
    fi

    # rustup
    if has_cmd rustup; then
        echo -e "  ${CYAN}rustup${NC}  : ${RUSTUP_DIST_SERVER:-未设置环境变量}"
    fi

    # go
    if has_cmd go; then
        local goproxy
        goproxy="$(go env GOPROXY 2>/dev/null)"
        echo -e "  ${CYAN}go${NC}      : ${goproxy:-未设置}"
    fi

    # conda
    if has_cmd conda; then
        local conda_channels
        conda_channels="$(conda config --show channels 2>/dev/null | head -5)"
        echo -e "  ${CYAN}conda${NC}   : $(echo "$conda_channels" | head -2 | tr '\n' ' ')"
    fi

    # composer
    if has_cmd composer; then
        local composer_repo
        composer_repo="$(composer config -g repos.packagist 2>/dev/null || echo "未配置")"
        echo -e "  ${CYAN}composer${NC}: ${composer_repo}"
    fi

    # apt (需要 sudo)
    if [[ "$OS" == "linux" ]] && [[ -f /etc/apt/sources.list ]]; then
        local apt_source
        apt_source="$(head -5 /etc/apt/sources.list 2>/dev/null | grep '^deb ' | head -1 | awk '{print $2}')"
        echo -e "  ${CYAN}apt${NC}     : ${apt_source:-未配置(或非标准格式)}"
    fi

    # docker
    if has_cmd docker; then
        local docker_mirrors
        docker_mirrors="$(docker info 2>/dev/null | grep -A 1 'Registry Mirrors' | tail -1 | xargs)"
        echo -e "  ${CYAN}docker${NC}  : ${docker_mirrors:-未配置}"
    fi

    # nvm
    if [[ -f "$HOME/.nvm/nvm.sh" ]]; then
        echo -e "  ${CYAN}nvm${NC}     : ${NVM_NODEJS_ORG_MIRROR:-未设置环境变量}"
    fi

    # flutter
    if has_cmd flutter; then
        echo -e "  ${CYAN}flutter${NC}: ${FLUTTER_STORAGE_BASE_URL:-未设置环境变量}"
    fi

    # homebrew
    if has_cmd brew; then
        local brew_remote
        brew_remote="$(git -C "$(brew --repo 2>/dev/null)" remote get-url origin 2>/dev/null)" || brew_remote="未知"
        echo -e "  ${CYAN}homebrew${NC}: ${brew_remote}"
        echo -e "  ${CYAN}  bottles${NC}: ${HOMEBREW_BOTTLE_DOMAIN:-未设置}"
    fi

    # git
    local git_insteadof
    git_insteadof="$(git config --global --get-regexp 'url\.' 2>/dev/null | head -3)"
    local git_proxy
    git_proxy="$(git config --global --get http.proxy 2>/dev/null)"
    if [[ -n "$git_insteadof" ]]; then
        echo -e "  ${CYAN}git${NC}     : ghproxy 加速已配置"
        echo "$git_insteadof" | while IFS= read -r line; do echo "            $line"; done
    elif [[ -n "$git_proxy" ]]; then
        echo -e "  ${CYAN}git${NC}     : HTTP 代理 → $git_proxy"
    else
        echo -e "  ${CYAN}git${NC}     : 未配置加速"
    fi

    header
    info "提示: 运行 source ${SHELL_RC} 重载环境变量"
}

# ==============================================================================
#  交互菜单
# ==============================================================================

# 选择镜像源
select_source() {
    local prompt_text="$1"
    echo "" >&2
    echo "选择镜像源:" >&2
    echo "  1) 阿里云        (国内首选，速度快)" >&2
    echo "  2) 清华大学 TUNA (教育网推荐)" >&2
    echo "  3) 中科大 USTC   (教育网推荐)" >&2
    echo "  4) 华为云        (企业用户推荐)" >&2
    echo "  0) 恢复官方源" >&2
    echo "" >&2
    echo -n "${prompt_text:-请输入编号 [默认 1]: }" >&2
    read -r src_choice
    echo "${src_choice:-1}"
}

# 单项选择菜单
select_single_item() {
    local src_name="$1"
    echo "" >&2
    echo "请选择要配置的项 (${src_name}):" >&2
    echo "  ┌─────────────────────────────────────────────┐" >&2
    echo "  │  a)  npm    b)  pnpm    c)  yarn    d)  bun │" >&2
    echo "  │  e)  pip    f)  gem     g)  bundler h)  cargo│" >&2
    echo "  │  i)  rustup j)  go      k)  conda   l)  composer│" >&2
    echo "  │  m)  apt    n)  docker  o)  nvm     p)  flutter│" >&2
    echo "  │  q)  homebrew          r)  全部              │" >&2
    echo "  └─────────────────────────────────────────────┘" >&2
    echo "" >&2
    echo -n "请输入字母 [a-r]: " >&2
    read -r item_choice

    echo "$item_choice"
}

# 交互主菜单
interactive_menu() {
    local src_choice
    local src_name

    while true; do
        # 清屏效果
        echo ""
        echo -e "${BOLD}${MAGENTA}╔══════════════════════════════════════════════════╗${NC}"
        echo -e "${BOLD}${MAGENTA}║         🌐 一键镜像源配置工具 v${VERSION}               ║${NC}"
        echo -e "${BOLD}${MAGENTA}╚══════════════════════════════════════════════════╝${NC}"
        echo ""
        echo "请选择操作:"
        echo "  ┌─────────────────────────────────────────────┐"
        echo "  │  1)  选择镜像源并一键设置所有                │"
        echo "  │  2)  选择性配置单项                          │"
        echo "  │  3)  查看当前镜像源配置                      │"
        echo "  │  4)  🔥 Git 加速配置                        │"
        echo "  │  0)  退出                                    │"
        echo "  └─────────────────────────────────────────────┘"
        echo ""
        echo -n "请输入编号 [0-4]: "
        read -r main_choice

        case "$main_choice" in
            1)
                # 一键设置所有
                src_choice="$(select_source)"
                src_name="$(get_source_name "$src_choice")"
                echo ""
                info "即将配置所有已安装的包管理器为 ${src_name} ..."
                echo ""

                configure_all "$src_choice"

                echo ""
                ok "一键配置完成！"
                info "运行 source ${SHELL_RC} 重载环境变量"
                if [[ "$src_choice" != "0" ]]; then
                    warn "apt 和 docker 需要 sudo 权限: sudo bash $SCRIPT_NAME all $src_choice"
                fi
                echo ""
                echo -n "按回车键继续..."
                read -r
                ;;

            2)
                # 选择性配置单项
                src_choice="$(select_source)"
                src_name="$(get_source_name "$src_choice")"

                while true; do
                    local item
                    item="$(select_single_item "$src_name")"

                    case "$item" in
                        a) configure_npm "$src_choice" ;;
                        b) configure_pnpm "$src_choice" ;;
                        c) configure_yarn "$src_choice" ;;
                        d) configure_bun "$src_choice" ;;
                        e) configure_pip "$src_choice" ;;
                        f) configure_gem "$src_choice" ;;
                        g) configure_bundler "$src_choice" ;;
                        h) configure_cargo "$src_choice" ;;
                        i) configure_rustup "$src_choice" ;;
                        j) configure_go "$src_choice" ;;
                        k) configure_conda "$src_choice" ;;
                        l) configure_composer "$src_choice" ;;
                        m)
                            if is_sudo; then
                                configure_apt "$src_choice"
                            else
                                check_sudo_and_run "apt $src_choice"
                            fi
                            ;;
                        n)
                            if is_sudo; then
                                configure_docker "$src_choice"
                            else
                                check_sudo_and_run "docker $src_choice"
                            fi
                            ;;
                        o) configure_nvm "$src_choice" ;;
                        p) configure_flutter "$src_choice" ;;
                        q) configure_homebrew "$src_choice" ;;
                        r) configure_all "$src_choice" ;;
                        *)
                            break 2
                            ;;
                    esac

                    echo ""
                    echo -n "按回车键继续单项配置，输入 q 返回主菜单..."
                    read -r cont
                    [[ "$cont" == "q" ]] && break
                done
                ;;

            3)
                show_status
                echo ""
                echo -n "按回车键继续..."
                read -r
                ;;

            4)
                # Git 加速
                echo ""
                echo "🔥 Git 加速配置:"
                echo "  1) ghproxy 加速 (推荐)"
                echo "  2) 自定义 HTTP 代理"
                echo "  0) 恢复官方直连"
                echo ""
                echo -n "请选择模式 [0-2], 默认 1: "
                read -r git_mode
                configure_git "${git_mode:-1}"
                echo ""
                echo -n "按回车键继续..."
                read -r
                ;;

            0)
                echo ""
                ok "感谢使用！如有帮助请给个 Star ⭐"
                exit 0
                ;;

            *)
                warn "无效输入，请重新选择"
                sleep 1
                ;;
        esac
    done
}

# ==============================================================================
#  一键配置所有
#  参数: $1 = 镜像源编号
# ==============================================================================
configure_all() {
    local src="$1"
    local src_name
    src_name="$(get_source_name "$src")"

    info "开始配置所有已安装的包管理器为 ${src_name} ..."
    echo ""

    # 非 sudo 部分
    configure_npm "$src"
    configure_pnpm "$src"
    configure_yarn "$src"
    configure_bun "$src"
    configure_pip "$src"
    configure_gem "$src"
    configure_bundler "$src"
    configure_cargo "$src"
    configure_rustup "$src"
    configure_go "$src"
    configure_conda "$src"
    configure_composer "$src"
    configure_nvm "$src"
    configure_flutter "$src"
    configure_homebrew "$src"

    # sudo 部分（如果有 sudo 权限）
    if is_sudo; then
        configure_apt "$src"
        configure_docker "$src"
    else
        echo ""
        warn "跳过 apt 和 docker（需要 root 权限）"
        warn "请另行执行: sudo bash $SCRIPT_NAME all $src"
    fi

    echo ""
    ok "所有已安装的包管理器配置完成！"
}

# ==============================================================================
#  帮助信息
# ==============================================================================
show_help() {
    echo ""
    echo -e "${BOLD}🌐 一键镜像源配置工具 v${VERSION}${NC}"
    echo ""
    echo "用法:"
    echo -e "  bash ${SCRIPT_NAME} ${GREEN}<命令>${NC} ${YELLOW}[镜像源编号]${NC}"
    echo ""
    echo "命令:"
    echo "  interactive, i       进入交互菜单"
    echo "  all, a               一键配置所有包管理器"
    echo "  show, status         查看当前镜像源配置"
    echo "  help                 显示帮助信息"
    echo ""
    echo "单项配置 (直接使用包管理器名称):"
    echo "  npm pnpm yarn bun pip gem bundler"
    echo "  cargo rustup go conda composer"
    echo "  apt docker nvm flutter homebrew"
    echo "  git                   Git 加速配置"
    echo ""
    echo "镜像源编号:"
    echo "  1  阿里云 (默认)"
    echo "  2  清华大学 TUNA"
    echo "  3  中科大 USTC"
    echo "  4  华为云"
    echo "  0  恢复官方源"
    echo ""
    echo "Git 加速模式 (git 命令专用):"
    echo "  1  ghproxy 加速 (默认)"
    echo "  2  HTTP 代理"
    echo "  0  恢复官方直连"
    echo ""
    echo "示例:"
    echo "  bash ${SCRIPT_NAME} i              # 交互菜单"
    echo "  bash ${SCRIPT_NAME} all            # 一键阿里云"
    echo "  bash ${SCRIPT_NAME} all 2          # 一键清华"
    echo "  bash ${SCRIPT_NAME} pip 3          # 单独配置 pip 为中科大"
    echo "  bash ${SCRIPT_NAME} go 4           # 单独配置 go 为华为云"
    echo "  bash ${SCRIPT_NAME} show           # 查看配置"
    echo "  bash ${SCRIPT_NAME} git            # Git ghproxy 加速"
    echo "  bash ${SCRIPT_NAME} git 2          # Git HTTP 代理"
    echo "  sudo bash ${SCRIPT_NAME} apt 1     # apt 阿里云"
    echo "  sudo bash ${SCRIPT_NAME} docker 2  # docker 清华"
    echo ""
}

# ==============================================================================
#  主入口
# ==============================================================================
main() {
    local cmd="${1:-interactive}"
    local arg="${2:-}"

    # 去除可能的引号、空格
    cmd="$(echo "$cmd" | xargs)"
    arg="$(echo "$arg" | xargs)"

    # 如果没有参数或只有 -h/--help
    case "$cmd" in
        -h|--help|help)
            show_help
            exit 0
            ;;
        -v|--version|version)
            echo "🌐 一键镜像源配置工具 v${VERSION}"
            exit 0
            ;;
    esac

    # 根据命令分发
    case "$cmd" in
        interactive|i)
            interactive_menu
            ;;

        all|a)
            configure_all "${arg:-1}"
            ;;

        show|status)
            show_status
            ;;

        # 包管理器单项
        npm)        configure_npm "${arg:-1}" ;;
        pnpm)       configure_pnpm "${arg:-1}" ;;
        yarn)       configure_yarn "${arg:-1}" ;;
        bun)        configure_bun "${arg:-1}" ;;
        pip)        configure_pip "${arg:-1}" ;;
        gem)        configure_gem "${arg:-1}" ;;
        bundler)    configure_bundler "${arg:-1}" ;;
        cargo)      configure_cargo "${arg:-1}" ;;
        rustup)     configure_rustup "${arg:-1}" ;;
        go)         configure_go "${arg:-1}" ;;
        conda)      configure_conda "${arg:-1}" ;;
        composer)   configure_composer "${arg:-1}" ;;
        apt)
            if is_sudo; then
                configure_apt "${arg:-1}"
            else
                error "apt 配置需要 root 权限！请使用: sudo bash $SCRIPT_NAME apt ${arg:-1}"
                exit 1
            fi
            ;;
        docker)
            if is_sudo; then
                configure_docker "${arg:-1}"
            else
                error "docker 配置需要 root 权限！请使用: sudo bash $SCRIPT_NAME docker ${arg:-1}"
                exit 1
            fi
            ;;
        nvm)        configure_nvm "${arg:-1}" ;;
        flutter)    configure_flutter "${arg:-1}" ;;
        homebrew)   configure_homebrew "${arg:-1}" ;;
        git)        configure_git "${arg:-1}" ;;

        *)
            error "未知命令: $cmd"
            echo "使用 'bash $SCRIPT_NAME help' 查看帮助"
            exit 1
            ;;
    esac
}

# 执行主入口
main "$@"
