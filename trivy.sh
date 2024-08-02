#!/bin/bash
set -e
#PUSHGATEWAY=""
CLUSTER="$1"
NS_LIST="$2"
NS_EXCLUDES="istio-|rancher-|cattle-|rook-ceph|gitlab-managed|kube-system"
SEVERITY="HIGH,CRITICAL"
test -n "$NS_LIST" || NS_LIST="$(kubectl get ns -o json|jq -r '.items[].metadata.name'|grep -v -E "$NS_EXCLUDES")"
echo "" > metrics.txt
# push_metrics $1
# $1 - path to a prometheus-compatible metrics-file
push_metrics() {
  if [[ -n "${PUSHGATEWAY}" ]] && [[ -f "$1" ]]; then
    echo -e "\n\n# removing all metrics"
    curl --silent --write-out "%{http_code}" -X DELETE "${PUSHGATEWAY}/metrics/job/trivy_scan/instance/$CLUSTER"
    sleep 2s
    echo -e "\n\n# pushing metrics to ${PUSHGATEWAY}"
    echo -e "\n cat $1 | curl --silent --write-out %{http_code} --data-binary @- ${PUSHGATEWAY}/metrics/job/trivy_scan/instance/$CLUSTER"
    set +e
    response=$( cat "$1" | curl --silent --write-out "%{http_code}" --data-binary @- "${PUSHGATEWAY}/metrics/job/trivy_scan/instance/$CLUSTER")
    set -e
    if [[ "$response" -ne 200 ]]; then
      echo -e "  - FAILED, is the Pushgateway available? (response: $response )"
      echo -e "    NOT FATAL, continuing... "
      echo -e "   ( if this happens repeatedly, ask your friendly neighbourhood sysadmin)"
    fi
    echo -e "  - done, continuing... "
  else
    echo "  - Pushgateway NOT defined, just saying...!"
  fi
}
install_trivy() {
  # Have to pin the trivy version until https://github.com/aquasecurity/trivy/issues/1424 is fixed
  # VERSION=$(
  #   curl --silent "https://api.github.com/repos/aquasecurity/trivy/releases/latest" | \
  #   grep '"tag_name":' | \
  #   sed -E 's/.*"v([^"]+)".*/\1/'
  # )
  VERSION="0.36.1"
  wget -O /tmp/trivy_${VERSION}_Linux-64bit.tar.gz https://github.com/aquasecurity/trivy/releases/download/v${VERSION}/trivy_${VERSION}_Linux-64bit.tar.gz
  tar zxvf /tmp/trivy_${VERSION}_Linux-64bit.tar.gz -C /tmp/
  mv /tmp/trivy /usr/local/bin/
}
check_images() {
  for namespace in $NS_LIST; do
    echo "# namespace: $namespace"
    IMAGE_LIST="$(kubectl get pods -n ${namespace} -o json|jq -r '.items[] | "\(.spec.containers[].image)"' | sort -u)"
    mkdir -p "./public/${CLUSTER}"
    for image in $IMAGE_LIST; do
      IMAGE="${image//;*/}"
      case "$IMAGE" in
        "$CI_REGISTRY"*)
          export TRIVY_USERNAME="$CI_REGISTRY_USER"
          export TRIVY_PASSWORD="$CI_REGISTRY_PASSWORD"
          export TRIVY_AUTH_URL="$CI_REGISTRY"
          ;;
        *)
          unset TRIVY_USERNAME
          unset TRIVY_PASSWORD
          unset TRIVY_AUTH_URL
          ;;
      esac
      # print to file
      trivy image \
        --ignore-unfixed \
        --exit-code 0 \
        --severity $SEVERITY \
        --ignorefile .trivyinore_${namespace} \
        --format template --template "@./contrib/html.tpl" \
        $IMAGE \
      >> "./public/${CLUSTER}_${namespace}.html";
        COUNT="$(
          trivy image \
            --ignore-unfixed \
            --exit-code 0 \
            --format table \
            --severity $SEVERITY \
            --ignorefile .trivyinore_${namespace} \
            $IMAGE \
          |grep "^Total"\
          |sed -E 's/Total: ([0-9]+) (.*)/ \1 /g'
        )"
        FINAL_COUNT=0
        for n in $COUNT; do
          FINAL_COUNT=$(( $FINAL_COUNT+$n ))
        done
      echo "trivy_container_issues{CLUSTER=\"${CLUSTER}\", namespace=\"${namespace}\", image=\"$IMAGE\"} $FINAL_COUNT" >> "./public/${CLUSTER}/metrics.txt"
      echo "#   - $IMAGE -> $FINAL_COUNT"
    done
  done
}
which trivy || install_trivy
check_images