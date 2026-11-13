#!/usr/bin/env bash
# ============================================================================
#  桃苏的博客 · 一键启停脚本
#  用法: ./command [start|stop|restart|status|logs|build|preview|install|help]
#  依赖: Node >= 22.23.0 与 pnpm（见 README「环境准备」）
# ============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR" || exit 1

RUN_DIR="$SCRIPT_DIR/.run"
PID_FILE="$RUN_DIR/dev.pid"
LOG_FILE="$RUN_DIR/dev.log"
PREV_LOG_FILE="$RUN_DIR/dev.log.1"
LOCK_DIR="$RUN_DIR/command.lock"
PREVIEW_PID_FILE="$RUN_DIR/preview.pid"

PORT="${PORT:-4321}"
HOST="${HOST:-127.0.0.1}"
START_TIMEOUT="${START_TIMEOUT:-120}"

if [ -t 1 ]; then
	C_RESET=$'\033[0m'; C_RED=$'\033[31m'; C_GREEN=$'\033[32m'
	C_YELLOW=$'\033[33m'; C_BLUE=$'\033[34m'; C_DIM=$'\033[2m'
else
	C_RESET=""; C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""; C_DIM=""
fi

info() { printf '%s\n' "${C_BLUE}ℹ${C_RESET} $*"; }
ok() { printf '%s\n' "${C_GREEN}✅${C_RESET} $*"; }
warn() { printf '%s\n' "${C_YELLOW}⚠${C_RESET} $*"; }
err() { printf '%s\n' "${C_RED}❌${C_RESET} $*" >&2; }
dim() { printf '%s\n' "${C_DIM}$*${C_RESET}"; }

cleanup_lock() { rmdir "$LOCK_DIR" 2>/dev/null || true; }

acquire_lock() {
	mkdir -p "$RUN_DIR"
	if ! mkdir "$LOCK_DIR" 2>/dev/null; then
		err "另一个 command 进程正在运行（锁: .run/command.lock）"
		err "若确认没有其他进程，执行: rmdir .run/command.lock"
		exit 1
	fi
	trap cleanup_lock EXIT INT TERM
}

need_cmd() { command -v "$1" >/dev/null 2>&1; }

version_ge() { # version_ge 22.23.0 22.23.0 -> 0
	[ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n1)" = "$2" ]
}

check_env() {
	if ! need_cmd node; then
		err "未找到 node，请先安装 Node.js 22 LTS（https://nodejs.org）"
		exit 1
	fi
	local node_ver
	node_ver="$(node -v 2>/dev/null | sed 's/^v//')"
	if [ -z "$node_ver" ]; then
		err "无法读取 node 版本"
		exit 1
	fi
	if ! version_ge "$node_ver" "22.23.0"; then
		err "Node 版本过低：当前 v$node_ver，需要 >= 22.23.0"
		err "推荐: nvm install 22 && nvm use 22"
		exit 1
	fi

	if ! need_cmd pnpm; then
		err "未找到 pnpm"
		err "启用方式: corepack enable   或   npm i -g pnpm@11.22.0"
		exit 1
	fi

	local node_major="${node_ver%%.*}"
	if [ "$node_major" -gt 22 ] 2>/dev/null; then
		warn "当前 Node v$node_ver 高于项目验证版本（22 LTS），如遇构建异常请切换: nvm use 22"
	fi
}

ensure_deps() {
	if [ ! -d "$SCRIPT_DIR/node_modules" ] || [ ! -f "$SCRIPT_DIR/node_modules/.modules.yaml" ]; then
		info "首次运行，正在安装依赖（可能需要几分钟）..."
		if ! pnpm install; then
			err "依赖安装失败，请检查网络后重试: ./command install"
			exit 1
		fi
		ok "依赖安装完成"
	fi
}

pid_alive() { [ -n "${1:-}" ] && kill -0 "$1" 2>/dev/null; }

read_pid() {
	if [ -f "$PID_FILE" ]; then
		local pid
		pid="$(cat "$PID_FILE" 2>/dev/null | tr -dc '0-9')"
		if [ -n "$pid" ] && pid_alive "$pid"; then
			printf '%s' "$pid"
			return 0
		fi
	fi
	return 1
}

port_pids() { lsof -ti "tcp:$PORT" -sTCP:LISTEN 2>/dev/null || true; }

http_code() { curl -s -o /dev/null -w '%{http_code}' --max-time 3 "$1" 2>/dev/null || true; }

open_browser() {
	local url="$1"
	case "$(uname -s)" in
	Darwin) open "$url" >/dev/null 2>&1 || true ;;
	Linux) need_cmd xdg-open && xdg-open "$url" >/dev/null 2>&1 || true ;;
	esac
}

