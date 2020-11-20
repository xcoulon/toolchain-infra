#!/bin/bash

######################################################################################
## Install the Prometheus Operator on the server defined in $KUBECONFIG
######################################################################################
function install_prometheus_operator() {
  export KUBECONFIG=$KUBECONFIG
  SERVER="$(oc whoami --show-server)"
  export SERVER
  read -p "ℹ️  Install Prometheus Operator on $SERVER in namespace '$NAMESPACE'? (y/n) " -r
  if [[ ! $REPLY =~ ^[Yy]$ ]]
  then
      exit 1
  fi

  # needed before processing the prometheus template
  oc create secret generic \
    --from-file=config.yaml=config/monitoring/kube-rbac-proxy-config.yaml \
    -n "$NAMESPACE" \
    kube-rbac-proxy 

  oc process -f config/monitoring/prometheus.tmpl.yaml \
    -p NAMESPACE="$NAMESPACE" \
    -p SA_NAME=prometheus-k8s \
    | oc apply -f -
  
  # needed by the `kube-rbac-proxy` sidecar to create TokenReviews and SubjectAccessReviews
  oc adm policy add-cluster-role-to-user kube-rbac-proxy -z prometheus-k8s -n "$NAMESPACE"
  
  echo "✅ done installing Prometheus Operator"
  echo ""
}

######################################################################################
## Create a route to Prometheus, so it can be reached by Grafana on the host cluster
######################################################################################
function create_prometheus_route() {
  echo "ℹ️  creating route to Prometheus on Member cluster..."
  oc create route edge prometheus --service=prometheus-operated-secured -n "$NAMESPACE"
  echo "✅ done creating route to Prometheus"
  echo ""
}

######################################################################################
## Main
######################################################################################
if [[ -z ${KUBECONFIG} ]]; then
  echo "Missing 'KUBECONFIG' env var"
  exit 1
elif [[ -z ${NAMESPACE} ]]; then
  echo "Missing 'NAMESPACE' env var"
  exit 1
fi

install_prometheus_operator
create_prometheus_route
