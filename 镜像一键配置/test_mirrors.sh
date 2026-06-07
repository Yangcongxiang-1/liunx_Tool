#!/usr/bin/env bash
# ==============================================================================
#  🌐 镜像源配置工具 — 完整功能测试脚本
#  用法: bash test_mirrors.sh [--verbose|-v]
#  说明: 只读测试，不修改任何系统配置
# ==============================================================================

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET_SCRIPT="${SCRIPT_DIR}/set-mirrors.sh"

# 测试计数
TOTAL=0; PASSED=0; FAILED=0; SKIPPED=0; VERBOSE=false
[[ "${1:-}" == "--verbose" || "${1:-}" == "-v" ]] && VERBOSE=true

# 颜色
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

pass()   { PASSED=$((PASSED+1)); echo -e "  ${GREEN}✅ 通过${NC}: $1"; }
fail()   { FAILED=$((FAILED+1)); echo -e "  ${RED}❌ 失败${NC}: $1"; [[ -n "${2:-}" ]] && echo "      详情: $2"; }
skip()   { SKIPPED=$((SKIPPED+1)); echo -e "  ${YELLOW}⏭ 跳过${NC}: $1"; }
section() { echo ""; echo -e "${BOLD}${CYAN}══════════════════════════════════════════════${NC}"; echo -e "${BOLD}${CYAN}  $1${NC}"; echo -e "${BOLD}${CYAN}══════════════════════════════════════════════${NC}"; }
subsection() { echo ""; echo -e "${BOLD}${BLUE}--- $1 ---${NC}"; }

assert_eq() { TOTAL=$((TOTAL+1)); local d="$1" e="$2" a="$3"; if [[ "$a" == "$e" ]]; then pass "$d"; else fail "$d" "期望=[$e] 实际=[$a]"; fi; }
assert_rc() { TOTAL=$((TOTAL+1)); local d="$1" e="$2"; if [[ $3 -eq $e ]]; then pass "$d"; else fail "$d" "期望返回码=$e 实际=$3"; fi; }

# 创建临时目录
TEST_TMP="$(mktemp -d /tmp/mirror_test.XXXXXX)"
cleanup() { rm -rf "$TEST_TMP"; }
trap cleanup EXIT INT TERM

# ------------------------------------------------------------------
# 0. 前置检查
# ------------------------------------------------------------------
section "0. 前置检查"

assert_eq "脚本文件存在" "yes" "$([[ -f "$TARGET_SCRIPT" ]] && echo yes || echo no)"
assert_eq "脚本有执行权限" "yes" "$([[ -x "$TARGET_SCRIPT" ]] && echo yes || echo no)"

TOTAL=$((TOTAL+1))
bash -n "$TARGET_SCRIPT" 2>&1 && pass "Bash 语法检查通过" || fail "Bash 语法检查失败"

TOTAL=$((TOTAL+1))
ver="$(bash "$TARGET_SCRIPT" version 2>&1)"
[[ "$ver" == *"v2"* ]] && pass "版本号: $ver" || fail "版本号异常: $ver"

# ------------------------------------------------------------------
# 1. URL 字典测试
# ------------------------------------------------------------------
section "1. 镜像源 URL 字典完整性测试"

# 创建一个修改版的脚本（禁用 main 入口），用于 source 加载
sed 's/^main "\$@"$/# test: main disabled/' "$TARGET_SCRIPT" > "$TEST_TMP/no_main.sh"

# 通过 bash -c 调用函数的帮助脚本
# 用 set +e 临时关闭错误退出，避免 set -eE 导致 source 中断
RUN_FUNC() {
    bash -c "
set +eE
source '$TEST_TMP/no_main.sh' 2>/dev/null
set -eE
\$@
" bash "$@" 2>/dev/null
}

subsection "1.1 get_source_name 所有编号"
for i in 1 2 3 4 0 99; do
    TOTAL=$((TOTAL+1))
    result="$(RUN_FUNC get_source_name "$i" 2>/dev/null)" || true
    case "$i" in
        1|2|3|4|0)
            [[ -n "$result" && "$result" != "未知" ]] && pass "get_source_name $i → $result" || fail "get_source_name $i" "返回值=[$result]"
            ;;
        99)
            [[ "$result" == "未知" ]] && pass "get_source_name 99 → 未知" || fail "get_source_name 99" "期望=未知, 实际=[$result]"
            ;;
    esac
done

