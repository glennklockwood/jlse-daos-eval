#!/usr/bin/env bash

DEFAULT_XFERSIZES="32m 8m 4m 1m 512k 4k 2880"
DEFAULT_NUMNODESES="1 2 4 8" # terrible grammar
DEFAULT_PPNS="16 8 4 2 1"
DEFAULT_ACCESSES="write read"

params="$(getopt -o t:n:p:o:i:a: -l transfersize:,numnodes:,ppn:,access: --name "$0" -- "$@")"
eval set -- "$params"
while true
do  
    case "$1" in
        -t|--transfersize)
            input_xfersize="$2"
            shift 2
            ;;
        -n|--numnodes)
            input_numnodes="$2"
            shift 2
            ;;
        -p|--ppn)
            input_ppn="$2"
            shift 2
            ;;
        -a|--access)
            input_access="$2"
            shift 2
            ;;
        --) 
            shift
            break
            ;;
        *)  
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

if [ -z "$input_xfersize" ]; then
    xfersizes=(${DEFAULT_XFERSIZES})
else
    xfersizes=($input_xfersize)
fi

if [ -z "$input_numnodes" ]; then
    numnodeses=(${DEFAULT_NUMNODESES})
else
    numnodeses=($input_numnodes)
fi

if [ -z "$input_ppn" ]; then
    ppns=($DEFAULT_PPNS)
else
    ppns=($input_ppn)
fi

if [ -z "$input_access" ]; then
    accesses=($DEFAULT_ACCESSES)
else
    accesses=($input_access)
fi

for access in ${accesses[@]}
  do for i in ${xfersizes[@]}
    do for j in ${numnodeses[@]}
      do for k in ${ppns[@]}
        do for l in 0 #1 2 3 4
          do echo "access=$access xfersize=$i numnodes=$j ppn=$k iter=$l";
        done
      done
    done
  done
done
