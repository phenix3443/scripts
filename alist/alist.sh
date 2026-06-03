#!/bin/bash

install() {
    echo "create database..."
    helm repo add panghuli https://charts.panghuli.cn &&
        helm repo update &&
        helm upgrade alist panghuli/alist -f alist/values.yaml --namespace home-lab --install --create-namespace

}

uninstall() {
    helm uninstall alist --namespace home-lab
}

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
