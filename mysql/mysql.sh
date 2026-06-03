#!/bin/bash

install() {
    helm upgrade mysql oci://registry-1.docker.io/bitnamicharts/mysql -f mysql/values.yaml --namespace home-lab --install --create-namespace
}
uninstall() {
    helm uninstall mysql --namespace home-lab
}

create_DB() {
    export MYSQL_ROOT_PASSWORD=$(kubectl get secret --namespace home-lab mysql -o jsonpath="{.data.mysql-root-password}" | base64 -d)
    kubectl run mysql-client --rm --tty -i --restart='Never' --image docker.io/bitnami/mysql:8.0.37-debian-12-r0 --namespace home-lab --env MYSQL_ROOT_PASSWORD="$MYSQL_ROOT_PASSWORD" --command -- bash
    mysql -h mysql.home-lab.svc.cluster.local -uroot -p"$MYSQL_ROOT_PASSWORD"
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
