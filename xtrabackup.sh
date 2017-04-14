#!/bin/bash
 
## 备份计划任务
## 
## 每天凌晨1:30一次全量备份
## 每天间隔1小时一次增量备份
## 30 1 * * * backup.sh full
## 00 * * * * backup.sh inc
##
##  恢复数据步骤：
##  (1)、查看备份日志，找到全量备份和增量备份的关系（注意增量备份的顺序）
##
##  cat ${BACKUP_BASE_DIR}/${INC_BASE_LIST}
##  (2)、全量备份
##  innobackupex --defaults-file=/etc/my.cnf --apply-log --redo-only ${BACKUP_BASE_DIR}/full_dir
##
##  (3)、第一个增量
##  innobackupex --defaults-file=/etc/my.cnf --apply-log --redo-only ${BACKUP_BASE_DIR}/full_dir \
##  --incremental-dir=${BACKUP_BASE_DIR}/one_inc_dir
##
##  (4)、第二个增量
##  innobackupex --defaults-file=/etc/my.cnf --apply-log --redo-only ${BACKUP_BASE_DIR}/full_dir \
##  --incremental-dir=${BACKUP_BASE_DIR}/two_inc_dir
##
##  (5)、恢复数据
##  innobackupex --defaults-file=/etc/my.cnf --copy-back ${BACKUP_BASE_DIR}/full_dir
 
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin
 
BACKUP_BASE_DIR="/backup/xtrabackup"
INC_BASE_LIST="${BACKUP_BASE_DIR}/inc_list.txt"
XTRABACKUP_PATH="/usr/local/xtrabackup/bin/innobackupex"
 
MYSQL_CNF="/etc/my.cnf"
MYSQL_HOSTNAME=127.0.0.1
MYSQL_USERNAME=root
MYSQL_PASSWORD=w7tQ5NNWWRk
 
LOCK_FILE=/tmp/innobackupex.lock
THREAD=3
 
mkdir -p ${BACKUP_BASE_DIR}
CURRENT_BACKUP_PATH="${BACKUP_BASE_DIR}/$(date +%F_%H-%M)"
[[ -d ${CURRENT_BACKUP_PATH} ]] && CURRENT_BACKUP_PATH="${BACKUP_BASE_DIR}/$(date +%F_%H-%M-%S)"
 
print_help(){
    echo "--------------------------------------------------------------"
    echo "Usage: $0 full | inc | help                                   "
    echo "--------------------------------------------------------------"
    exit 1
}
 
[[ $# -lt 1 ]] && print_help
 
[[ "$1" == "help" ]] && print_help
 
[[ -f "$LOCK_FILE" ]] && echo -e "Usage: rm -f $LOCK_FILE\nUsage: chattr -i $LOCK_FILE && rm -f $LOCK_FILE" && exit 1
 
FullBackup(){
    touch $LOCK_FILE
    chattr +i $LOCK_FILE
    local rc=0
    ${XTRABACKUP_PATH} \
    --defaults-file=${MYSQL_CNF} \
    --user=${MYSQL_USERNAME} \
    --password=${MYSQL_PASSWORD} \
    --host=${MYSQL_HOSTNAME} \
    --parallel=${THREAD} \
    --no-timestamp ${CURRENT_BACKUP_PATH} > ${CURRENT_BACKUP_PATH}_full.log 2>&1
    grep ".*\ completed\ OK\!" ${CURRENT_BACKUP_PATH}_full.log > /dev/null 2>&1
    if [ $? -ne 0 ];then
        rc=1
        [[ -d ${CURRENT_BACKUP_PATH} && $(pwd) != "/" ]] && rm -rf ${CURRENT_BACKUP_PATH}
    else
        echo "NULL|${CURRENT_BACKUP_PATH}|full" >> ${INC_BASE_LIST}
        [[ -d ${CURRENT_BACKUP_PATH} && $(pwd) != "/" ]] && chattr +i ${CURRENT_BACKUP_PATH} || rc=1
    fi
    chattr -i ${LOCK_FILE}
    rm -f $LOCK_FILE
    chattr +a ${INC_BASE_LIST}
    return $rc
}
 
IncBackup(){
    touch $LOCK_FILE
    chattr +i $LOCK_FILE
    local rc=0
    PREV_BACKUP_DIR=$(sed '/^$/d' ${INC_BASE_LIST} | tail -1 | awk -F '|' '{print $2}')
    ${XTRABACKUP_PATH} \
    --defaults-file=${MYSQL_CNF} \
    --user=${MYSQL_USERNAME} \
    --password=${MYSQL_PASSWORD} \
    --host=${MYSQL_HOSTNAME} \
    --no-timestamp --incremental ${CURRENT_BACKUP_PATH} \
    --incremental-basedir=${PREV_BACKUP_DIR} > ${CURRENT_BACKUP_PATH}_inc.log 2>&1
    grep ".*\ completed\ OK\!" ${CURRENT_BACKUP_PATH}_inc.log > /dev/null 2>&1
    if [ $? -ne 0 ];then
        rc=1
        [[ -d ${CURRENT_BACKUP_PATH} && $(pwd) != "/" ]] && rm -rf ${CURRENT_BACKUP_PATH}
    else
        echo "${PREV_BACKUP_DIR}|${CURRENT_BACKUP_PATH}|inc" >> ${INC_BASE_LIST}
        [[ -d ${CURRENT_BACKUP_PATH} && $(pwd) != "/" ]] && chattr +i ${CURRENT_BACKUP_PATH} || rc=1
    fi
    chattr -i ${LOCK_FILE}
    rm -f $LOCK_FILE
    chattr +a ${INC_BASE_LIST}
    return $rc
}
 
## 全量备份
if [ "$1" == "full" ];then
    FullBackup
fi
 
## 增量备份
if [ "$1" == "inc" ];then
    ## 判断上一次备份是否存在，无则进行全量备份
    if [[ ! -f ${INC_BASE_LIST} || $(sed '/^$/d' ${INC_BASE_LIST} | wc -l) -eq 0 ]];then
        FullBackup
    else
        IncBackup
    fi
fi
 
## 删除14天前的备份
if [[ -d ${BACKUP_BASE_DIR} && $(pwd) != "/" ]];then
    find ${BACKUP_BASE_DIR} -name "$(date -d '14 days ago' +'%F')_*" | xargs chattr -i
    find ${BACKUP_BASE_DIR} -name "$(date -d '14 days ago' +'%F')_*" | xargs rm -rf
fi

