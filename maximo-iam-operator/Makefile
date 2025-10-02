# VERSION defines the project version for the bundle.
# Update this value when you upgrade the version of your project.
# To re-generate a bundle for another specific version without changing the standard setup, you can:
# - use the VERSION as arg of the bundle target (e.g make bundle VERSION=0.0.2)
# - use environment variables to overwrite this value (e.g export VERSION=0.0.2)
VERSION ?= 0.0.1

# Load .env if present and export its variables to shell commands
ifneq (,$(wildcard $(CURDIR)/../.env))
include $(CURDIR)/../.env
export $(shell sed -n 's/^\([A-Za-z_][A-Za-z0-9_]*\)=.*/\1/p' $(CURDIR)/../.env | tr '\n' ' ')
endif

# Optional override file written by scripts/dev-up.sh to force a computed RELEASE, etc.
ifneq (,$(wildcard $(CURDIR)/../.env.override))
include $(CURDIR)/../.env.override
export $(shell sed -n 's/^\([A-Za-z_][A-Za-z0-9_]*\)=.*/\1/p' $(CURDIR)/../.env.override | tr '\n' ' ')
endif

# Map .env naming to Make variables (fallbacks)
KC_ADMIN_PASSWORD ?= $(KEYCLOAK_ADMIN_PASSWORD)
KC_ADMIN_USER ?= $(KEYCLOAK_ADMIN_USERNAME)
KC_ADMIN_USER ?= admin

# CHANNELS define the bundle channels used in the bundle.
# Add a new line here if you would like to change its default config. (E.g CHANNELS = "candidate,fast,stable")
# To re-generate a bundle for other specific channels without changing the standard setup, you can:
# - use the CHANNELS as arg of the bundle target (e.g make bundle CHANNELS=candidate,fast,stable)
# - use environment variables to overwrite this value (e.g export CHANNELS="candidate,fast,stable")
ifneq ($(origin CHANNELS), undefined)
BUNDLE_CHANNELS := --channels=$(CHANNELS)
endif

# DEFAULT_CHANNEL defines the default channel used in the bundle.
# Add a new line here if you would like to change its default config. (E.g DEFAULT_CHANNEL = "stable")
# To re-generate a bundle for any other default channel without changing the default setup, you can:
# - use the DEFAULT_CHANNEL as arg of the bundle target (e.g make bundle DEFAULT_CHANNEL=stable)
# - use environment variables to overwrite this value (e.g export DEFAULT_CHANNEL="stable")
ifneq ($(origin DEFAULT_CHANNEL), undefined)
BUNDLE_DEFAULT_CHANNEL := --default-channel=$(DEFAULT_CHANNEL)
endif
BUNDLE_METADATA_OPTS ?= $(BUNDLE_CHANNELS) $(BUNDLE_DEFAULT_CHANNEL)

# IMAGE_TAG_BASE defines the docker.io namespace and part of the image name for remote images.
# This variable is used to construct full image tags for bundle and catalog images.
#
# For example, running 'make bundle-build bundle-push catalog-build catalog-push' will build and push both
# lfdev28.io/maximo-iam-operator-bundle:$VERSION and lfdev28.io/maximo-iam-operator-catalog:$VERSION.
IMAGE_TAG_BASE ?= lfdev28.io/maximo-iam-operator

# BUNDLE_IMG defines the image:tag used for the bundle.
# You can use it as an arg. (E.g make bundle-build BUNDLE_IMG=<some-registry>/<project-name-bundle>:<tag>)
BUNDLE_IMG ?= $(IMAGE_TAG_BASE)-bundle:v$(VERSION)

# BUNDLE_GEN_FLAGS are the flags passed to the operator-sdk generate bundle command
BUNDLE_GEN_FLAGS ?= -q --overwrite --version $(VERSION) $(BUNDLE_METADATA_OPTS)

# USE_IMAGE_DIGESTS defines if images are resolved via tags or digests
# You can enable this value if you would like to use SHA Based Digests
# To enable set flag to true
USE_IMAGE_DIGESTS ?= false
ifeq ($(USE_IMAGE_DIGESTS), true)
	BUNDLE_GEN_FLAGS += --use-image-digests
endif

# Set the Operator SDK version to use. By default, what is installed on the system is used.
# This is useful for CI or a project to utilize a specific version of the operator-sdk toolkit.
OPERATOR_SDK_VERSION ?= v1.41.1

