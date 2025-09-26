#!/bin/sh

# 이미 재실행되었는지 체크하는 마커
if [ -z "${_REEXEC_DONE:-}" ]; then
    # 현재 실행 중인 쉘 이름(ps 기반)
    CURRENT_SHELL=$(ps -p $$ -o comm= | sed 's/^-*//')  # 접두사 제거

    # 사용자의 로그인 쉘 이름
    TARGET_SHELL=$(basename "$SHELL")

    # 같지 않으면 재실행
    if [ "$CURRENT_SHELL" != "$TARGET_SHELL" ]; then
        export _REEXEC_DONE=1
        echo "Re-executing script with $TARGET_SHELL..."
        exec "$SHELL" "$0" "$@"
        # exec 성공하면 아래로 오지 않음
    fi
fi

# 현재 디렉토리 기준으로 svd 실행 중인 python 프로세스 종료

set -e  # 오류 발생시 스크립트 중단

# =============================================================================
# 로그 시스템 설정
# =============================================================================

# 로그 설정 (환경변수로 오버라이드 가능)
LOG_DIR="${LOG_DIR:-$PWD/logs/shutdown}"
LOG_FILE="${LOG_FILE:-$LOG_DIR/shutdown.log.$(date '+%Y%m%d')}"
LOG_LEVEL="${LOG_LEVEL:-INFO}"  # DEBUG, INFO, WARN, ERROR
LOG_TO_FILE="${LOG_TO_FILE:-true}"
LOG_TO_CONSOLE="${LOG_TO_CONSOLE:-true}"
MAX_LOG_FILES="${MAX_LOG_FILES:-7}"  # 보관할 로그 파일 수

# 로그 디렉토리 생성
mkdir -p "$LOG_DIR"

# 로그 로테이션 (이전 로그 파일 정리)
cleanup_old_logs() {
    find "$LOG_DIR" -name "shutdown_*.log" -mtime +$MAX_LOG_FILES -delete 2>/dev/null || true
}

# 로그 레벨 숫자 매핑
declare -A LOG_LEVELS=([DEBUG]=0 [INFO]=1 [WARN]=2 [ERROR]=3)

# 로그 메시지 출력 함수
log_message() {
    local level="$1"
    local message="$2"
    local current_level_num=${LOG_LEVELS[$LOG_LEVEL]}
    local message_level_num=${LOG_LEVELS[$level]}

    # 로그 레벨 체크 (설정된 레벨보다 낮으면 출력 안함)
    if [ ${message_level_num:-1} -lt ${current_level_num:-1} ]; then
        return 0
    fi

    local timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    local pid="$$"
    local log_entry="[$level] $timestamp [PID:$pid] - $message"

    # 콘솔 출력 (색상 적용)
    if [ "$LOG_TO_CONSOLE" = "true" ]; then
        case $level in
            ERROR) echo -e "\033[31m$log_entry\033[0m" ;;  # 빨간색
            WARN)  echo -e "\033[33m$log_entry\033[0m" ;;  # 노란색
            INFO)  echo -e "\033[32m$log_entry\033[0m" ;;  # 초록색
            DEBUG) echo -e "\033[36m$log_entry\033[0m" ;;  # 청록색
        esac
    fi

    # 파일 저장
    if [ "$LOG_TO_FILE" = "true" ]; then
        echo "$log_entry" >> "$LOG_FILE"
    fi
}

# 로그 레벨별 함수들
log_debug() { log_message "DEBUG" "$1"; }
log_info() { log_message "INFO" "$1"; }
log_warn() { log_message "WARN" "$1"; }
log_error() { log_message "ERROR" "$1"; }

# 스크립트 시작 로그 및 환경 정보
init_logging() {
    cleanup_old_logs

    if [ "$LOG_TO_FILE" = "true" ]; then
        echo "===================================================================================" >> "$LOG_FILE"
        echo "=== SVD Shutdown Script Started at $(date) ===" >> "$LOG_FILE"
        echo "=== Script: $0" >> "$LOG_FILE"
        echo "=== User: $(whoami)" >> "$LOG_FILE"
        echo "=== PID: $$" >> "$LOG_FILE"
        echo "=== Working Directory: $(pwd)" >> "$LOG_FILE"
        echo "=== Log Level: $LOG_LEVEL" >> "$LOG_FILE"
        echo "===================================================================================" >> "$LOG_FILE"
    fi

    log_info "[Init] SHELL: $SHELL"
    log_info "[Init] Logging initialized - File: $LOG_FILE, Level: $LOG_LEVEL"
    log_debug "[Init] Environment: USER=$(whoami), PWD=$(pwd), SHELL=$SHELL"
}

