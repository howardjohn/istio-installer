#!/bin/bash

set -o errexit
set -o nounset
set -o pipefail
set -x

OUT=$(mktemp -d /tmp/istio-release.XXXXX)
TMP=$(mktemp -d /tmp/istio-build.XXXXX)

MANIFEST_DIR="${OUT}/manifests"
HELM_DIR="${OUT}/helm"
DEMO_DIR="${OUT}/demo"

function make_manifests() {
    mkdir -p "${MANIFEST_DIR}"
    for component in crds istio-control istio-cni gateways istiocoredns istio-policy istio-telemetry security; do
        cp -r $component $MANIFEST_DIR/$component
    done
    cp global.yaml $MANIFEST_DIR/global.yaml
}

function update_version() {
    RELEASE_VERSION=$1
    RELEASE_HUB=$2
    # Update version string in yaml files.
    current_tag=1.1.0

    find ${MANIFEST_DIR} -type f -exec sed -i "s|hub: gcr.io/istio-release|hub: ${RELEASE_HUB}|g" {} \;
    find ${MANIFEST_DIR} -type f -exec sed -i "s|tag: .*-latest-daily|tag: ${RELEASE_VERSION}|g" {} \;
    find ${MANIFEST_DIR} -type f -exec sed -i "s/tag: ${current_tag}/tag: ${RELEASE_VERSION}/g" {} \;
    find ${MANIFEST_DIR} -type f -exec sed -i "s/version: ${current_tag}/version: ${RELEASE_VERSION}/g" {} \;
    find ${MANIFEST_DIR} -type f -exec sed -i "s/appVersion: ${current_tag}/appVersion: ${RELEASE_VERSION}/g" {} \;
}

function make_helm() {
    mkdir -p ${HELM_DIR}

    CHARTS=($(find ${MANIFEST_DIR} -name Chart.yaml | grep -v test))

    for CHART_PATH in "${CHARTS[@]}"; do
        DIR=$(dirname "$CHART_PATH")
        helm package "$DIR" -d "$HELM_DIR"
    done

    helm repo index "$HELM_DIR"
}

function make_demo() {
    mkdir -p ${DEMO_DIR}
    mkdir -p ${TMP}/release/demo/
    # TODO we actually did need the citadel stuff in demo
    cp -r test/demo/* ${DEMO_DIR}
    DEMO_OPTS="-f test/demo/values.yaml"
	bin/iop istio-system istio-citadel ${MANIFEST_DIR}/security/citadel -t ${DEMO_OPTS} > ${TMP}/release/demo/istio-citadel.yaml
	bin/iop istio-system istio-config ${MANIFEST_DIR}/istio-control/istio-config -t ${DEMO_OPTS} > ${TMP}/release/demo/istio-config.yaml
	bin/iop istio-system istio-discovery ${MANIFEST_DIR}/istio-control/istio-discovery -t ${DEMO_OPTS} > ${TMP}/release/demo/istio-discovery.yaml
	bin/iop istio-system istio-autoinject ${MANIFEST_DIR}/istio-control/istio-autoinject -t ${DEMO_OPTS} > ${TMP}/release/demo/istio-autoinject.yaml
	bin/iop istio-system istio-ingress ${MANIFEST_DIR}/gateways/istio-ingress -t ${DEMO_OPTS} > ${TMP}/release/demo/istio-ingress.yaml
	bin/iop istio-system istio-egress ${MANIFEST_DIR}/gateways/istio-egress -t ${DEMO_OPTS} > ${TMP}/release/demo/istio-egress.yaml
	bin/iop istio-system istio-telemetry ${MANIFEST_DIR}/istio-telemetry/mixer-telemetry -t ${DEMO_OPTS} > ${TMP}/release/demo/istio-telemetry.yaml
	bin/iop istio-system istio-telemetry ${MANIFEST_DIR}/istio-telemetry/prometheus -t ${DEMO_OPTS} > ${TMP}/release/demo/istio-prometheus.yaml
	bin/iop istio-system istio-telemetry ${MANIFEST_DIR}/istio-telemetry/grafana -t ${DEMO_OPTS} > ${TMP}/release/demo/istio-grafana.yaml
	#bin/iop istio-system istio-policy ${MANIFEST_DIR}/istio-policy -t > ${TMP}/release/demo/istio-policy.yaml
	cat ${TMP}/release/demo/*.yaml > ${DEMO_DIR}/k8s.yaml
}

make_manifests
update_version 1.2.2 docker.io/istio
make_demo
make_helm

tree "${OUT}" -d
