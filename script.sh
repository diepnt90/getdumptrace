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

# Extract COMPUTERNAME from the environment variable
COMPUTERNAME=$(echo "$environ" | grep '^COMPUTERNAME=' | cut -d= -f2)

# Check if COMPUTERNAME is found
if [ -z "$COMPUTERNAME" ]; then
  echo "COMPUTERNAME not found in environment."
  exit 1
fi

# Extract the Azure Blob SAS URL that contains the specific blob path
blob_sas=$(echo "$environ" | grep 'blob.core.windows.net/insights-logs-appserviceconsolelogs' | head -n 1 | cut -d= -f2-)

# Check if blob SAS URL is found
if [ -z "$blob_sas" ]; then
  echo "No Azure Blob SAS URL found containing 'blob.core.windows.net/insights-logs-appserviceconsolelogs'."
else
  echo "Found Azure Blob SAS URL: $blob_sas"
fi

# Timestamp to be used in the output file names
timestamp=$(date +"%Y%m%d_%H%M%S")

# Take action based on the input argument
case "$1" in
  --dump)
    echo "Collecting dump for PID: $pid"

    # Specify the output name directly with the -o flag, without .dmp extension
    dump_file="core_${COMPUTERNAME}_${timestamp}"
    /tools/dotnet-dump collect -p "$pid" -o "$dump_file"

    # Check if the dump file was created successfully
    if [ ! -f "$dump_file" ]; then
      echo "Failed to create dump file."
    else
      echo "Dump file created: $dump_file"

      # Wait for 10 seconds to ensure the file is fully written
      echo "Waiting for 10 seconds to ensure the file is stable before uploading..."
      sleep 10

      # Upload the dump file to Azure Blob storage using azcopy
      if [ -n "$blob_sas" ]; then
        echo "Uploading $dump_file to Azure Blob storage..."
        /tools/azcopy copy "$dump_file" "$blob_sas"
      else
        echo "No valid Azure Blob SAS URL found. Skipping upload."
      fi
    fi
    ;;
    
  --trace)
    echo "Collecting trace for PID: $pid with duration 1 minute and 30 seconds"

    # Specify the output name directly with the -o flag
    trace_file="${COMPUTERNAME}_${timestamp}.nettrace"
    /tools/dotnet-trace collect -p "$pid" --duration 00:00:01:30 -o "$trace_file"

    # Check if the trace file was created successfully
    if [ ! -f "$trace_file" ]; then
      echo "Failed to create trace file."
    else
      echo "Trace file created: $trace_file"

      # Wait for 10 seconds to ensure the file is fully written
      echo "Waiting for 10 seconds to ensure the file is stable before uploading..."
      sleep 10

      # Upload the trace file to Azure Blob storage using azcopy
      if [ -n "$blob_sas" ]; then
        echo "Uploading $trace_file to Azure Blob storage..."
        /tools/azcopy copy "$trace_file" "$blob_sas"
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

# Clean up: Clear the /home/dump-trace directory
echo "Cleaning up the /home/dump-trace directory..."
rm -rf /home/dump-trace/*

echo "Cleanup completed."
