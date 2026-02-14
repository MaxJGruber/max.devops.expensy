#!/bin/bash
kubectl apply -f ./k8s/namespace.yaml
kubectl apply -f ./k8s/secrets.yaml.local
kubectl apply -f ./k8s/mongo-pvc.yaml
kubectl apply -f ./k8s/mongo.yaml
kubectl apply -f ./k8s/redis.yaml
kubectl apply -f ./k8s/backend.yaml
kubectl apply -f ./k8s/frontend.yaml
kubectl apply -f ./k8s/ingress.yaml
kubectl apply -f ./k8s/prometheus.yaml