kill_tree() { # 先子后父，TERM 后再 KILL
	local pid="$1"
	pkill -TERM -P "$pid" 2>/dev/null || true
	kill -TERM "$pid" 2>/dev/null || true
	for _ in 1 2 3 4 5 6; do
		pid_alive "$pid" || break
		sleep 0.5
	done
	pkill -KILL -P "$pid" 2>/dev/null || true
	kill -KILL "$pid" 2>/dev/null || true
}

wait_http() { # wait_http <url> <seconds>
	local url="$1" limit="$2" i=0 code
	while [ "$i" -lt "$limit" ]; do
		code="$(http_code "$url")"
		if [ "$code" = "200" ] || [ "$code" = "301" ] || [ "$code" = "302" ]; then
			printf '%s' "$code"
			return 0
		fi
		sleep 1
		i=$((i + 1))
	done
	printf '%s' "${code:-000}"
	return 1
}

tail_log() { # tail_log <file> <lines>
	[ -f "$1" ] && tail -n "${2:-30}" "$1" || true
}

# ---------------------------------------------------------------- start -----
cmd_start() {
	acquire_lock
	check_env

	local running
	if running="$(read_pid)"; then
		local url="http://${HOST}:${PORT}/"
		ok "开发服务器已在运行（PID $running）: $url"
		dim "如需重启: ./command restart    查看日志: ./command logs"
		open_browser "$url"
		return 0
	fi

	local busy
	busy="$(port_pids)"
	if [ -n "$busy" ]; then
		err "端口 $PORT 已被其他进程占用（PID: $(echo "$busy" | tr '\n' ' '))"
		err "释放端口: lsof -ti tcp:$PORT | xargs kill -9"
		err "或换端口: PORT=4322 ./command start"
		return 1
	fi

	ensure_deps

	mkdir -p "$RUN_DIR"
	if [ -f "$LOG_FILE" ]; then mv -f "$LOG_FILE" "$PREV_LOG_FILE"; fi

	info "启动开发服务器（端口 $PORT）..."
	nohup pnpm dev --port "$PORT" --host "$HOST" >"$LOG_FILE" 2>&1 &
	local pid=$!
	echo "$pid" >"$PID_FILE"

	local code
	if ! code="$(wait_http "http://${HOST}:${PORT}/" "$START_TIMEOUT")"; then
		err "启动失败（${START_TIMEOUT}s 内未响应，最后状态码: $code）"
		echo "$C_DIM--- 日志末尾 ---$C_RESET"
		tail_log "$LOG_FILE" 30
		kill_tree "$pid"
		rm -f "$PID_FILE"
		return 1
	fi

	ok "已启动: http://${HOST}:${PORT}/（PID $pid，日志 .run/dev.log）"
	dim "停止: ./command stop    状态: ./command status    日志: ./command logs -f"
	open_browser "http://${HOST}:${PORT}/"
}

# ----------------------------------------------------------------- stop -----
cmd_stop() {
	acquire_lock
	local pid found=0

	if pid="$(read_pid)"; then
		info "正在停止开发服务器（PID $pid）..."
		kill_tree "$pid"
		found=1
	fi

	# 兜底：按端口清理残留（astro / node 子进程）
	local busy
	busy="$(port_pids)"
	if [ -n "$busy" ]; then
		info "清理端口 $PORT 上的残留进程: $(echo "$busy" | tr '\n' ' ')"
		for p in $busy; do kill -TERM "$p" 2>/dev/null || true; done
		sleep 1
		busy="$(port_pids)"
		for p in $busy; do kill -KILL "$p" 2>/dev/null || true; done
		found=1
	fi

	rm -f "$PID_FILE" "$PREVIEW_PID_FILE"

	if [ -n "$(port_pids)" ]; then
		err "端口 $PORT 仍被占用，请手动检查: lsof -i tcp:$PORT"
		return 1
	fi

	if [ "$found" -eq 1 ]; then
		ok "已停止，端口 $PORT 已释放"
	else
		warn "没有检测到运行中的开发服务器"
	fi
}

# --------------------------------------------------------------- status -----
cmd_status() {
	local pid url code
	url="http://${HOST}:${PORT}/"
	if pid="$(read_pid)"; then
		code="$(http_code "$url")"
		if [ "$code" = "200" ]; then
			ok "运行中（PID $pid，HTTP $code）: $url"
		else
			warn "进程存活（PID $pid）但 HTTP 响应异常: ${code:-000}"
			dim "排查: ./command logs"
		fi
		return 0
	fi

	local busy
	busy="$(port_pids)"
	if [ -n "$busy" ]; then
		warn "未运行本脚本启动的服务，但端口 $PORT 被占用（PID: $(echo "$busy" | tr '\n' ' ')）"
		return 1
	fi
	warn "未运行"
	dim "启动: ./command start"
	return 1
}

