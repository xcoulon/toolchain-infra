#!/bin/bash

######################################################################################
## Install the Prometheus Operator on the server defined in $KUBECONFIG
######################################################################################
function install_prometheus_operator() {
  export KUBECONFIG=$KUBECONFIG
  SERVER="$(oc whoami --show-server)"
  export SERVER
  read -p "ℹ️  Install Prometheus Operator on $SERVER in namespace '$TOOLCHAIN_MONITORING_NS'? (y/n) " -r
  if [[ ! $REPLY =~ ^[Yy]$ ]]
  then
      exit 1
  fi

  oc create secret generic --from-file=config.yaml=config/monitoring/kube-rbac-proxy.config.yaml kube-rbac-proxy 
  oc process -f config/monitoring/prometheus.tmpl.yaml \
    -p PROMETHEUS_OPERATOR_NS="$TOOLCHAIN_MONITORING_NS" \
    -p SA_NAME=prometheus-k8s \
    | oc apply -f -

  echo "✅ done installing Prometheus Operator"
  echo ""
}

######################################################################################
## Create a route to Prometheus, so it can be reached by Grafana on the host cluster
######################################################################################
function create_prometheus_route() {
  echo "ℹ️  creating route to Prometheus on Member cluster..."
  oc create route edge prometheus --service=prometheus-operated-secured -n "$TOOLCHAIN_MONITORING_NS"
  echo "✅ done creating route to Prometheus"
  echo ""
}

######################################################################################
## Main
######################################################################################
if [[ -z ${KUBECONFIG} ]]; then
  echo "Missing 'KUBECONFIG' env var"
  exit 1
elif [[ -z ${TOOLCHAIN_MONITORING_NS} ]]; then
  echo "Missing 'TOOLCHAIN_MONITORING_NS' env var"
  exit 1
fi

install_prometheus_operator
create_prometheus_route
