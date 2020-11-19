#!/bin/bash

######################################################################################
## Install the Prometheus Operator on the server defined in $KUBECONFIG
######################################################################################
function install_prometheus_operator() {
  echo "ℹ️  installing Prometheus Operator on Member cluster in namespace '$TOOLCHAIN_MEMBER_OPERATOR_NS'..."
  export KUBECONFIG=$KUBECONFIG_MEMBER
  SERVER="$(oc whoami --show-server)"
  export SERVER
  read -p "connecting to $SERVER (Y/n)? " -r
  if [[ ! $REPLY =~ ^[Yy]$ ]]
  then
      exit 1
  fi

  oc process -f config/monitoring/prometheus.tmpl.yaml \
    -p NAMESPACE="$TOOLCHAIN_MEMBER_OPERATOR_NS" \
    -p SA_NAME=prometheus-k8s \
    | oc apply -f -

  # approve the install plan, stick to Prometheus version 0.32 for now
  oc patch "$(oc get installplan -l operators.coreos.com/prometheus.$TOOLCHAIN_MEMBER_OPERATOR_NS -o name)" --type='merge' -p '{"spec":{"approved":true}}'

  # at this point, there should be some new pods in the `toolchain-$CLUSTER-monitoring` namespace
  oc wait --for condition=Ready pods -l app=prometheus -n "$TOOLCHAIN_MEMBER_OPERATOR_NS"
  echo "✅ done installing Prometheus Operator"
  echo ""
}

######################################################################################
## Create a route to Prometheus, so it can be reached by Grafana on the host cluster
######################################################################################
function create_prometheus_route() {
  echo "ℹ️  creating route to Prometheus on Member cluster..."
  oc create route edge prometheus --service=prometheus-operated -n "$TOOLCHAIN_MEMBER_OPERATOR_NS"
  echo "✅ done creating route to Prometheus"
  echo ""
}

######################################################################################
## Main
######################################################################################
if [[ -z ${KUBECONFIG_MEMBER} ]]; then
  echo "Missing 'KUBECONFIG_MEMBER' env var"
  exit 1
elif [[ -z ${TOOLCHAIN_MEMBER_OPERATOR_NS} ]]; then
  echo "Missing 'TOOLCHAIN_MEMBER_OPERATOR_NS' env var"
  exit 1
fi

install_prometheus_operator
create_prometheus_route
