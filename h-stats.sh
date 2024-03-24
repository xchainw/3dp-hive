#!/usr/bin/env bash

#######################
# Functions
#######################

. "3dp/h-manifest.conf"

log_basename="$CUSTOM_LOG_BASENAME"
log_name="$log_basename.log"
conf_name="$CUSTOM_CONFIG_FILENAME"

# Define a function to calculate the miner version.
get_miner_version() {
    local ver="${CUSTOM_VERSION}"
    echo "$ver"
}

# This function calculates the uptime of the miner by determining the time elapsed since the last modification of the log file.
get_miner_uptime(){
  local uptime=0
  local log_time=$(stat --format='%Y' "$log_name")

  # Check configuration file exists. If it does, get its last modification time.
  if [ -e "$conf_name" ]; then
    local conf_time=$(stat --format='%Y' "$conf_name")
    uptime=$((log_time-conf_time))
  fi
  echo $uptime
}

# Function to get log time difference
get_log_time_diff() {
    local a=0
    a=$(( $(date +%s) - $(stat --format='%Y' "$log_name") ))
    echo $a
}

diffTime=$(get_log_time_diff)
maxDelay=300


if [ "$diffTime" -lt "$maxDelay" ]; then
  ver=$(get_miner_version)
  hs_units="hs"
  algo="$CUSTOM_ALGO"
  
  uptime=$(get_miner_uptime)

  # Calculating GPU count

  gpu_brand=$(jq '.brand' <<< "$gpu_stats")
  gpu_count=$(jq 'length' <<< "$gpu_brand")
  [[ -z $gpu_count ]] && gpu_count=0
  
  # enabled devices
  enabled_devices=($(head -n 50 $log_name | grep -oP 'Enable Device: #\K\d+'))

  echo ----------
  echo "gpu_count: $gpu_count"
  echo "enable devices: ${enabled_devices[*]}"
  echo "gpu_stats: $gpu_stats"
  echo ----------

  if [[ $gpu_count -ge 0 ]]; then
    share_stats=$(cat $log_name | tail -n 50 | grep -oP 'a/r/d:\K\d+/\d+/\d+' | tail -n 1)

    # parse each share stats
    accept_share=$(echo "$share_stats" | awk -F '/' '{print $1}')
    reject_share=$(echo "$share_stats" | awk -F '/' '{print $2}')
    invalid_share=$(echo "$share_stats" | awk -F '/' '{print $3}')

    gpu_temp=$(jq '.temp' <<< "$gpu_stats")
    gpu_fan=$(jq '.fan' <<< "$gpu_stats")
    gpu_bus=$(jq '.busids' <<< "$gpu_stats")
  	
    gpu_khs_tot=0

    for i in "${enabled_devices[@]}"; do
      # miner's default hashrate is khs
      khz[$i]=$(cat $log_name | tail -n 50 | grep "#${i}.*it/s" | awk '{match($0, /[0-9]+\.[0-9]+k it\/s/); print substr($0, RSTART, RLENGTH-6)}' | tail -n 1)
      [[ -z ${khz[$i]} ]] && khz[$i]=0
      # convert khs to hs
      hs[$i]=$(echo "${khz[$i]} * 1000" | bc)
      
      gpu_khs_tot=$(echo "$gpu_khs_tot + ${khz[$i]}" | bc)
      temp[$i]=$(jq .[$i] <<< "$gpu_temp")
      fan[$i]=$(jq .[$i] <<< "$gpu_fan")
      busid=$(jq .[$i] <<< "$gpu_bus")
      bus_numbers[$i]=$(echo $busid | cut -d ":" -f1 | cut -c2- | awk -F: '{ printf "%d\n",("0x"$1) }')
    done
  fi
  
  ac=$accept_share
  rj=$reject_share
  iv=$invalid_share
  # miner's total khs
  khs=$gpu_khs_tot


  stats=$(jq -nc \
            --arg khs "$khs" \
            --arg hs_units "$hs_units" \
            --argjson hs "$(echo "${hs[@]}" | tr " " "\n" | jq -cs '.')" \
            --argjson temp "$(echo "${temp[@]}" | tr " " "\n" | jq -cs '.')" \
            --argjson fan "$(echo "${fan[@]}" | tr " " "\n" | jq -cs '.')" \
            --arg uptime "$uptime" \
            --arg ver "$ver" \
            --arg ac "$ac" --arg rj "$rj" --arg iv "$iv" \
            --arg algo "$algo" \
            --argjson bus_numbers "$(echo "${bus_numbers[@]}" | tr " " "\n" | jq -cs '.')" \
            '{$hs, $hs_units, $temp, $fan, $uptime, $ver, ar: [$ac, $rj, $iv], $algo, $bus_numbers}')

else
  stats=""
  khs=0
fi

 echo khs:   $khs
 echo stats: $stats
 echo ----------