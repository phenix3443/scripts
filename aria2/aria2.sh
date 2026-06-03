#!/bin/bash

install() {
    helm repo add panghuli https://charts.panghuli.cn &&
        helm repo update &&
        helm upgrade aria2 panghuli/aria2 -f aria2/values.yaml --namespace home-lab --install --create-namespace

}

uninstall() {
    helm uninstall aria2 --namespace home-lab
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