# ----------------------------------------------------------------- logs -----
cmd_logs() {
	local follow=0
	[ "${1:-}" = "-f" ] && follow=1
	if [ ! -f "$LOG_FILE" ]; then
		warn "暂无日志（.run/dev.log 不存在），先执行: ./command start"
		return 1
	fi
	if [ "$follow" -eq 1 ]; then
		info "实时跟随 .run/dev.log（Ctrl+C 退出）"
		tail -f "$LOG_FILE"
	else
		tail -n 100 "$LOG_FILE"
	fi
}

# ---------------------------------------------------------------- build -----
human_size() { du -sh "$1" 2>/dev/null | awk '{print $1}'; }

cmd_build() {
	check_env
	info "开始构建（Cloudflare Pages 使用相同命令）..."
	local start_ts end_ts code
	start_ts="$(date +%s)"
	pnpm build
	code=$?
	end_ts="$(date +%s)"
	if [ "$code" -ne 0 ]; then
		err "构建失败（退出码 $code），耗时 $((end_ts - start_ts))s"
		return "$code"
	fi
	if [ ! -d "$SCRIPT_DIR/dist" ]; then
		err "构建命令成功但未找到 dist/ 目录"
		return 1
	fi
	ok "构建完成，耗时 $((end_ts - start_ts))s，dist 体积 $(human_size "$SCRIPT_DIR/dist")"
	dim "本地预览: ./command preview"
}

# -------------------------------------------------------------- preview -----
cmd_preview() {
	acquire_lock
	check_env
	local keep=0
	[ "${1:-}" = "--no-build" ] && keep=1
	if [ "$keep" -eq 0 ] || [ ! -d "$SCRIPT_DIR/dist" ]; then
		cmd_build || return 1
	fi

	local busy
	busy="$(port_pids)"
	if [ -n "$busy" ]; then
		err "端口 $PORT 已被占用（PID: $(echo "$busy" | tr '\n' ' ')），先执行 ./command stop"
		return 1
	fi

	info "启动预览服务器（端口 $PORT）..."
	nohup pnpm preview --port "$PORT" --host "$HOST" >"$LOG_FILE" 2>&1 &
	local pid=$!
	echo "$pid" >"$PREVIEW_PID_FILE"
	echo "$pid" >"$PID_FILE"

	if ! wait_http "http://${HOST}:${PORT}/" "$START_TIMEOUT" >/dev/null; then
		err "预览启动失败，日志末尾:"
		tail_log "$LOG_FILE" 30
		kill_tree "$pid"
		rm -f "$PID_FILE" "$PREVIEW_PID_FILE"
		return 1
	fi
	ok "预览已启动: http://${HOST}:${PORT}/（PID $pid）"
	dim "停止: ./command stop"
	open_browser "http://${HOST}:${PORT}/"
}

# -------------------------------------------------------------- install -----
cmd_install() {
	check_env
	info "重新安装依赖（pnpm install --force）..."
	if pnpm install --force; then
		ok "依赖重装完成"
	else
		err "依赖安装失败"
		return 1
	fi
}

# ----------------------------------------------------------------- help -----
cmd_help() {
	cat <<'EOF'
桃苏的博客 · 一键启停脚本

用法:
  ./command start            启动本地开发服务器（默认，4321 端口）并在浏览器打开
  ./command stop             停止开发服务器并释放端口
  ./command restart          重启
  ./command status           查看运行状态（进程 + HTTP）
  ./command logs [-f]        查看日志，-f 实时跟随
  ./command build            生产构建（与 Cloudflare Pages 相同命令）
  ./command preview [--no-build]
                             构建并本地预览 dist（--no-build 复用已有产物）
  ./command install          强制重装依赖
  ./command help             显示本帮助

可配置环境变量:
  PORT=4321                  开发/预览端口
  HOST=127.0.0.1             监听地址（局域网访问可设 0.0.0.0）
  START_TIMEOUT=120          启动健康检查超时（秒，首次启动含字体下载较慢）

运行时文件（已 git 忽略）:
  .run/dev.pid               当前服务进程号
  .run/dev.log               本次日志（上次为 .run/dev.log.1）

示例:
  ./command start
  PORT=4322 ./command start
  ./command logs -f
  ./command stop
EOF
}

# --------------------------------------------------------------- router -----
main() {
	local sub="${1:-start}"
	case "$sub" in
	start | up | dev) cmd_start ;;
	stop | down) cmd_stop ;;
	restart)
		cmd_stop
		cleanup_lock
		cmd_start
		;;
	status) cmd_status ;;
	logs | log) shift; cmd_logs "${1:-}" ;;
	build) cmd_build ;;
	preview) shift; cmd_preview "${1:-}" ;;
	install | i) cmd_install ;;
	help | -h | --help) cmd_help ;;
	*)
		err "未知命令: $sub"
		echo
		cmd_help
		exit 1
		;;
	esac
}

main "$@"
