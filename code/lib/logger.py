#!/usr/bin/python
# -*- coding:utf-8 -*-

"""program"""
__author__ = "Maum.Ai"
__date__ = "creation: 2023-03-03, modification: 0000-00-00"

###########
# imports #
###########
import os
import sys
import time
import logging
import logging.handlers


#######
# def #
#######
def get_timed_rotating_logger(**kwargs):
    """
    Get timed rotating logger
    :param      kwargs:         Arguments
    :return:                    Logger
    """
    # create logger
    if not os.path.exists(kwargs.get('log_dir_path')):
        try:
            os.makedirs(kwargs.get('log_dir_path'))
        except Exception:
            time.sleep(1)
            os.makedirs(kwargs.get('log_dir_path'))
            pass
    logger = logging.getLogger(kwargs.get('logger_name'))
    if kwargs.get('log_level').lower() == 'info':
        log_level = 20
    elif kwargs.get('log_level').lower() == 'warning':
        log_level = 30
    elif kwargs.get('log_level').lower() == 'error':
        log_level = 40
    elif kwargs.get('log_level').lower() == 'critical':
        log_level = 50
    else:
        log_level = 10
    logger.setLevel(log_level)
    ch = logging.handlers.TimedRotatingFileHandler(
        os.path.join(kwargs.get('log_dir_path'), kwargs.get('log_file_name')),
        when='midnight',
        interval=1,
        backupCount=kwargs.get('backup_count'),
        encoding=None,
        delay=False,
        utc=False
    )
    ch.setLevel(log_level)
    # Create formatter
    formatter = logging.Formatter(
        fmt='%(asctime)s.%(msecs)03d - %(levelname)s[%(lineno)d] - %(message)s',
        datefmt='%Y-%m-%d %H:%M:%S'
    )
    # Add formatter to ch
    ch.setFormatter(formatter)
    # Add ch to logger
    logger.addHandler(ch)
    st = logging.StreamHandler(sys.stdout)
    st.setFormatter(formatter)
    st.setLevel(logging.DEBUG)
    logger.addHandler(st)
    return logger


def set_logger(**kwargs):
    """
    This is a set logger
    :param      kwargs:         Arguments
    :return:                    Logger
    """
    # create logger
    if not os.path.exists(kwargs.get('log_dir_path')):
        os.makedirs(kwargs.get('log_dir_path'))
    logger = logging.getLogger(kwargs.get('logger_name'))
    if kwargs.get('log_level').lower() == 'info':
        log_level = 20
    elif kwargs.get('log_level').lower() == 'warning':
        log_level = 30
    elif kwargs.get('log_level').lower() == 'error':
        log_level = 40
    elif kwargs.get('log_level').lower() == 'critical':
        log_level = 50
    else:
        log_level = 10
    logger.setLevel(log_level)
    # Create a file handler
    log_file_path = os.path.join(kwargs.get('log_dir_path'), kwargs.get('log_file_name'))
    handler = logging.FileHandler(log_file_path)
    handler.setLevel(log_level)
    # Create a logging format
    formatter = logging.Formatter(
        fmt='%(asctime)s - %(levelname)s[%(lineno)d] - %(message)s', datefmt='%Y-%m-%d %H:%M:%S')
    handler.setFormatter(formatter)
    # Add the handlers to the logger
    logger.addHandler(handler)
    return logger

