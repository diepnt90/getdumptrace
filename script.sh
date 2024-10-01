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
    /tools/dotnet-dump collect -p "$pid" -o "/home/dump-trace/core_${pid}_$(date +%Y%m%d%H%M%S).dump"
    echo "Dump collection completed."
elif [ "$1" == "--trace" ]; then
    echo "Step 5: Running dotnet-trace to collect trace for PID $pid..."
    /tools/dotnet-trace collect -p "$pid" --duration 00:01:30 -o "/home/dump-trace/trace_${pid}_$(date +%Y%m%d%H%M%S).nettrace"
    echo "Trace collection completed."
else
    echo "Error: Invalid parameter. Use '--dump' or '--trace'. Exiting."
    exit 1
fi

# Step 6: Get environment variable
echo "Step 6: Retrieving environment variables for PID $pid..."
environ=$(cat "/proc/$pid/environ" | tr '\0' '\n')
if [ -z "$environ" ]; then
    echo "Error: Unable to retrieve environment variables for PID $pid. Exiting."
    exit 1
fi
echo "Environment variables retrieved."

# Step 7: Get the container URL
echo "Step 7: Extracting container URL from environment variables..."
container_url=$(echo "$environ" | grep 'blob.core.windows.net/insights-logs-appserviceconsolelogs' | head -n 1 | cut -d= -f2-)
if [ -z "$container_url" ]; then
    echo "Error: Container URL not found in environment variables. Exiting."
    exit 1
fi
echo "Container URL: $container_url"

# Step 8: Show the container URL value
echo "Step 8: Displaying container URL..."
echo "Container URL: $container_url"

# Step 9: Find the newest trace or dump in /home/dump-trace based on input parameter
echo "Step 9: Finding the newest trace or dump file in /home/dump-trace..."
if [ "$1" == "--dump" ]; then
    collected_file=$(find /home/dump-trace -type f -name 'core_*' -print0 | xargs -0 ls -t | head -n 1)
    echo "Newest dump file: $collected_file"
elif [ "$1" == "--trace" ]; then
    collected_file=$(find /home/dump-trace -type f -name '*.nettrace' -print0 | xargs -0 ls -t | head -n 1)
    echo "Newest trace file: $collected_file"
fi

# Step 10: Upload the trace or dump using azcopy
if [ -n "$collected_file" ]; then
    echo "Step 10: Uploading file $collected_file to $container_url using azcopy..."
    /tools/azcopy copy "$collected_file" "$container_url"
    if [ $? -eq 0 ]; then
        echo "File uploaded successfully."
    else
        echo "Error: File upload failed."
    fi
else
    echo "Error: No trace or dump file found to upload."
fi

# Step 11: If the input parameter is -r, restart the application
if [ "$2" == "-r" ]; then
    echo "Step 11: Restarting the application by killing 'start.sh' process..."
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

# Step 12: Clean the /home/dump-trace directory
echo "Step 12: Cleaning up /home/dump-trace directory..."
rm -rf /home/dump-trace/*
if [ $? -eq 0 ]; then
    echo "/home/dump-trace directory cleaned successfully."
else
    echo "Error: Failed to clean /home/dump-trace directory."
fi
