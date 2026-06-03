#!/bin/bash

brew install minikube &&
    minikube start --addons=metrics-server,dashboard,ingress --apiserver-name='minikubeAPI' --cni=calico --nodes=3
