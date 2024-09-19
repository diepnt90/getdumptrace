#!/bin/bash

# Find the PID of the .NET process
pid=$(/tools/dotnet-dump ps | grep '/usr/share/dotnet/dotnet' | awk '{print $1}')

# Check if PID was found
if [ -z "$pid" ]; then
    echo "Error: Could not find the .NET process."
    exit 1
fi

# Get the environment variables of the process
environ=$(cat "/proc/$pid/environ" | tr '\0' '\n')

# Display the environment variables
echo "$environ"
