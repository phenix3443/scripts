#!/bin/bash
script_dir=$(dirname "$(readlink -f "$0")")

source "${script_dir}/../utils/os.sh"

install_protoc() {
    # Determine OS platform
    OS=$(detect_os)

    echo "Operating System: ${OS}"

    # Install protobuf based on detected OS
    if [ "${OS}" = "Linux" ]; then
        # Check for Debian-based or Red Hat-based
        if [ -f /etc/debian_version ]; then
            echo "Debian-based Linux detected"
            sudo apt-get update
            sudo apt-get install -y protobuf-compiler
        elif [ -f /etc/redhat-release ]; then
            echo "Red Hat-based Linux detected"
            sudo yum update
            sudo yum install -y protobuf-compiler
        else
            echo "Unsupported Linux distribution"
        fi
    elif [ "${OS}" = "Mac" ]; then
        echo "macOS detected"
        brew install protobuf
    else
        echo "Unsupported operating system"
    fi
}
