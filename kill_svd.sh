#!/bin/bash 
# 현재 디렉토리 기준으로 svd 실행 중인 python 프로세스 종료 

set -e  # 오류 발생시 스크립트 중단

# 함수 정의
log_info() {
    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_warn() {
    echo "[WARN] $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# 설정
PWD="$(pwd)" 
SVD_PATH="$(pwd)/svd" 
SUPERVISORCTL_TIMEOUT=10
SIGTERM_TIMEOUT=5

log_info "Starting shutdown process for: $SVD_PATH"

# 1단계: supervisorctl을 통한 정상 종료
graceful_shutdown() {
    if ! command -v supervisorctl &> /dev/null; then
        log_warn "supervisorctl command not found"
        return 1
    fi
    
    # supervisord 설정 파일 확인 (있는 경우)
    local config_file=""
    if [ -f "$PWD/cfg/replace_supervisord.conf" ]; then
        config_file="-c $PWD/cfg/replace_supervisord.conf"
    fi
    
    # supervisord 상태 확인
    if ! supervisorctl $config_file status &> /dev/null; then
        log_warn "Supervisord is not responding"
        return 1
    fi
    
    log_info "Stopping all supervised processes..."
    if supervisorctl $config_file stop all; then
        sleep 2
        
        log_info "Shutting down supervisord..."
        if supervisorctl $config_file shutdown; then
            # 정상 종료 대기
            for i in $(seq 1 $SUPERVISORCTL_TIMEOUT); do
                if ! ps -u $(whoami) -f | grep "python $SVD_PATH" | grep -v grep &> /dev/null; then
                    log_info "Graceful shutdown completed"
                    return 0
                fi
                log_info "Waiting for shutdown... ($i/$SUPERVISORCTL_TIMEOUT)"
                sleep 1
            done
            log_warn "Graceful shutdown timeout"
            return 1
        else
            log_warn "Supervisorctl shutdown failed"
            return 1
        fi
    else
        log_warn "Failed to stop supervised processes"
        return 1
    fi
}

# 2단계: 수동 프로세스 종료
manual_termination() {
    local pids=$(ps -u $(whoami) -f | grep "python $SVD_PATH" | grep -v grep | awk '{print $2}')
    
    if [ -z "$pids" ]; then 
        log_info "No python svd processes found"
        return 0
    fi 
    
    log_info "Found python svd processes. PIDs: $pids"
    
    # SIGTERM 시도
    log_info "Sending SIGTERM..."
    if kill $pids 2>/dev/null; then
        # SIGTERM 대기
        for i in $(seq 1 $SIGTERM_TIMEOUT); do
            local remaining=$(ps -u $(whoami) -f | grep "python $SVD_PATH" | grep -v grep | awk '{print $2}')
            if [ -z "$remaining" ]; then
                log_info "Processes terminated gracefully"
                return 0
            fi
            sleep 1
        done
        
        # SIGKILL 시도
        local remaining=$(ps -u $(whoami) -f | grep "python $SVD_PATH" | grep -v grep | awk '{print $2}')
        if [ -n "$remaining" ]; then
            log_warn "Force killing remaining processes: $remaining"
            if kill -9 $remaining 2>/dev/null; then
                sleep 2
                # 최종 확인
                local final_check=$(ps -u $(whoami) -f | grep "python $SVD_PATH" | grep -v grep | awk '{print $2}')
                if [ -n "$final_check" ]; then
                    log_error "Failed to terminate processes: $final_check"
                    return 1
                fi
            fi
        fi
    else
        log_error "Failed to send SIGTERM"
        return 1
    fi
    
    log_info "Manual termination completed"
    return 0
}

# 3단계: 정리 작업
cleanup() {
    log_info "Performing cleanup..."
    
    # 설정 파일 제거
    if [ -f "$PWD/cfg/replace_supervisord.conf" ]; then
        rm -f "$PWD/cfg/replace_supervisord.conf"
        log_info "Removed replace_supervisord.conf"
    fi
    
    # PID 파일 제거
    for pid_file in "/tmp/supervisord.pid" "$PWD/supervisord.pid"; do
        if [ -f "$pid_file" ]; then
            rm -f "$pid_file"
            log_info "Removed $(basename $pid_file)"
        fi
    done
    
    # 소켓 파일 제거
    for sock_file in "/tmp/supervisor.sock" "$PWD/supervisor.sock"; do
        if [ -S "$sock_file" ]; then
            rm -f "$sock_file"
            log_info "Removed $(basename $sock_file)"
        fi
    done
}

# 메인 실행
main() {
    if graceful_shutdown; then
        log_info "Graceful shutdown successful"
    elif manual_termination; then
        log_info "Manual termination successful"
    else
        log_error "Failed to terminate processes"
        exit 1
    fi
    
    cleanup
    log_info "Shutdown process completed successfully"
}

# 인터럽트 시 정리 작업
trap cleanup EXIT

# 실행
main