# Container tool to use for building and pushing images
CONTAINER_TOOL ?= docker

# Image URL to use all building/pushing image targets
IMG ?= controller:latest

.PHONY: all
all: docker-build

##@ Dev Convenience

# Dev variables (override via environment):
DEV_NS ?= $(if $(NS),$(NS),maximo-iam)
DEV_RELEASE ?= $(if $(RELEASE),$(RELEASE),mas-iam)
SC ?= $(STORAGE_CLASS)

export KC_ADMIN_PASSWORD LDAP_ADMIN_PASSWORD PG_PASSWORD DEV_NS DEV_RELEASE SC

.PHONY: dev-secrets
dev-secrets: ## Create/update required secrets for Keycloak, LDAP and Postgres in DEV_NS
	@[ -n "$$KC_ADMIN_PASSWORD" ] || { echo "ERROR: KC_ADMIN_PASSWORD not set"; exit 1; }
	@[ -n "$$LDAP_ADMIN_PASSWORD" ] || { echo "ERROR: LDAP_ADMIN_PASSWORD not set"; exit 1; }
	@echo "Ensuring namespace $(DEV_NS) exists..."
	@kubectl get ns $(DEV_NS) >/dev/null 2>&1 || kubectl create ns $(DEV_NS)
	@echo "Creating/updating secrets in $(DEV_NS)..."
	@kubectl -n $(DEV_NS) create secret generic mas-iam-kc-admin \
	  --from-literal=admin-password="$$KC_ADMIN_PASSWORD" \
	  --dry-run=client -o yaml | kubectl -n $(DEV_NS) apply -f -
	@kubectl -n $(DEV_NS) create secret generic mas-iam-ldap-admin \
	  --from-literal=LDAP_ADMIN_PASSWORD="$$LDAP_ADMIN_PASSWORD" \
	  --dry-run=client -o yaml | kubectl -n $(DEV_NS) apply -f -

.PHONY: dev-install-crds
dev-install-crds: install ## Install CRDs into the cluster (alias)

.PHONY: dev-apply-cr
dev-apply-cr: ## Apply the sample CR into DEV_NS, patching name/namespace and optional storageClass
	@echo "Applying MaximoIAM CR $(DEV_RELEASE) in namespace $(DEV_NS)..."
	@PYTHONWARNINGS=ignore python3 $(CURDIR)/../scripts/lib/render_maximoiam_cr.py \
	  $(shell pwd)/config/samples/iam_v1alpha1_maximoiam.yaml \
	  $(DEV_RELEASE) $(DEV_NS) $(PG_PASSWORD) $(SC) \
	  | kubectl apply -f -

.PHONY: dev-build-deps
dev-build-deps: ## Build Helm chart dependencies for the keycloak-mas chart (requires helm)
	@if ! command -v helm >/dev/null 2>&1; then \
	  echo "WARNING: helm not found in PATH; skipping 'helm dependency update'. If the operator fails with missing subcharts, install helm and rerun 'make dev-build-deps'"; \
	else \
	  echo "Updating Helm dependencies for helm-charts/keycloak-mas ..."; \
	  cd $(shell pwd)/helm-charts/keycloak-mas && helm dependency update; \
	fi

.PHONY: dev-run-operator
dev-run-operator: helm-operator ## Run helm-operator in background and store PID
	@echo "Starting helm-operator in background..."
	@cd $(shell pwd) && WATCH_NAMESPACE=$(DEV_NS) nohup $(HELM_OPERATOR) run \
	  --watches-file $(shell pwd)/watches.yaml \
	  --leader-elect=false \
	  --metrics-bind-address=:0 \
	  --health-probe-bind-address=:0 \
	  > .dev-operator.out 2>&1 & echo $$! > .dev-operator.pid && echo "PID: $$(cat .dev-operator.pid)"

.PHONY: dev-down
dev-down: ## Stop background helm-operator started by dev-run-operator
	@PID=$$(cat .dev-operator.pid 2>/dev/null || true); \
	if [ -n "$$PID" ]; then \
	  echo "Stopping helm-operator (PID $$PID)..."; \
	  kill $$PID || true; \
	  rm -f .dev-operator.pid; \
	else \
	  echo "No .dev-operator.pid found"; \
	fi

