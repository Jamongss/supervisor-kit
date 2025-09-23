#!/bin/bash
# 현재 디렉토리 기준으로 svd 실행 중인 python 프로세스 종료

# svd 실행 경로
PWD="$(pwd)"
SVD_PATH="$(pwd)/svd"

# 확인: 현재 경로와 svd 실행 경로
echo "[INFO] Looking for python processes running: $SVD_PATH"

# 해당 경로로 실행된 python 프로세스 PID 확인
PIDS=$(ps -u $(whoami) -f | grep "python $SVD_PATH" | grep -v grep | awk '{print $2}')

if [ -z "$PIDS" ]; then
    echo "[INFO] No python svd process found."
else
    echo "[INFO] Killing PIDs: $PIDS"
    kill $PIDS
    # 강제 종료가 필요하면 아래 사용
    # kill -9 $PIDS
    rm $PWD/cfg/replace_supervisord.conf
fi
