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

# Git Stash 스크립트

set -e  # 오류 발생시 스크립트 중단

# =============================================================================
# 로그 시스템 설정
# =============================================================================

# 로그 설정 (환경변수로 오버라이드 가능)
LOG_DIR="${LOG_DIR:-$PWD/logs/git_stash}"
LOG_FILE="${LOG_FILE:-$LOG_DIR/git_stash.log.$(date '+%Y%m%d')}"
LOG_LEVEL="${LOG_LEVEL:-INFO}"  # DEBUG, INFO, WARN, ERROR, CRITICAL
LOG_TO_FILE="${LOG_TO_FILE:-true}"
LOG_TO_CONSOLE="${LOG_TO_CONSOLE:-true}"
MAX_LOG_FILES="${MAX_LOG_FILES:-7}"  # 보관할 로그 파일 수

# 로그 디렉토리 생성
mkdir -p "$LOG_DIR"

# 로그 로테이션 (이전 로그 파일 정리)
cleanup_old_logs() {
    find "$LOG_DIR" -name "git_stash_*.log" -mtime +$MAX_LOG_FILES -delete 2>/dev/null || true
}

# 로그 레벨 숫자 매핑
declare -A LOG_LEVELS=([DEBUG]=0 [INFO]=1 [WARN]=2 [ERROR]=3 [CRITICAL]=4)

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
            CRITICAL) echo -e "\033[1;41;97m$log_entry\033[0m" ;; # 흰 글자 + 빨간 배경 + 굵게
	    ERROR)    echo -e "\033[1;31m$log_entry\033[0m" ;;    # 굵은 빨간색
	    WARN)     echo -e "\033[1;33m$log_entry\033[0m" ;;    # 굵은 노란색
	    INFO)     echo -e "\033[1;32m$log_entry\033[0m" ;;    # 굵은 초록색
            DEBUG)    echo -e "\033[36m$log_entry\033[0m" ;;      # 청록색
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
log_critical() { log_message "CRITICAL" "$1"; }

# 스크립트 시작 로그 및 환경 정보
init_logging() {
    cleanup_old_logs

    if [ "$LOG_TO_FILE" = "true" ]; then
        echo "===================================================================================" >> "$LOG_FILE"
        echo "=== Git Stash Script Started at $(date) ===" >> "$LOG_FILE"
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

# Git 저장소 확인
check_git_repo() {
    log_info "[Check] Checking if current directory is a git repository..."

    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        log_error "[Check] Current directory is not a git repository"
        return 1
    fi

    log_info "[Check] Git repository confirmed"
    return 0
}

# Git 상태 확인
check_git_status() {
    log_info "[Status] Checking git status..."

    # 변경사항 확인
    if git diff-index --quiet HEAD -- 2>/dev/null; then
        log_warn "[Status] No changes to stash (working directory is clean)"
        return 1
    fi

    log_info "[Status] Changes detected in working directory"

    # 변경 내역 로그
    log_info "[Status] Current git status:"
    {
        echo "============================== git status =============================="
        git status --short
        echo "========================================================================"
    } | tee -a "$LOG_FILE"

    return 0
}

# Git stash 실행
perform_stash() {
    local stash_message="$1"

    if [ -z "$stash_message" ]; then
        stash_message="Auto-stash at $(date '+%Y-%m-%d %H:%M:%S')"
    fi

    log_info "[Stash] Stashing changes with message: $stash_message"

    # stash 실행 (untracked files 포함)
    if git stash push -u -m "$stash_message" 2>&1 | tee -a "$LOG_FILE"; then
        log_info "[Stash] Changes stashed successfully"

        # stash 목록 확인
        log_info "[Stash] Current stash list:"
        {
            echo "============================== git stash list =============================="
            git stash list
            echo "============================================================================"
        } | tee -a "$LOG_FILE"

        return 0
    else
        log_error "[Stash] Failed to stash changes"
        return 1
    fi
}

# Stash 목록 표시
show_stash_list() {
    log_info "[List] Current stash entries:"

    if ! git stash list | grep -q .; then
        log_info "[List] No stash entries found"
        return 0
    fi

    {
        echo "============================== git stash list =============================="
        git stash list
        echo "============================================================================"
    } | tee -a "$LOG_FILE"

    return 0
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

# 사용법 출력
print_usage() {
    cat << EOF
Usage: $0 [OPTIONS] [MESSAGE]

Git stash wrapper script with logging

OPTIONS:
    -h, --help      Show this help message
    -l, --list      Show stash list only (no stashing)
    -m, --message   Stash message (can also be provided as argument)

EXAMPLES:
    $0                              # Stash with auto-generated message
    $0 "Work in progress"           # Stash with custom message
    $0 -m "Feature development"     # Stash with custom message using flag
    $0 -l                           # Show stash list only

ENVIRONMENT VARIABLES:
    LOG_LEVEL       Set log level (DEBUG, INFO, WARN, ERROR, CRITICAL)
    LOG_TO_FILE     Enable/disable file logging (true/false)
    LOG_TO_CONSOLE  Enable/disable console logging (true/false)

EOF
}

# 메인 실행 함수
main() {
    local stash_message=""
    local list_only=false

    # 인자 파싱
    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help)
                print_usage
                exit 0
                ;;
            -l|--list)
                list_only=true
                shift
                ;;
            -m|--message)
                shift
                stash_message="$1"
                shift
                ;;
            *)
                # 메시지로 취급
                stash_message="$1"
                shift
                ;;
        esac
    done

    log_info "[Main] Starting git stash process"

    # Git 저장소 확인
    if ! check_git_repo; then
        return 1
    fi

    # 리스트만 표시하는 경우
    if [ "$list_only" = true ]; then
        show_stash_list
        return 0
    fi

    # Git 상태 확인
    if ! check_git_status; then
        log_info "[Main] Nothing to stash"
        show_stash_list
        return 0
    fi

    # Stash 실행
    if perform_stash "$stash_message"; then
        log_info "[Main] Git stash completed successfully"
        return 0
    else
        log_error "[Main] Git stash failed"
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
log_info "[Init] Git Stash Script v1.0"
log_info "[Init] Current user: $(whoami)"
log_info "[Init] Current directory: $(pwd)"

# 메인 로직 실행
if main "$@"; then
    log_info "[Main] Script execution completed successfully"
    exit 0
else
    log_error "[Main] Script execution failed"
    exit 1
fi
