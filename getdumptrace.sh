#!/bin/bash

# Initialize flags
dump_flag=false
trace_flag=false
restart_flag=false

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    key="$1"

    case $key in
        --dump)
            dump_flag=true
            shift
            ;;
        --trace)
            trace_flag=true
            shift
            ;;
        -r|--restart)
            restart_flag=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--dump | --trace] [-r|--restart]"
            exit 1
            ;;
    esac
done

# Ensure that either --dump or --trace is specified
if [ "$dump_flag" = false ] && [ "$trace_flag" = false ]; then
    echo "Error: You must specify either --dump or --trace."
    echo "Usage: $0 [--dump | --trace] [-r|--restart]"
    exit 1
fi

# Ensure that both --dump and --trace are not specified together
if [ "$dump_flag" = true ] && [ "$trace_flag" = true ]; then
    echo "Error: You cannot specify both --dump and --trace at the same time."
    echo "Usage: $0 [--dump | --trace] [-r|--restart]"
    exit 1
fi

# Step 1: Create directory and change into it
mkdir -p /home/dump-trace && cd /home/dump-trace

# Find the PID of the .NET process
pid=$(/tools/dotnet-dump ps | grep '/usr/share/dotnet/dotnet' | awk '{print $1}')

# Check if PID was found
if [ -z "$pid" ]; then
    echo "Error: Could not find the .NET process."
    exit 1
fi

# Step 2: Collect dump or trace based on the flag
if [ "$dump_flag" = true ]; then
    echo "Collecting memory dump..."
    /tools/dotnet-dump collect -p "$pid"
elif [ "$trace_flag" = true ]; then
    echo "Collecting performance trace..."
    /tools/dotnet-trace collect -p "$pid" --duration 00:00:01:30
fi

# Step 3: Get environment variables
environ=$(cat "/proc/$pid/environ" | tr '\0' '\n')

# Step 4: Extract the container URL from environment variables
container_url=$(echo "$environ" | grep 'blob.core.windows.net/insights-logs-appserviceconsolelogs' | head -n 1 | cut -d= -f2-)

# Display the container URL
echo "Container URL: $container_url"

# Step 5: Find the collected file
if [ "$dump_flag" = true ]; then
    collected_file=$(ls -t /home/dump-trace/core_* | head -1)
elif [ "$trace_flag" = true ]; then
    collected_file=$(ls -t /home/dump-trace/*.nettrace | head -1)
fi

if [ -z "$collected_file" ]; then
    echo "No collected file found."
else
    echo "File to be uploaded: $collected_file"
    # Step 6: Upload the collected file
    if [ -n "$container_url" ]; then
        /tools/azcopy copy "$collected_file" "$container_url"
        if [ $? -eq 0 ]; then
            echo "File uploaded successfully."
            # Remove the collected file after successful upload
            rm "$collected_file"
            echo "Collected file removed."
        else
            echo "Failed to upload the file."
            # Optionally, remove the collected file even if upload failed
            # rm "$collected_file"
            # echo "Collected file removed despite upload failure."
        fi
    else
        echo "Container URL not found in environment variables."
    fi
fi

# If the -r or --restart option was used, restart the application
if [ "$restart_flag" = true ]; then
    echo "Restarting the application by killing 'start.sh' process..."
    pid_to_kill=$(ps -A | grep '[s]tart\.sh' | awk '{print $1}')
    if [ -n "$pid_to_kill" ]; then
        kill -9 "$pid_to_kill"
        echo "'start.sh' process killed."
    else
        echo "No 'start.sh' process found to kill."
    fi
fi