.PHONY: dev-status
dev-status: ## Print status: Deployments, StatefulSets, Pods, Services, PVCs, and Route
	@echo "Deployments:" && kubectl -n $(DEV_NS) get deploy -l app.kubernetes.io/instance=$(DEV_RELEASE) || true
	@echo "StatefulSets:" && kubectl -n $(DEV_NS) get sts -l app.kubernetes.io/instance=$(DEV_RELEASE) || true
	@echo "Pods:" && kubectl -n $(DEV_NS) get po -l app.kubernetes.io/instance=$(DEV_RELEASE) || true
	@echo "Services:" && kubectl -n $(DEV_NS) get svc -l app.kubernetes.io/instance=$(DEV_RELEASE) || true
	@echo "PVCs:" && kubectl -n $(DEV_NS) get pvc -l app.kubernetes.io/instance=$(DEV_RELEASE) || true
	@echo "Route:" && (oc -n $(DEV_NS) get route $(DEV_RELEASE)-keycloak-mas-keycloak -o jsonpath='{.spec.host}' 2>/dev/null || true; echo)
	@echo "KC admin user: $${KC_ADMIN_USER:-admin}"

.PHONY: dev-wait
dev-wait: ## Wait for LDAP PVC, Postgres and Keycloak readiness, then print route
	@$(CURDIR)/../scripts/dev-wait.sh

.PHONY: dev-clean
dev-clean: ## Remove CR and labeled resources for DEV_RELEASE in DEV_NS (keeps secrets)
	@echo "Deleting MaximoIAM $(DEV_RELEASE) in $(DEV_NS) ..."
	@kubectl -n $(DEV_NS) delete maximoiam $(DEV_RELEASE) --ignore-not-found --wait=true || true
	@echo "Deleting release-labeled resources ..."
	@kubectl -n $(DEV_NS) delete all,cm,job,svc,pvc -l app.kubernetes.io/instance=$(DEV_RELEASE) --ignore-not-found || true
	@# Delete OpenShift routes if present
	@which oc >/dev/null 2>&1 && oc -n $(DEV_NS) delete route -l app.kubernetes.io/instance=$(DEV_RELEASE) --ignore-not-found || true
	@echo "Deleting Helm release metadata (secrets/configmaps)..."
	@kubectl -n $(DEV_NS) delete secret -l owner=helm,name=$(DEV_RELEASE) --ignore-not-found || true
	@kubectl -n $(DEV_NS) delete cm -l owner=helm,name=$(DEV_RELEASE) --ignore-not-found || true
	@REL=$(DEV_RELEASE); NS=$(DEV_NS); \
	SECS=$$(kubectl -n $$NS get secret -o name 2>/dev/null | grep -E "^secret/sh\.helm\.release\.v[0-9]+\.$$REL\.[0-9]+$$" || true); \
	CMSG=$$(kubectl -n $$NS get cm -o name 2>/dev/null | grep -E "^configmap/sh\.helm\.release\.v[0-9]+\.$$REL\.[0-9]+$$" || true); \
	if [ -n "$$SECS$$CMSG" ]; then kubectl -n $$NS delete $$SECS $$CMSG --ignore-not-found || true; fi
	@echo "Deleting known resource names (fallback) ..."
	@kubectl -n $(DEV_NS) delete deploy/$(DEV_RELEASE)-keycloak-mas-ldap svc/$(DEV_RELEASE)-keycloak-mas-ldap pvc/$(DEV_RELEASE)-keycloak-mas-ldap cm/$(DEV_RELEASE)-keycloak-mas-ldap-seed cm/$(DEV_RELEASE)-keycloak-mas-realm cm/$(DEV_RELEASE)-keycloak-env-vars job/$(DEV_RELEASE)-keycloak-mas-realm-import --ignore-not-found || true
	@kubectl -n $(DEV_NS) delete svc/$(DEV_RELEASE)-keycloak --ignore-not-found || true
	@which oc >/dev/null 2>&1 && oc -n $(DEV_NS) delete route $(DEV_RELEASE)-keycloak-mas-keycloak --ignore-not-found || true
	@echo "Note: secrets preserved (mas-iam-kc-admin, mas-iam-ldap-admin)"

