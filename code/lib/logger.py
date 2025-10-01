#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""program"""
__author__ = "Jamongss"
__date__ = "2023-03-03"
__last_modified_by__ = "Jamongss"
__last_modified_date__ = "2025-10-01"
__maintainer__ = "Jamongss"

###########
# imports #
###########
import os
import sys
import time
import logging
import logging.handlers

# ANSI 컬러 + 굵기
class LogColors(object):
    RESET = "\033[0m"
    COLORS = {
        'DEBUG': "\033[36m",  # 청록
        'INFO': "\033[32m",   # 초록
        'WARNING': "\033[33m",# 노랑
        'ERROR': "\033[31m",  # 빨강
        'CRITICAL': "\033[41m",# 빨강 배경
    }

class ColorFormatter(logging.Formatter):
    def format(self, record):
        msg = logging.Formatter.format(self, record)
        color = LogColors.COLORS.get(record.levelname, "")
        return "{color}{msg}{reset}".format(
            color=color,
            msg=msg,
            reset=LogColors.RESET
        )

def get_timed_rotating_logger(**kwargs):
    """
    Python2/3 호환: TimedRotatingFileHandler + 콘솔 컬러 로그
    kwargs:
        logger_name: str
        log_dir_path: str
        log_file_name: str
        log_level: str ('debug','info','warning','error','critical')
        backup_count: int
    """
    log_dir = kwargs.get('log_dir_path')
    if not os.path.exists(log_dir):
        try:
            os.makedirs(log_dir)
        except Exception:
            time.sleep(1)
            os.makedirs(log_dir)

    logger = logging.getLogger(kwargs.get('logger_name'))

    # 로그 레벨 매핑
    level_str = kwargs.get('log_level', 'debug').lower()
    level_map = {
        'debug': logging.DEBUG,
        'info': logging.INFO,
        'warning': logging.WARNING,
        'error': logging.ERROR,
        'critical': logging.CRITICAL
    }
    log_level = level_map.get(level_str, logging.DEBUG)
    logger.setLevel(log_level)

    # FileHandler
    file_handler = logging.handlers.TimedRotatingFileHandler(
        os.path.join(log_dir, kwargs.get('log_file_name')),
        when='midnight',
        interval=1,
        backupCount=kwargs.get('backup_count', 7)
    )
    file_handler.setLevel(log_level)
    file_formatter = logging.Formatter(
        '%(asctime)s.%(msecs)03d - %(levelname)s[%(lineno)d] - %(message)s',
        '%Y-%m-%d %H:%M:%S'
    )
    file_handler.setFormatter(file_formatter)
    logger.addHandler(file_handler)

    # StreamHandler (컬러 적용)
    stream_handler = logging.StreamHandler(sys.stdout)
    stream_handler.setLevel(logging.DEBUG)
    stream_formatter = ColorFormatter(
        '%(asctime)s.%(msecs)03d - %(levelname)s[%(lineno)d] - %(message)s',
        '%Y-%m-%d %H:%M:%S'
    )
    stream_handler.setFormatter(stream_formatter)
    logger.addHandler(stream_handler)

    return logger


def set_logger(**kwargs):
    log_dir = kwargs.get('log_dir_path')
    if not os.path.exists(log_dir):
        os.makedirs(log_dir)

    logger = logging.getLogger(kwargs.get('logger_name'))

    level_str = kwargs.get('log_level', 'debug').lower()
    level_map = {
        'debug': logging.DEBUG,
        'info': logging.INFO,
        'warning': logging.WARNING,
        'error': logging.ERROR,
        'critical': logging.CRITICAL
    }
    log_level = level_map.get(level_str, logging.DEBUG)
    logger.setLevel(log_level)

    log_file_path = os.path.join(log_dir, kwargs.get('log_file_name'))
    file_handler = logging.FileHandler(log_file_path)
    file_handler.setLevel(log_level)
    formatter = logging.Formatter(
        '%(asctime)s - %(levelname)s[%(lineno)d] - %(message)s',
        '%Y-%m-%d %H:%M:%S'
    )
    file_handler.setFormatter(formatter)
    logger.addHandler(file_handler)

    return logger

