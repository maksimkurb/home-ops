#!/bin/bash


for namespace in `kubectl get ns -o name | awk -F '/' '{print $2}'`
do
  for ingress in `kubectl -n $namespace get ingress -o name | awk -F '/' '{print $2}'`
  do
    echo "Working on $ingress in $namespace"
    kubectl -n $namespace annotate ingress $ingress temp/updated="true"
    kubectl -n $namespace annotate ingress $ingress temp/updated-
  done
done
