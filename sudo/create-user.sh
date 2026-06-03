#!/bin/bash

# 创建具有 sudo 权限的用户账号

create_user_with_sudo() {
    local username=$1
    local password=$2

    if [ -z "$username" ]; then
        echo "错误: 请提供用户名"
        echo "使用方法: $0 create <username> [password]"
        exit 1
    fi

    # 检查用户是否已存在
    if id "$username" &>/dev/null; then
        echo "错误: 用户 $username 已存在"
        exit 1
    fi

    echo "正在创建用户: $username"

    # 创建用户
    if [ -n "$password" ]; then
        # 如果提供了密码，使用 useradd 创建用户并设置密码
        sudo useradd -m -s /bin/bash "$username"
        echo "$username:$password" | sudo chpasswd
    else
        # 如果没有提供密码，创建用户但不设置密码（需要后续手动设置）
        sudo useradd -m -s /bin/bash "$username"
        echo "警告: 用户 $username 已创建但未设置密码，请使用 'sudo passwd $username' 设置密码"
    fi

    # 将用户添加到 sudo 组（推荐方法）
    sudo usermod -aG sudo "$username"
    echo "已将用户 $username 添加到 sudo 组"

    # 验证用户是否在 sudo 组中
    if groups "$username" | grep -q "\bsudo\b"; then
        echo "✓ 用户 $username 已成功创建并具有 sudo 权限"
    else
        echo "✗ 警告: 无法验证 sudo 权限"
    fi
}

add_sudo_to_user() {
    local username=$1

    if [ -z "$username" ]; then
        echo "错误: 请提供用户名"
        echo "使用方法: $0 add_sudo <username>"
        exit 1
    fi

    # 检查用户是否存在
    if ! id "$username" &>/dev/null; then
        echo "错误: 用户 $username 不存在"
        exit 1
    fi

    # 检查用户是否已在 sudo 组中
    if groups "$username" | grep -q "\bsudo\b"; then
        echo "用户 $username 已经具有 sudo 权限"
        exit 0
    fi

    # 将用户添加到 sudo 组
    sudo usermod -aG sudo "$username"
    echo "✓ 已为用户 $username 添加 sudo 权限"
}

remove_sudo_from_user() {
    local username=$1

    if [ -z "$username" ]; then
        echo "错误: 请提供用户名"
        echo "使用方法: $0 remove_sudo <username>"
        exit 1
    fi

    # 检查用户是否存在
    if ! id "$username" &>/dev/null; then
        echo "错误: 用户 $username 不存在"
        exit 1
    fi

    # 从 sudo 组中移除用户
    sudo deluser "$username" sudo
    echo "✓ 已移除用户 $username 的 sudo 权限"
}

# 根据参数执行相应操作
case $1 in
create)
    create_user_with_sudo "$2" "$3"
    ;;
add_sudo)
    add_sudo_to_user "$2"
    ;;
remove_sudo)
    remove_sudo_from_user "$2"
    ;;
*)
    echo "使用方法: $0 [create|add_sudo|remove_sudo] <username> [password]"
    echo ""
    echo "命令说明:"
    echo "  create <username> [password]    - 创建新用户并授予 sudo 权限"
    echo "  add_sudo <username>            - 为现有用户添加 sudo 权限"
    echo "  remove_sudo <username>         - 移除用户的 sudo 权限"
    echo ""
    echo "示例:"
    echo "  $0 create myuser                    # 创建用户（不设置密码）"
    echo "  $0 create myuser mypassword         # 创建用户并设置密码"
    echo "  $0 add_sudo existinguser            # 为现有用户添加 sudo 权限"
    echo "  $0 remove_sudo myuser               # 移除用户的 sudo 权限"
    exit 1
    ;;
esac
