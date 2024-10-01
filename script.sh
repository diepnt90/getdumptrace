#!/bin/bash

# Check if the input argument is provided
if [ -z "$1" ]; then
  echo "Usage: $0 --dump or --trace"
  exit 1
fi

# Create the /home/dump-trace directory if it does not exist
mkdir -p /home/dump-trace

# Change directory to /home/dump-trace
cd /home/dump-trace || exit

# Find the first PID of the process running '/usr/share/dotnet/dotnet'
pid=$(/tools/dotnet-dump ps | grep '/usr/share/dotnet/dotnet' | awk '{print $1}' | head -n 1)

# Check if PID is found
if [ -z "$pid" ]; then
  echo "No process found for '/usr/share/dotnet/dotnet'."
  exit 1
fi

# Take action based on the input argument
case "$1" in
  --dump)
    echo "Collecting dump for PID: $pid"
    /tools/dotnet-dump collect -p "$pid"
    ;;
  --trace)
    echo "Collecting trace for PID: $pid with duration 1 minute and 30 seconds"
    /tools/dotnet-trace collect -p "$pid" --duration 00:00:01:30
    ;;
  *)
    echo "Invalid argument. Use --dump or --trace"
    exit 1
    ;;
esac
