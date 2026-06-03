#!/bin/bash

install() {
    helm repo add panghuli https://charts.panghuli.cn &&
        helm repo update &&
        helm upgrade cloudreve panghuli/cloudreve -f cloudreve/values.yaml --namespace home-lab --install --create-namespace
}

uninstall() {
    helm uninstall cloudreve --namespace home-lab
}

# 根据参数执行相应操作
case $1 in
install)
    install
    ;;
uninstall)
    uninstall
    ;;
*)
    echo "Usage: $0 [install|uninstall]"
    exit 1
    ;;
esac