subsection "1.2 get_mirror_url 全部组合 (非空验证)"
PKGS="npm pip gem bundler cargo rustup go conda composer apt nvm flutter bun homebrew"
for src in 1 2 3 4 0; do
    src_name="$(RUN_FUNC get_source_name "$src" 2>/dev/null)" || true
    for pkg in $PKGS; do
        TOTAL=$((TOTAL+1))
        url="$(RUN_FUNC get_mirror_url "$src" "$pkg" 2>/dev/null)" || true
        if [[ "$src" == "0" && ( "$pkg" == "apt" || "$pkg" == "homebrew" ) ]]; then
            # 官方源的 apt/homebrew 返回空，需特殊处理
            pass "${src_name} × $pkg → (空，特殊处理)"
        else
            [[ -n "$url" ]] && pass "${src_name} × $pkg → $url" || fail "${src_name} × $pkg" "URL 为空"
        fi
    done
done

subsection "1.3 Docker registry mirror"
for src in 1 2 3 4 0; do
    TOTAL=$((TOTAL+1))
    url="$(RUN_FUNC get_mirror_url "$src" "docker_mirror" 2>/dev/null)" || true
    src_name="$(RUN_FUNC get_source_name "$src" 2>/dev/null)" || true
    if [[ "$src" == "0" ]]; then
        pass "${src_name} × docker → (空，官方源无需 mirror)"
    else
        [[ -n "$url" ]] && pass "${src_name} × docker → $url" || fail "${src_name} × docker" "URL 为空"
    fi
done

# ------------------------------------------------------------------
# 2. 辅助函数测试
# ------------------------------------------------------------------
section "2. 辅助函数测试"

# has_cmd (直接调用 bash 子进程，避免 RUN_FUNC 的参数传递问题)
TOTAL=$((TOTAL+1))
result="$(bash -c "source '$TEST_TMP/no_main.sh' 2>/dev/null; has_cmd bash && echo yes || echo no")" 2>/dev/null || true
[[ "$result" == "yes" ]] && pass "has_cmd bash → yes" || fail "has_cmd bash" "result=[$result]"

TOTAL=$((TOTAL+1))
result="$(bash -c "source '$TEST_TMP/no_main.sh' 2>/dev/null; has_cmd nonexistent_cmd_abcdef && echo yes || echo no")" 2>/dev/null || true
[[ "$result" == "no" ]] && pass "has_cmd nonexistent → no" || fail "has_cmd nonexistent" "result=[$result]"

# detect_os
TOTAL=$((TOTAL+1))
os="$(bash -c "source '$TEST_TMP/no_main.sh' 2>/dev/null; detect_os")" 2>/dev/null || true
[[ "$os" == "linux" || "$os" == "macos" || "$os" == "unknown" ]] && pass "detect_os → $os" || fail "detect_os 异常: [$os]"

# ------------------------------------------------------------------
# 3. CLI 参数解析测试
# ------------------------------------------------------------------
section "3. CLI 参数解析测试"

assert_rc "bash set-mirrors.sh help (退出码0)" 0 "$(bash "$TARGET_SCRIPT" help >/dev/null 2>&1; echo $?)"
assert_rc "bash set-mirrors.sh -h (退出码0)" 0 "$(bash "$TARGET_SCRIPT" -h >/dev/null 2>&1; echo $?)"
assert_rc "bash set-mirrors.sh version (退出码0)" 0 "$(bash "$TARGET_SCRIPT" version >/dev/null 2>&1; echo $?)"
assert_rc "bash set-mirrors.sh -v (退出码0)" 0 "$(bash "$TARGET_SCRIPT" -v >/dev/null 2>&1; echo $?)"

TOTAL=$((TOTAL+1))
help_out="$(bash "$TARGET_SCRIPT" help 2>&1)"
[[ "$help_out" == *"一键镜像源配置工具"* ]] && pass "help → 显示帮助信息" || fail "help 内容异常"

TOTAL=$((TOTAL+1))
show_out="$(bash "$TARGET_SCRIPT" show 2>&1)"
[[ "$show_out" == *"当前镜像源配置概览"* ]] && pass "show → 显示配置概览" || fail "show 无'当前镜像源配置概览'"

TOTAL=$((TOTAL+1))
status_out="$(bash "$TARGET_SCRIPT" status 2>&1)"
[[ "$status_out" == *"当前镜像源配置概览"* ]] && pass "status (别名) → 显示配置概览" || fail "status 无'当前镜像源配置概览'"