# =============================================================================
# 메인 애플리케이션 로직
# =============================================================================

# 설정 변수
PWD="$(pwd)"
SVD_PATH="$(pwd)/svd"
SUPERVISORCTL_TIMEOUT=10
SIGTERM_TIMEOUT=5

# 1단계: supervisorctl을 통한 정상 종료
graceful_shutdown() {
    log_info "[Graceful_Shutdown] Attempting graceful shutdown via supervisorctl ..."

    if ! command -v $PWD/svctl &> /dev/null; then
        log_warn "[Graceful_Shutdown] supervisorctl command not found ..."
        return 1
    fi

    log_debug "[Graceful_Shutdown] supervisorctl command found"

    # supervisord 상태 확인
    # if ! $PWD/svctl status &> /dev/null; then
    if ! $PWD/svctl status; then
        log_warn "[Graceful_Shutdown] Supervisord is not responding to status command"
        return 1
    fi

    log_info "[Graceful_Shutdown] Supervisord is responding. Stopping all supervised processes..."
    if $PWD/svctl stop all 2>/dev/null; then
        log_info "[Graceful_Shutdown] All supervised processes stop command sent"
        sleep 2

        log_info "[Graceful_Shutdown] Sending shutdown command to supervisord..."
        if $PWD/svctl shutdown 2>/dev/null; then
            log_info "[Graceful_Shutdown] Shutdown command sent successfully"

            # 정상 종료 완료 대기
            for i in $(seq 1 $SUPERVISORCTL_TIMEOUT); do
                if ! ps -u $(whoami) -f | grep "python $SVD_PATH" | grep -v grep &> /dev/null; then
                    log_info "[Graceful_Shutdown] Graceful shutdown completed successfully"
                    return 0
                fi
                log_debug "[Graceful_Shutdown] Waiting for shutdown... ($i/$SUPERVISORCTL_TIMEOUT)"
                sleep 1
            done

            log_warn "[Graceful_Shutdown] Graceful shutdown timeout after ${SUPERVISORCTL_TIMEOUT}s"
            return 1
        else
            log_warn "[Graceful_Shutdown] Supervisorctl shutdown command failed"
            return 1
        fi
    else
        log_warn "[Graceful_Shutdown] Failed to stop supervised processes"
        return 1
    fi
}

# 2단계: 수동 프로세스 종료
manual_termination() {
    log_info "[Manual_Termination] Attempting manual process termination"

    local pids=$(ps -u $(whoami) -f | grep "python $SVD_PATH" | grep -v grep | awk '{print $2}')

    if [ -z "$pids" ]; then
        log_info "[Manual_Termination] No python svd processes found"
        return 0
    fi

    log_info "[Manual_Termination] Found python svd processes. PIDs: $pids"
    log_debug "[Manual_Termination] Process details:"
    ps -u $(whoami) -f | grep "python $SVD_PATH" | grep -v grep | while read line; do
        log_debug "[Manual_Termination]  $line"
    done

    # SIGTERM 시도
    log_info "[Manual_Termination] Sending SIGTERM to processes: $pids"
    if kill $pids 2>/dev/null; then
        log_debug "[Manual_Termination] SIGTERM sent successfully"

        # SIGTERM 대기
        for i in $(seq 1 $SIGTERM_TIMEOUT); do
            local remaining=$(ps -u $(whoami) -f | grep "python $SVD_PATH" | grep -v grep | awk '{print $2}')
            if [ -z "$remaining" ]; then
                log_info "[Manual_Termination] All processes terminated gracefully with SIGTERM"
                return 0
            fi
            log_debug "[Manual_Termination] Waiting for SIGTERM termination... ($i/$SIGTERM_TIMEOUT)"
            sleep 1
        done

        # SIGKILL 시도
        local remaining=$(ps -u $(whoami) -f | grep "python $SVD_PATH" | grep -v grep | awk '{print $2}')
        if [ -n "$remaining" ]; then
            log_warn "[Manual_Termination] SIGTERM timeout. Force killing remaining processes: $remaining"
            if kill -9 $remaining 2>/dev/null; then
                log_info "[Manual_Termination] SIGKILL sent to remaining processes"
                sleep 2

                # 최종 확인
                local final_check=$(ps -u $(whoami) -f | grep "python $SVD_PATH" | grep -v grep | awk '{print $2}')
                if [ -n "$final_check" ]; then
                    log_error "[Manual_Termination] Failed to terminate all processes even with SIGKILL: $final_check"
                    return 1
                else
                    log_info "[Manual_Termination] All processes forcefully terminated"
                fi
            else
                log_error "[Manual_Termination] Failed to send SIGKILL"
                return 1
            fi
        fi
    else
        log_error "[Manual_Termination] Failed to send SIGTERM to processes"
        return 1
    fi

    log_info "[Manual_Termination] Manual termination completed successfully"
    return 0
}

