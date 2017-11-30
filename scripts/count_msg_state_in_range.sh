#!/bin/bash

set -e

##################################################
# Usage example 1: Delivered in ERROR state

# ./count_msg_state_in_range.sh  -f ~/evm.log -t error -b 2017-11-30T01:45:39 -e 2017-11-30T02:45:39

# [12/01/17 02:02:58 IST] - processing log file: /home/arcolife/evm.log
# [12/01/17 02:02:58 IST] - extracting logs between 2017-11-30T01:45:39 and 2017-11-30T02:45:39
# [12/01/17 02:02:59 IST] - extracted MSG STATE [error] and IDs from /tmp/evm.log_delivered
# [12/01/17 02:02:59 IST] - Processing complete
# [12/01/17 02:02:59 IST] - Results:
#       20 [Container.perf_capture_realtime]

##################################################
# Usage example 2: Delivered in OK state

# $ ./count_msg_state_in_range.sh  -f ~/evm.log -t ok -b 2017-11-30T01:45:39 -e 2017-11-30T02:45:39

# [12/01/17 02:01:45 IST] - processing log file: /home/arcolife/evm.log
# [12/01/17 02:01:45 IST] - extracting logs between 2017-11-30T01:45:39 and 2017-11-30T02:45:39
# [12/01/17 02:01:45 IST] - extracted MSG STATE [ok] and IDs from /tmp/evm.log_delivered
# [12/01/17 02:01:46 IST] - Processing complete
# [12/01/17 02:01:46 IST] - Results:
#       11 [ContainerProject.perf_rollup]
#      14 [ContainerReplicator.perf_rollup]
#      17 [ContainerService.perf_rollup]
#      ............

##################################################

log(){
  echo -e "[$(date +'%D %H:%M:%S %Z')] - $*"
}

user_interrupt(){
  echo
  log ".. Keyboard Interrupt detected."
  log ".. Cleaning up relevant files from /tmp"
  cleanup
  exit 1
}

help_menu(){
  echo "Usage: ./get_all_delivered_in_range.sh [ -b begin ] [ -e end ] [ -f file ] [ -t type]"
  echo "Example: ./get_all_delivered_in_range.sh -b 2017-11-21T03:59 -e 2017-11-21T04:19 -f ./evm.log -t error"
}

# [ $# = 0 ] && {
#   help
#   exit -1
# }

trap user_interrupt SIGINT
trap user_interrupt SIGTSTP

while getopts "h?b:e:f:t:" opt; do
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
  esac
done

init_args(){
  if [[ -z $FILE_P ]]; then
    FILE_P=/var/www/miq/vmdb/log/evm.log
    log "INFO - Using default file path"
  fi
  if [[ -z $msg_type ]]; then
    msg_type='error'
    # other possiblity => 'ok'
    log "INFO - Using default message delivered type - state [error]"
  fi
  log "processing log file: $FILE_P"
  filename=$(basename $FILE_P)
  extension=${FILE_P#*.}
  file_delivered=/tmp/"$filename"_delivered
  log_frag_file=/tmp/"$filename"_log_frag
  ids_file=/tmp/"$filename"_ids
  completed_file=/tmp/"$filename"_completed
}

cleanup(){
  # cleanup traces of symlink if present
  if [[ -f $log_frag_file ]]; then
    log "deleting previous garbage -> $log_frag_file"
    rm $log_frag_file
  fi

  if [[ -f $file_delivered ]]; then
    log "deleting previous garbage -> $file_delivered"
    rm $file_delivered
  fi

  if [[ -f $ids_file ]]; then
    log "deleting previous garbage -> $ids_file"
    rm $ids_file
  fi

  if [[ -f $completed_file ]]; then
    log "deleting previous garbage -> $completed_file"
    rm $completed_file
  fi
}

preprocess(){
  less $1 | grep 'State\: \['$msg_type'\], Delivered in' > $file_delivered
  cat $file_delivered |  grep -oE '(Message id: \[[0-9]*\])' | sed 's/Message id: \[//' | sed 's/.\{1\}$//' > $ids_file
  log "extracted MSG STATE [$msg_type] and IDs from $file_delivered"
}

init_args
cleanup

if [[ -z $log_start || -z $log_end ]]; then
  log "consuming entire evm.log because time range was not supplied"
  ln -s $FILE_P $log_frag_file
  # preprocess $FILE_P
else
  log "extracting logs between $log_start and $log_end"
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
fi

preprocess $log_frag_file

touch $completed_file

for current_id in `cat $ids_file`; do grep 'MiqQueue.put.*\['$current_id'\]' $log_frag_file | tail -1 | sed -n -e 's/^.*Command: \(\[.*.]\), Timeout.*/\1/p' >> $completed_file; done

log "Processing complete"

log "Results: \n $(cat $completed_file  | sort | uniq -c)"