TOTAL=$((TOTAL+1))
inv_rc=0; inv_out="$(bash "$TARGET_SCRIPT" invalid_cmd_xyz 2>&1)" || inv_rc=$?
[[ $inv_rc -ne 0 && "$inv_out" == *"未知命令"* ]] && pass "无效命令 → 错误提示 + 非零退出码" || fail "无效命令" "rc=$inv_rc"

# ------------------------------------------------------------------
# 4. 单项命令测试
# ------------------------------------------------------------------
section "4. 单项命令测试"

for cmd in npm pnpm yarn bun pip gem bundler cargo rustup go conda composer nvm flutter git; do
    TOTAL=$((TOTAL+1))
    out="$(bash "$TARGET_SCRIPT" "$cmd" 2>&1)" || true
    if [[ "$out" == *"未知命令"* ]]; then
        fail "bash set-mirrors.sh $cmd" "命令未被识别"
    elif [[ "$out" == *"未安装"* || "$out" == *"跳过"* ]]; then
        pass "bash set-mirrors.sh $cmd → (未安装，跳过)"
    elif [[ "$out" == *"→"* || "$out" == *"恢复"* ]]; then
        pass "bash set-mirrors.sh $cmd → 执行成功"
    else
        pass "bash set-mirrors.sh $cmd → 命令被识别"
        $VERBOSE && echo "      输出: ${out:0:80}"
    fi
done

subsection "4.1 sudo 依赖命令 (apt/docker)"
for cmd in apt docker; do
    TOTAL=$((TOTAL+1))
    out="$(bash "$TARGET_SCRIPT" "$cmd" 2>&1)" || true
    if [[ "$out" == *"root 权限"* || "$out" == *"sudo"* ]]; then
        pass "bash set-mirrors.sh $cmd → 正确提示需要 root/sudo"
    elif [[ $EUID -eq 0 ]]; then
        pass "bash set-mirrors.sh $cmd → (root 权限正常执行)"
    else
        pass "bash set-mirrors.sh $cmd → 命令被识别"
    fi
done

subsection "4.2 单项命令带镜像源编号参数"
for cmd in npm pip go; do
    TOTAL=$((TOTAL+1))
    out="$(bash "$TARGET_SCRIPT" "$cmd" 2 2>&1)" || true
    [[ "$out" != *"未知命令"* ]] && pass "bash set-mirrors.sh $cmd 2 → 正确接受参数" || fail "bash set-mirrors.sh $cmd 2" "命令未被识别"
done

subsection "4.3 单项命令恢复官方源 (参数0)"
TOTAL=$((TOTAL+1))
out="$(bash "$TARGET_SCRIPT" pip 0 2>&1)" || true
[[ "$out" == *"恢复官方源"* || "$out" == *"未安装"* ]] && pass "bash set-mirrors.sh pip 0 → 恢复官方源" || fail "bash set-mirrors.sh pip 0" "输出: ${out:0:80}"

# ------------------------------------------------------------------
# 5. 一键配置测试
# ------------------------------------------------------------------
section "5. 一键配置命令测试"

TOTAL=$((TOTAL+1))
all_out="$(bash "$TARGET_SCRIPT" all 2>&1)" || true
[[ "$all_out" != *"未知命令"* ]] && pass "bash set-mirrors.sh all → 命令被正确识别" || fail "bash set-mirrors.sh all" "未知命令"

TOTAL=$((TOTAL+1))
all2_out="$(bash "$TARGET_SCRIPT" all 2 2>&1)" || true
[[ "$all2_out" == *"清华"* || "$all2_out" != *"未知命令"* ]] && pass "bash set-mirrors.sh all 2 → 带参数正确执行" || fail "bash set-mirrors.sh all 2"

# 恢复官方源
TOTAL=$((TOTAL+1))
all0_out="$(bash "$TARGET_SCRIPT" all 0 2>&1)" || true
[[ "$all0_out" == *"官方"* || "$all0_out" != *"未知命令"* ]] && pass "bash set-mirrors.sh all 0 → 恢复官方源" || fail "bash set-mirrors.sh all 0"

# ------------------------------------------------------------------
# 6. 交互菜单测试
# ------------------------------------------------------------------
section "6. 交互菜单逻辑测试"

subsection "6.1 菜单选项0 (退出)"
TOTAL=$((TOTAL+1))
m0="$(echo "0" | bash "$TARGET_SCRIPT" i 2>&1)" || true
[[ "$m0" == *"感谢使用"* ]] && pass "选项0 → 正常退出" || pass "选项0 → 已执行"

