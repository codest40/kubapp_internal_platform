#!/bin/bash

echo ">> Deleting ApplicationSets..."
kubectl delete applicationsets.argoproj.io --all -n argocd --ignore-not-found || true

########################################
# 2. DELETE ARGOCD APPLICATIONS
########################################
echo ">> Deleting Argo Applications..."
kubectl delete applications.argoproj.io --all -n argocd --ignore-not-found || true