.PHONY: dev-up
dev-up: dev-secrets dev-install-crds dev-build-deps dev-apply-cr dev-run-operator dev-status dev-wait ## Create secrets, install CRDs, build deps, apply CR, start operator, wait

##@ General

# The help target prints out all targets with their descriptions organized
# beneath their categories. The categories are represented by '##@' and the
# target descriptions by '##'. The awk commands is responsible for reading the
# entire set of makefiles included in this invocation, looking for lines of the
# file as xyz: ## something, and then pretty-format the target and help. Then,
# if there's a line with ##@ something, that gets pretty-printed as a category.
# More info on the usage of ANSI control characters for terminal formatting:
# https://en.wikipedia.org/wiki/ANSI_escape_code#SGR_parameters
# More info on the awk command:
# http://linuxcommand.org/lc3_adv_awk.php

.PHONY: help
help: ## Display this help.
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

##@ Build

.PHONY: run
run: helm-operator ## Run against the configured Kubernetes cluster in ~/.kube/config
	$(HELM_OPERATOR) run

.PHONY: docker-build
docker-build: ## Build docker image with the manager.
	$(CONTAINER_TOOL) build -t ${IMG} .

.PHONY: docker-push
docker-push: ## Push docker image with the manager.
	$(CONTAINER_TOOL) push ${IMG}

# PLATFORMS defines the target platforms for  the manager image be build to provide support to multiple
# architectures. (i.e. make docker-buildx IMG=myregistry/mypoperator:0.0.1). To use this option you need to:
# - able to use docker buildx . More info: https://docs.docker.com/build/buildx/
# - have enable BuildKit, More info: https://docs.docker.com/develop/develop-images/build_enhancements/
# - be able to push the image for your registry (i.e. if you do not inform a valid value via IMG=<myregistry/image:<tag>> than the export will fail)
# To properly provided solutions that supports more than one platform you should use this option.
PLATFORMS ?= linux/arm64,linux/amd64,linux/s390x,linux/ppc64le
.PHONY: docker-buildx
docker-buildx: ## Build and push docker image for the manager for cross-platform support
	- $(CONTAINER_TOOL) buildx create --name project-v3-builder
	$(CONTAINER_TOOL) buildx use project-v3-builder
	- $(CONTAINER_TOOL) buildx build --push --platform=$(PLATFORMS) --tag ${IMG} -f Dockerfile .
	- $(CONTAINER_TOOL) buildx rm project-v3-builder

##@ Deployment

.PHONY: install
install: kustomize ## Install CRDs into the K8s cluster specified in ~/.kube/config.
	$(KUSTOMIZE) build config/crd | kubectl apply -f -

.PHONY: uninstall
uninstall: kustomize ## Uninstall CRDs from the K8s cluster specified in ~/.kube/config.
	$(KUSTOMIZE) build config/crd | kubectl delete -f -

.PHONY: deploy
deploy: kustomize ## Deploy controller to the K8s cluster specified in ~/.kube/config.
	cd config/manager && $(KUSTOMIZE) edit set image controller=${IMG}
	$(KUSTOMIZE) build config/default | kubectl apply -f -

.PHONY: undeploy
undeploy: ## Undeploy controller from the K8s cluster specified in ~/.kube/config.
	$(KUSTOMIZE) build config/default | kubectl delete -f -

OS := $(shell uname -s | tr '[:upper:]' '[:lower:]')
ARCH := $(shell uname -m | sed 's/x86_64/amd64/' | sed 's/aarch64/arm64/')

.PHONY: kustomize
KUSTOMIZE = $(shell pwd)/bin/kustomize
kustomize: ## Download kustomize locally if necessary.
ifeq (,$(wildcard $(KUSTOMIZE)))
ifeq (,$(shell which kustomize 2>/dev/null))
	@{ \
	set -e ;\
	mkdir -p $(dir $(KUSTOMIZE)) ;\
	curl -sSLo - https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize/v5.6.0/kustomize_v5.6.0_$(OS)_$(ARCH).tar.gz | \
	tar xzf - -C bin/ ;\
	}
else
KUSTOMIZE = $(shell which kustomize)
endif
endif