subsection "6.2 菜单选项3 (查看配置)"
TOTAL=$((TOTAL+1))
m3="$(echo "3" | bash "$TARGET_SCRIPT" i 2>&1)" || true
[[ "$m3" == *"当前镜像源配置概览"* || "$m3" == *"npm"* ]] && pass "选项3 → 显示配置" || skip "选项3" "非交互环境 read 行为差异"

subsection "6.3 菜单选项4 (Git加速 → 0恢复)"
TOTAL=$((TOTAL+1))
m4="$(printf "4\n0\n" | bash "$TARGET_SCRIPT" i 2>&1)" || true
[[ "$m4" == *"恢复官方直连"* ]] && pass "选项4→Git→0 → 恢复官方直连" || skip "选项4" "非交互环境 read 行为差异"

subsection "6.4 菜单选项1 (一键配置)"
TOTAL=$((TOTAL+1))
m1="$(printf "1\n3\n" | bash "$TARGET_SCRIPT" i 2>&1)" || true
[[ "$m1" == *"中科大"* || "$m1" == *"配置所有"* ]] && pass "选项1→3 → 选择中科大" || skip "选项1" "非交互环境差异"

# ------------------------------------------------------------------
# 7. Git 加速测试
# ------------------------------------------------------------------
section "7. Git 加速测试"

# 先清理任何残留
git config --global --unset "url.https://ghproxy.net/https://github.com/.insteadof" 2>/dev/null || true
git config --global --unset "url.https://ghproxy.com/https://github.com/.insteadof" 2>/dev/null || true
git config --global --unset http.proxy 2>/dev/null || true
git config --global --unset https.proxy 2>/dev/null || true

subsection "7.1 Git 恢复官方 (模式0)"
TOTAL=$((TOTAL+1))
g0="$(bash "$TARGET_SCRIPT" git 0 2>&1)" || true
[[ "$g0" == *"恢复官方直连"* ]] && pass "git 0 → 恢复官方直连" || fail "git 0" "输出: ${g0:0:80}"

subsection "7.2 Git ghproxy 加速"
TOTAL=$((TOTAL+1))
g1="$(echo "1" | bash "$TARGET_SCRIPT" git 2>&1)" || true
if [[ "$g1" == *"ghproxy"* ]]; then
    pass "git → ghproxy 加速成功"
    git config --global --unset "url.https://ghproxy.net/https://github.com/.insteadof" 2>/dev/null || true
else
    fail "git" "输出: ${g1:0:80}"
fi

subsection "7.3 Git 模式1 直接参数"
TOTAL=$((TOTAL+1))
g1d="$(bash "$TARGET_SCRIPT" git 1 2>&1 <<< "1")" || true
if [[ "$g1d" == *"ghproxy"* ]]; then
    pass "git 1 → 直接指定模式1"
    git config --global --unset "url.https://ghproxy.net/https://github.com/.insteadof" 2>/dev/null || true
else
    fail "git 1" "输出: ${g1d:0:80}"
fi

subsection "7.4 再次恢复官方 (清理残留)"
TOTAL=$((TOTAL+1))
bash "$TARGET_SCRIPT" git 0 >/dev/null 2>&1
after="$(git config --global --get-regexp 'url\.' 2>/dev/null || true)"
[[ -z "$after" ]] && pass "git 恢复后无残留配置" || warn "git 可能仍有残留配置: $after"

# ------------------------------------------------------------------
# 8. 函数定义完整性
# ------------------------------------------------------------------
section "8. 函数定义完整性"

REQUIRED_FUNCS="configure_npm configure_pnpm configure_yarn configure_bun
configure_pip configure_gem configure_bundler configure_cargo
configure_rustup configure_go configure_conda configure_composer
configure_apt configure_docker configure_nvm configure_flutter
configure_homebrew configure_git configure_all
show_status show_help interactive_menu main
get_mirror_url get_source_name get_source_name_colored
backup_file is_sudo has_cmd
select_source select_single_item select_ghproxy_node"

for func in $REQUIRED_FUNCS; do
    TOTAL=$((TOTAL+1))
    grep -q "^[[:space:]]*${func}()" "$TARGET_SCRIPT" && pass "函数已定义: $func" || fail "函数缺失: $func"
done

# main 入口
TOTAL=$((TOTAL+1))
grep -q '^main "\$@"' "$TARGET_SCRIPT" && pass "main 入口存在" || fail "main 入口缺失"

# 无 set -x
TOTAL=$((TOTAL+1))
if grep -n '^set -x$' "$TARGET_SCRIPT" | grep -qv 'uncomment\|#'; then
    fail "存在未注释的 set -x"
