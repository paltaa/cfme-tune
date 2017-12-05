#!/bin/bash

# Usage examples: https://gist.github.com/arcolife/6d6bda31ad3685e05cb1f91c34d97d4b

log(){
  # Date Macros:
  # - TZ=UTC
  # TZ=$log_tz

  # date formats
  # --rfc-2822
  # +'%Y-%m-%dT%H:%M:%S'
  # +'%D %H:%M:%S %Z'
  echo -e "[$(TZ=America/New_York date +'%Y-%m-%d %H:%M:%S %Z')] - $*"
}

user_interrupt(){
  echo
  log "INFO -- .. Keyboard Interrupt detected."
  log "INFO -- .. Cleaning up relevant files from /tmp"
  cleanup
  exit 1
}

help_menu(){
  echo -e "Usage: \n\t./count_msg_state_in_range.sh [ -b begin ] [ -e end ] [ -f file ] [ -t type] [-c -- ]"
  echo -e "Example: \n\t./count_msg_state_in_range.sh -b 2017-11-21T03:59 -e 2017-11-21T04:19 -f ~/evm.log -t ok"
}

# [ $# = 0 ] && {
#   help
#   exit -1
# }

trap user_interrupt SIGINT
trap user_interrupt SIGTSTP

while getopts "h?b:e:f:t:c:" opt; do
  case "$opt" in
    h|\?)
    help_menu
    exit 0
    ;;
    b)
    log_start=$OPTARG
    ;;
    e)
    log_end=$OPTARG
    ;;
    f)
    FILE_P=$OPTARG
    ;;
    t)
    msg_type=$OPTARG
    ;;
    c)
    consume_all=1
    ;;
  esac
done

# Logfile created on 2017-11-29 06:16:54 -0500 by logger.rb/54362