# 3단계: 정리 작업
cleanup() {
    log_info "[CleanUp] Performing cleanup operations"

    local cleaned_files=0

    # 설정 파일 제거
    local conf_file="$PWD/cfg/replace_supervisord.conf"
    if [ -f "$conf_file" ]; then
        if rm -f "$conf_file" 2>/dev/null; then
            log_info "[CleanUp] Removed replace_supervisord.conf"
            ((cleaned_files++))
        else
            log_warn "[CleanUp] Failed to remove replace_supervisord.conf"
        fi
    else
        log_debug "[CleanUp] replace_supervisord.conf not found"
    fi

    # PID 파일들 제거
    for pid_file in "$PWD/run/supervisord.pid"; do
        if [ -f "$pid_file" ]; then
            if rm -f "$pid_file" 2>/dev/null; then
                log_info "[CleanUp] Removed PID file: $(basename $pid_file)"
                ((cleaned_files++))
            else
                log_warn "[CleanUp] Failed to remove PID file: $pid_file"
            fi
        else
            log_debug "[CleanUp] PID file not found: $pid_file"
        fi
    done

    # 소켓 파일들 제거
    for sock_file in "$PWD/run/supervisor.sock"; do
        if [ -S "$sock_file" ]; then
            if rm -f "$sock_file" 2>/dev/null; then
                log_info "[CleanUp] Removed socket file: $(basename $sock_file)"
                ((cleaned_files++))
            else
                log_warn "[CleanUp] Failed to remove socket file: $sock_file"
            fi
        else
            log_debug "[CleanUp] Socket file not found: $sock_file"
        fi
    done

    log_info "[CleanUp] Cleanup completed: $cleaned_files files removed"
}

# 종료 시 정리 작업 (시그널 핸들러)
cleanup_on_exit() {
    local exit_code=$?
    log_debug "[CleanUp] Script exiting with code: $exit_code"

    if [ "$LOG_TO_FILE" = "true" ]; then
        echo "=== Script ended at $(date) with exit code: $exit_code ===" >> "$LOG_FILE"
        echo "" >> "$LOG_FILE"
    fi
}

# 메인 실행 함수
main() {
    log_info "[Main] Starting shutdown process for: $SVD_PATH"

    local shutdown_method=""
    local success=false

    # 우선순위 순서로 종료 시도
    if graceful_shutdown; then
        shutdown_method="graceful (supervisorctl)"
        success=true
    elif manual_termination; then
        shutdown_method="manual (signal)"
        success=true
    else
        log_error "[Main] All shutdown methods failed"
        return 1
    fi

    if $success; then
        log_info "[Main] Shutdown successful using: $shutdown_method"
        cleanup
        log_info "[Main] All operations completed successfully"
        return 0
    else
        log_error "[Main] Shutdown process failed"
        return 1
    fi
}

# =============================================================================
# 스크립트 실행
# =============================================================================

# 시그널 핸들러 설정
trap cleanup_on_exit EXIT

# 로그 시스템 초기화
init_logging

# 시작 환경 정보 로깅
log_info "[Init] SVD Shutdown Script v2.0"
log_info "[Init] Current user: $(whoami)"
log_info "[Init] Current directory: $PWD"
log_info "[Init] Target SVD path: $SVD_PATH"
log_info "[Init] Timeout settings - Supervisorctl: ${SUPERVISORCTL_TIMEOUT}s, SIGTERM: ${SIGTERM_TIMEOUT}s"

# 메인 로직 실행
if main; then
    log_info "[Main] Script execution completed successfully"
    exit 0
else
    log_error "[Main] Script execution failed"
    exit 1
fi