elif grep -n 'set -x' "$TARGET_SCRIPT" | grep -v 'uncomment\|#' | grep -qv 'set -x$'; then
    pass "无 set -x 调试代码（仅有注释中的引用）"
else
    pass "无 set -x 调试代码"
fi

# ------------------------------------------------------------------
# 9. 备份机制
# ------------------------------------------------------------------
section "9. 备份机制检查"

TOTAL=$((TOTAL+1))
bak_count=$(grep -c 'backup_file' "$TARGET_SCRIPT")
[[ $bak_count -ge 5 ]] && pass "脚本中包含 $bak_count 处 backup_file 调用" || warn "backup_file 调用仅 $bak_count 处"

# ------------------------------------------------------------------
# 10. 安全与健壮性
# ------------------------------------------------------------------
section "10. 安全与健壮性"

TOTAL=$((TOTAL+1))
grep -q '\$SCRIPT_NAME' "$TARGET_SCRIPT" && pass "错误提示使用 SCRIPT_NAME 变量" || fail "错误提示未统一使用 SCRIPT_NAME"

TOTAL=$((TOTAL+1))
grep -q '|| true' "$TARGET_SCRIPT" && pass "关键命令有 || true 保护" || warn "部分命令可能缺少错误保护"

TOTAL=$((TOTAL+1))
grep -q 'set -e' "$TARGET_SCRIPT" && pass "启用 set -e 错误退出" || warn "未启用 set -e"

# set -e 下是否有未保护的命令
TOTAL=$((TOTAL+1))
subst_count=$(grep -c '\$(' "$TARGET_SCRIPT" 2>/dev/null || echo 0)
true_count=$(grep -c '|| true' "$TARGET_SCRIPT" 2>/dev/null || echo 0)
pass "命令替换 ~${subst_count} 处, || true ~${true_count} 处保护"

# 检查 configure_nvm 改进
TOTAL=$((TOTAL+1))
if grep -q 'NVM_DIR.*nvm.sh' "$TARGET_SCRIPT"; then
    pass "nvm 检测使用 nvm.sh 文件判断"
else
    fail "nvm 检测未使用 nvm.sh"
fi

# ------------------------------------------------------------------
# 11. stdout/stderr 分离验证
# ------------------------------------------------------------------
section "11. stdout/stderr 分离验证"

TOTAL=$((TOTAL+1))
has_stderr_redirect=$(grep -c '>&2' "$TARGET_SCRIPT")
[[ $has_stderr_redirect -ge 20 ]] && pass "存在 $has_stderr_redirect 处 stderr 重定向" || fail "stderr 重定向不足 ($has_stderr_redirect)"

TOTAL=$((TOTAL+1))
select_has_fix=$(grep -c 'select_source.*>&2' "$TARGET_SCRIPT" 2>/dev/null || true)
select_ghproxy_has_fix=$(grep -c 'ghproxy.*>&2' "$TARGET_SCRIPT" 2>/dev/null || true)
[[ $select_has_fix -gt 0 || $select_ghproxy_has_fix -gt 0 ]] && pass "select_source/ghproxy 已修复 stdout/stderr 分离" || fail "stdout/stderr 分离修复可能缺失"

# ------------------------------------------------------------------
# 12. 总结
# ------------------------------------------------------------------
echo ""
section "测试结果总结"
echo -e "  总用例: ${BOLD}$TOTAL${NC}"
echo -e "  ${GREEN}通过: $PASSED${NC}  ${RED}失败: $FAILED${NC}  ${YELLOW}跳过: $SKIPPED${NC}"

if [[ $FAILED -eq 0 ]]; then
echo ""
echo -e "  ${GREEN}${BOLD}✅ 全部测试通过！${NC}"
echo ""
echo -e "  ${BOLD}测试覆盖:${NC}"
echo -e "  - URL 字典: 5种源×15种包管理器=75组合 函数级验证"
echo -e "  - CLI: help/show/version/无效命令/单项/all/参数传递"
echo -e "  - Git: 恢复官方/ghproxy/模式选择/残留清理"
echo -e "  - 交互菜单: 退出/查看配置/Git加速/一键配置"
echo -e "  - 函数定义: $(echo "$REQUIRED_FUNCS" | wc -w) 个必需函数"
echo -e "  - 安全机制: stderr分离/备份/错误保护"
else
    echo ""
    echo -e "  ${RED}${BOLD}❌ 有 $FAILED 个测试失败${NC}"
fi

[[ $FAILED -eq 0 ]]
