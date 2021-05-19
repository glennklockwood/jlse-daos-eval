#!/usr/bin/env bash

SRUN="mpirun -f \$COBALT_NODEFILE -genvall"
DEFAULT_IOR="/home/glock/src/glior-3.3/install.jlse/bin/ior"
DEFAULT_PARAMFILE="parameters.txt"

params="$(getopt -o i: -l paramfile:,ior: --name "$0" -- "$@")"
eval set -- "$params"
while true
do  
    case "$1" in
        --paramfile)
            input_paramfile="$2"
            shift 2
            ;;
        -i|--ior)
            ior="$2"
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

if [ -z "$ior" ]; then
    ior="${DEFAULT_IOR}"
fi

if [ -z "$input_paramfile" ]; then
    paramfile=($DEFAULT_PARAMFILE)
else
    paramfile=($input_paramfile)
fi

if [ ! -f "$ior" ]; then
    echo "IOR $ior does not exist" >&2
    exit 1
fi

if [ ! -f "$paramfile" ]; then
    echo "Parameter file $paramfile does not exist" >&2
    exit 1
fi

declare -A access_params
access_params[read]="-r"
access_params[write]="-w -k"

# load permutations from a file
mapfile -t permutations < "$paramfile"

# iterate through the shuffled list of randomizations
for paramset in "${permutations[@]}"; do

  # use the permutations to set variables
  eval $paramset

  if [[ $xfersize == *m ]]; then
    xsize=$(sed -e 's/m$//' <<< $xfersize)
    xsize=$((xsize * 1024 * 1024))
  elif [[ $xfersize == *k ]]; then
    xsize=$(sed -e 's/k$//' <<< $xfersize)
    xsize=$((xsize * 1024))
  else
    xsize=$xfersize
  fi

  # figure out if the run has already happened - note this will not know if a
  # read test did not run correctly, so if an iteration does its writes but
  # not reads, delete the entire output file and start again.  you also have
  # to sniff out output files that contain write results without read results
  # explicitly!
  output_bn="ior-n${numnodes}ppn${ppn}t${xsize}.${iter}"
  output_f="$PWD/${output_bn}-${access}.out"
  err_f="$PWD/${output_bn}-${access}.err"
  if [ -f "${output_f}" ]; then
    if [ "$access" == "write" ]; then
      echo "[$(date)] $output_f exists for writes; skipping"
      continue
    elif grep -q "^read" "$output_f"; then
      echo "[$(date)] $output_f contains read result; skipping"
      continue
    fi
  fi

  # if reading but stonewall doesn't exist, ior will fail when it hits EOF
  stonewall_f="$PWD/${output_bn}.sws"
  if [ "$access" == "read" ]; then
    if [ ! -f "$stonewall_f" ]; then
      echo "[$(date)] $stonewall_f does not exist for ${output_bn}; skipping"
      continue
    fi
  fi

  # file basename we will be reading/writing - actually has .00000xx appended
  datafile_f="${output_bn}.data"

  echo "[$(date)] Running numnodes=$numnodes ppn=$ppn xfersize=$xfersize output=$output_f access=$access"

  # write 16 TiB total in 45 sec - increase for writes faster than 355 GB/s
  segct=$((16 * 1024 * 1024 * 1024 * 1024 / xsize / numnodes / ppn))
  if [ $segct -gt 2147483647 ]; then
      segct=2147483647
  fi
  base_ior_args="-b $xfersize \
                 -t $xfersize \
                 -s $segct \
                 -e -F -C -g \
                 -D 45 -O "stoneWallingWearOut=1" \
                 -O "stoneWallingStatusFile=${stonewall_f}" \
                 -o "\${DFUSE_MOUNT}/${datafile_f}" \
                 -vv"
  set -x
  set -e
  tmpfile="$RANDOM.qsub"
  touch "$tmpfile"
  chmod +x "$tmpfile"
  mpirun="$SRUN -ppn $ppn \"${ior}\" $base_ior_args ${access_params[$access]} 2>>\"${err_f}\" > \"$output_f\""
  sed -e "s@^XXX\$@${mpirun}@" run-ior.qsub > "$tmpfile"
  cat $tmpfile
  # qsub -q presque -n 1 -t 0:30:00 -I
  jid=$(qsub -q presque -n ${numnodes} -t 30 "$tmpfile")
  cqwait "$jid"
  rm -v "$tmpfile"
  set +x
  set +e
done
