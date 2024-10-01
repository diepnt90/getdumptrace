#!/bin/bash

# Step 1: Create a folder /home/dump-trace if it doesn't exist
echo "Step 1: Checking if /home/dump-trace directory exists..."
if [ ! -d "/home/dump-trace" ]; then
    mkdir -p /home/dump-trace
    echo "/home/dump-trace directory created."
else
    echo "/home/dump-trace directory already exists."
fi

# Step 2: Get the first PID
echo "Step 2: Getting the first PID for '/usr/share/dotnet/dotnet'..."
pid=$( /tools/dotnet-dump ps | grep '/usr/share/dotnet/dotnet' | awk '{print $1}' | head -n 1 )
echo "PID obtained: $pid"

# Step 3: Echo the PID value
if [ -z "$pid" ]; then
    echo "Error: No PID found for '/usr/share/dotnet/dotnet'. Exiting."
    exit 1
fi

# Step 4 & 5: Check the input parameter
if [ "$1" == "--dump" ]; then
    echo "Step 4: Running dotnet-dump to collect dump for PID $pid..."
    dump_file="/home/dump-trace/core_${pid}_$(date +%Y%m%d%H%M%S).dump"
    /tools/dotnet-dump collect -p "$pid" -o "$dump_file"
    echo "Dump collection completed. Expected file: $dump_file"
elif [ "$1" == "--trace" ]; then
    echo "Step 5: Running dotnet-trace to collect trace for PID $pid..."
    trace_file="/home/dump-trace/trace_${pid}_$(date +%Y%m%d%H%M%S).nettrace"
    /tools/dotnet-trace collect -p "$pid" --duration 00:01:30 -o "$trace_file"
    echo "Trace collection completed. Expected file: $trace_file"
else
    echo "Error: Invalid parameter. Use '--dump' or '--trace'. Exiting."
    exit 1
fi

# Step 6: Check if files were created
echo "Step 6: Listing files in /home/dump-trace..."
ls -l /home/dump-trace

# Step 7: Find the newest trace or dump in /home/dump-trace based on input parameter
echo "Step 7: Finding the newest trace or dump file in /home/dump-trace..."
if [ "$1" == "--dump" ]; then
    collected_file=$(find /home/dump-trace -type f -name 'core_*' -print0 | xargs -0 ls -t | head -n 1)
elif [ "$1" == "--trace" ]; then
    collected_file=$(find /home/dump-trace -type f -name '*.nettrace' -print0 | xargs -0 ls -t | head -n 1)
fi

# Step 8: Echo the collected file
echo "Collected file found: $collected_file"

# Step 9: Upload the trace or dump using azcopy
if [ -z "$collected_file" ]; then
    echo "Error: No trace or dump file found to upload. Exiting."
    exit 1
fi

if [ ! -f "$collected_file" ]; then
    echo "Error: The file '$collected_file' does not exist. Exiting."
    exit 1
fi

echo "Uploading file $collected_file to $container_url using azcopy..."
/tools/azcopy copy "$collected_file" "$container_url" --from-to=LocalBlob
if [ $? -eq 0 ]; then
    echo "File uploaded successfully."
else
    echo "Error: File upload failed."
fi

# Step 10: If the input parameter is -r, restart the application
if [ "$2" == "-r" ]; then
    echo "Step 10: Restarting the application by killing 'start.sh' process..."
    pid_to_kill=$(ps -A | grep '[s]tart\.sh' | awk '{print $1}')
    if [ -n "$pid_to_kill" ]; then
        kill -9 "$pid_to_kill"
        if [ $? -eq 0 ]; then
            echo "'start.sh' process killed successfully."
        else
            echo "Error: Failed to kill 'start.sh' process."
        fi
    else
        echo "No 'start.sh' process found to kill."
    fi
fi
