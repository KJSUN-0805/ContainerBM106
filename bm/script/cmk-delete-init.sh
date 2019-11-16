#!/bin/bash

#k taint node bm-pg node-role.kubernetes.io/master-
kubectl -n cmk-namespace delete pod cmk-cluster-init-pod

kubectl taint node bm-pg cmk-
kubectl taint node bm-wk cmk-

kubectl -n cmk-namespace delete pod cmk-init-install-discover-pod-bm-pg cmk-init-install-discover-pod-bm-wk
kubectl -n cmk-namespace delete daemonset cmk-reconcile-nodereport-ds-bm-pg cmk-reconcile-nodereport-ds-bm-wk
kubectl -n cmk-namespace delete deploy cmk-webhook-deployment
kubectl -n cmk-namespace delete Secret cmk-webhook-certs
kubectl -n cmk-namespace delete configmaps cmk-webhook-configmap
kubectl -n cmk-namespace delete MutatingWebhookConfiguration cmk-webhook-config
kubectl -n cmk-namespace delete svc cmk-webhook-service
kubectl -n cmk-namespace delete pod cmk-init-pod cmk-install-pod cmk-isolate-pod

rm -rf /etc/cmk/*
rsync -avz --delete /etc/cmk bm-wk:/etc

