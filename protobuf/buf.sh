#!/bin/bash

script_dir=$(dirname "$(readlink -f "$0")")

source "${script_dir}/../utils/os.sh"

# Function to install buf
function install_buf() {
    OS=$(detect_os)

    echo "Operating System: ${OS}"

    if [ "${OS}" = "Linux" ]; then
        go install github.com/bufbuild/buf/cmd/buf@v1.30.1
    elif [ "${OS}" = "Mac" ]; then
        # Install buf using Homebrew
        brew install bufbuild/buf/buf
    else
        echo "Unsupported operating system"
    fi
}

# Install buf
install_buf