init_args(){

  if [[ -z $FILE_P ]]; then
    FILE_P=/var/www/miq/vmdb/log/evm.log
    log "INFO -- Using default file path"
  fi

  log "INFO -- processing log file: $FILE_P"

  get_tz=$(grep "Logfile created on" $FILE_P)
  log_tz=$(echo $get_tz| sed -n -e 's/^.*created on.*-\(.*\) by.*$/\1/p')
  log "INFO -- Attempting to infer Log TZ"
  if [[ $log_tz -eq 0500 ]]; then
    log_tz="America/New_York"
    log "Timezone for log is $log_tz"
  elif [[ -z $get_tz ]]; then
      log "INFO -- [default mode] Unable to find TZ of log; Assuming EST"
      log_tz="America/New_York"
  else
      log_tz="UTC"
  fi

  if [[ -z $msg_type ]]; then
    msg_type='error'
    # other possiblity => 'ok'
    log "INFO -- Using default message delivered type - state [error]"
  fi
  filename=$(basename $FILE_P)
  extension=${FILE_P#*.}
  file_delivered=/tmp/"$filename"_delivered
  log_frag_file=/tmp/"$filename"_log_frag
  ids_file=/tmp/"$filename"_ids
  completed_file=/tmp/"$filename"_completed

  set -e
}

cleanup(){
  # cleanup traces of symlink if present
  if [[ -f $log_frag_file ]]; then
    log "INFO -- deleting previous garbage -> $log_frag_file"
    rm $log_frag_file
  fi

  if [[ -f $file_delivered ]]; then
    log "INFO -- deleting previous garbage -> $file_delivered"
    rm $file_delivered
  fi

  if [[ -f $ids_file ]]; then
    log "INFO -- deleting previous garbage -> $ids_file"
    rm $ids_file
  fi

  if [[ -f $completed_file ]]; then
    log "INFO -- deleting previous garbage -> $completed_file"
    rm $completed_file
  fi
}

preprocess(){
  less $1 | grep 'State\: \['$msg_type'\], Delivered in' > $file_delivered
  cat $file_delivered |  grep -oE '(Message id: \[[0-9]*\])' | \
    sed 's/Message id: \[//' | sed 's/.\{1\}$//' > $ids_file
  log "INFO -- extracted MSG STATE [$msg_type] and IDs from $file_delivered"
}

fragment_logfile(){
  if [[ $extension == '.tar.gz' ]]; then
    # deal with archived evm log file
    echo -e "$(less $FILE_P | awk -F'[]]|[[]| ' '$0 ~ /^\[----\] I, \[/ &&
      $6 >= "'$log_start'" { p=1 }
      $6 >= "'$log_end'" { p=0 } p { print $0 }' \
      )" > $log_frag_file
  else
    echo -e "$(awk -F'[]]|[[]| ' '$0 ~ /^\[----\] I, \[/ &&
      $6 >= "'$log_start'" { p=1 }
      $6 >= "'$log_end'" { p=0 } p { print $0 }' \
      $FILE_P )" > $log_frag_file
  fi
}

get_log_range(){
  # get first and last times of log
  log_start_est=$(head -n 1 $FILE_P | sed -n -e 's/^.*created on \(.*\) by.*/\1/p')
  if [[ -z $time_start_est ]]; then
    # if evm.log is already fragmented (i.e., not the whole log file)
    log_start_est=$(grep -P 'INFO|ERROR' $FILE_P -m 1 | sed -n -e 's/^.*I, \[\(.*\) #.*\].*/\1/p' | awk -F'.' '{print$1}')
  fi
  log_end_est=$(tac $FILE_P | grep -P 'INFO|ERROR'  -m 1 | sed -n -e 's/^.*I, \[\(.*\) #.*\].*/\1/p' | awk -F'.' '{print$1}')
}

check_supplied_range(){
  log_begin_in_seconds=$(date -d $log_start_est +%s)
  log_end_in_seconds=$(date -d $log_end_est +%s)
  supplied_beg_in_seconds=$(date -d $log_start +%s)
  supplied_end_in_seconds=$(date -d $log_end +%s)

  time_change_flag=0

  if [[ supplied_beg_in_seconds -lt log_begin_in_seconds ]]; then
    log "WARN - Supplied BEGIN precedes log range. Recaliberating to Log's beginning"
    log_start=$log_start_est
    log "INFO -- New log_start = $log_start"
    time_change_flag=1
  elif [[ supplied_beg_in_seconds -ge log_end_in_seconds ]]; then
    log "ERROR -- Invalid Begin time; exceeds Log's end range"
    exit 1
  fi

  if [[ supplied_end_in_seconds -gt log_end_in_seconds ]]; then
    log "WARN - Supplied END exceeds log range. Recaliberating to Log's end"
    log_end=$log_end_est
    log "INFO -- New log_end = $log_end"
    time_change_flag=1
  elif [[ supplied_end_in_seconds -le log_begin_in_seconds ]]; then
    log "ERROR -- Invalid End time; precedes Log's beging range"
    exit 1
  fi

  if [[ $time_change_flag -eq 0 ]]; then
    log "INFO -- Supplied time range is a valid subset of log's range"
  fi
}

define_log_range(){
  if [[ $consume_all -eq 1 ]]; then
    log "INFO -- consuming entire evm.log"
    ln -s $FILE_P $log_frag_file
  elif [[ -z $log_start || -z $log_end ]]; then
    log "INFO -- [default mode] using last 1 hour's worth of log data to process events."
    log_end=$(tail -1 $FILE_P  | sed -n -e 's/^.*I, \[\(.*\) #.*\].*/\1/p' | awk -F'.' '{print$1}')
    time_last_est=$(TZ=$log_tz date -d "$log_end")
    log_start=$(TZ=$log_tz date --date="${time_last_est} - 1 hour" +'%Y-%m-%dT%H:%M:%S')
    fragment_logfile
  else
    # check if supplied time range is a subset of log file's range
    get_log_range
    check_supplied_range
    log "INFO -- extracting logs between $log_start and $log_end"
    fragment_logfile
  fi
}

postprocess(){
  touch $completed_file
  log "INFO -- Counting delivered MSG STATE [$msg_type] messages"
  for current_id in `cat $ids_file`; do
    grep 'MiqQueue.put.*\['$current_id'\]' $log_frag_file | tail -1 | sed -n -e 's/^.*Command: \(\[.*.]\), Timeout.*/\1/p' >> $completed_file;
  done
  log "INFO -- Processing complete"
  log "INFO -- Results: \n $(cat $completed_file  | sort | uniq -c)"
}

init_args
cleanup
define_log_range
preprocess $log_frag_file
postprocess
