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

# Extract the environment variables of the process
environ=$(cat "/proc/$pid/environ" | tr '\0' '\n')

# Extract the Azure Blob SAS URL that contains the specific blob path
blob_sas=$(echo "$environ" | grep 'blob.core.windows.net/insights-logs-appserviceconsolelogs' | head -n 1 | cut -d= -f2-)

# Check if blob SAS URL is found
if [ -z "$blob_sas" ]; then
  echo "No Azure Blob SAS URL found containing 'blob.core.windows.net/insights-logs-appserviceconsolelogs'."
else
  echo "Found Azure Blob SAS URL: $blob_sas"
fi

# Take action based on the input argument
case "$1" in
  --dump)
    echo "Collecting dump for PID: $pid"
    /tools/dotnet-dump collect -p "$pid"

    # Find the newest dump file with the pattern 'core_*'
    newest_dump=$(ls -t core_* 2>/dev/null | head -n 1)

    # Check if a dump file is found
    if [ -z "$newest_dump" ]; then
      echo "No dump file found."
    else
      echo "Newest dump file: $newest_dump"
      
      # Upload the dump file to the Azure Blob storage using azcopy
      if [ -n "$blob_sas" ]; then
        echo "Uploading $newest_dump to Azure Blob storage..."
        /tools/azcopy copy "$newest_dump" "$blob_sas"
      else
        echo "No valid Azure Blob SAS URL found. Skipping upload."
      fi
    fi
    ;;
  --trace)
    echo "Collecting trace for PID: $pid with duration 1 minute and 30 seconds"
    /tools/dotnet-trace collect -p "$pid" --duration 00:00:01:30

    # Find the newest trace file with the pattern '*.nettrace'
    newest_trace=$(ls -t *.nettrace 2>/dev/null | head -n 1)

    # Check if a trace file is found
    if [ -z "$newest_trace" ]; then
      echo "No trace file found."
    else
      echo "Newest trace file: $newest_trace"
      
      # Upload the trace file to the Azure Blob storage using azcopy
      if [ -n "$blob_sas" ]; then
        echo "Uploading $newest_trace to Azure Blob storage..."
        /tools/azcopy copy "$newest_trace" "$blob_sas"
      else
        echo "No valid Azure Blob SAS URL found. Skipping upload."
      fi
    fi
    ;;
  *)
    echo "Invalid argument. Use --dump or --trace"
    exit 1
    ;;
esac