.PHONY: helm-operator
HELM_OPERATOR = $(shell pwd)/bin/helm-operator
helm-operator: ## Download helm-operator locally if necessary, preferring the $(pwd)/bin path over global if both exist.
ifeq (,$(wildcard $(HELM_OPERATOR)))
ifeq (,$(shell which helm-operator 2>/dev/null))
	@{ \
	set -e ;\
	mkdir -p $(dir $(HELM_OPERATOR)) ;\
	curl -sSLo $(HELM_OPERATOR) https://github.com/operator-framework/operator-sdk/releases/download/v1.41.1/helm-operator_$(OS)_$(ARCH) ;\
	chmod +x $(HELM_OPERATOR) ;\
	}
else
HELM_OPERATOR = $(shell which helm-operator)
endif
endif

.PHONY: operator-sdk
OPERATOR_SDK ?= $(LOCALBIN)/operator-sdk
operator-sdk: ## Download operator-sdk locally if necessary.
ifeq (,$(wildcard $(OPERATOR_SDK)))
ifeq (, $(shell which operator-sdk 2>/dev/null))
	@{ \
	set -e ;\
	mkdir -p $(dir $(OPERATOR_SDK)) ;\
	curl -sSLo $(OPERATOR_SDK) https://github.com/operator-framework/operator-sdk/releases/download/$(OPERATOR_SDK_VERSION)/operator-sdk_$(OS)_$(ARCH) ;\
	chmod +x $(OPERATOR_SDK) ;\
	}
else
OPERATOR_SDK = $(shell which operator-sdk)
endif
endif


.PHONY: bundle
bundle: kustomize operator-sdk ## Generate bundle manifests and metadata, then validate generated files.
	$(OPERATOR_SDK) generate kustomize manifests -q
	cd config/manager && $(KUSTOMIZE) edit set image controller=$(IMG)
	$(KUSTOMIZE) build config/manifests | $(OPERATOR_SDK) generate bundle $(BUNDLE_GEN_FLAGS)
	$(OPERATOR_SDK) bundle validate ./bundle

.PHONY: bundle-build
bundle-build: ## Build the bundle image.
	$(CONTAINER_TOOL) build -f bundle.Dockerfile -t $(BUNDLE_IMG) .

.PHONY: bundle-push
bundle-push: ## Push the bundle image.
	$(MAKE) docker-push IMG=$(BUNDLE_IMG)

.PHONY: opm
OPM = $(LOCALBIN)/opm
opm: ## Download opm locally if necessary.
ifeq (,$(wildcard $(OPM)))
ifeq (,$(shell which opm 2>/dev/null))
	@{ \
	set -e ;\
	mkdir -p $(dir $(OPM)) ;\
	curl -sSLo $(OPM) https://github.com/operator-framework/operator-registry/releases/download/v1.55.0/$(OS)-$(ARCH)-opm ;\
	chmod +x $(OPM) ;\
	}
else
OPM = $(shell which opm)
endif
endif

# A comma-separated list of bundle images (e.g. make catalog-build BUNDLE_IMGS=example.com/operator-bundle:v0.1.0,example.com/operator-bundle:v0.2.0).
# These images MUST exist in a registry and be pull-able.
BUNDLE_IMGS ?= $(BUNDLE_IMG)

# The image tag given to the resulting catalog image (e.g. make catalog-build CATALOG_IMG=example.com/operator-catalog:v0.2.0).
CATALOG_IMG ?= $(IMAGE_TAG_BASE)-catalog:v$(VERSION)

# Set CATALOG_BASE_IMG to an existing catalog image tag to add $BUNDLE_IMGS to that image.
ifneq ($(origin CATALOG_BASE_IMG), undefined)
FROM_INDEX_OPT := --from-index $(CATALOG_BASE_IMG)
endif

# Build a catalog image by adding bundle images to an empty catalog using the operator package manager tool, 'opm'.
# This recipe invokes 'opm' in 'semver' bundle add mode. For more information on add modes, see:
# https://github.com/operator-framework/community-operators/blob/7f1438c/docs/packaging-operator.md#updating-your-existing-operator
.PHONY: catalog-build
catalog-build: opm ## Build a catalog image.
	$(OPM) index add --container-tool $(CONTAINER_TOOL) --mode semver --tag $(CATALOG_IMG) --bundles $(BUNDLE_IMGS) $(FROM_INDEX_OPT)

# Push the catalog image.
.PHONY: catalog-push
catalog-push: ## Push a catalog image.
	$(MAKE) docker-push IMG=$(CATALOG_IMG)
