# Upstream Keycloak Operator Deployment (MAS IAM Toolkit)

This attempt trades the custom Helm-based operator for the upstream **Keycloak Operator** that Red Hat already maintains. The goal is to let teammates install a single operator, apply a small set of manifests, and obtain a Keycloak instance pre-loaded with your MAS realm configuration. LDAP integration can be layered on later once the core flow is healthy.

## High-Level Flow

1. **Install the Keycloak Operator** into a dedicated namespace (for example `mas-iam`), either through the OpenShift console or via `Subscription` manifests.
2. **Provision PostgreSQL** in the same namespace. This can be any managed DB; to keep things self-contained we ship a minimal StatefulSet manifest using the upstream `postgres` image.
3. **Create the database secret** (`mas-iam-db`) that holds the admin credentials Keycloak will use.
4. **Apply the `Keycloak` custom resource** that the operator watches. This spins up the Keycloak pods, wires in the DB credentials, and exposes a service/route.
5. **Import the MAS realm** using a `KeycloakRealmImport` CR. The operator reads the supplied JSON and applies it to the server once it’s ready.

The manifests in this folder are intentionally simple so you can tweak names without dealing with templating logic.

## Repository Layout

```
keycloak-upstream-operator/
├── README.md
└── manifests/
    ├── 00-namespace.yaml
    ├── 01-operator-subscription.yaml
    ├── 10-postgres.yaml
    ├── 11-postgres-secret.yaml
    ├── 20-keycloak.yaml
    ├── 30-realm-import.yaml
    └── 40-openldap.yaml
```

* `00-namespace.yaml` – creates/labels the target namespace.
* `01-operator-subscription.yaml` – optional helper for installing the operator through OLM (OpenShift). Skip if you prefer the web console.
* `10-postgres.yaml` – barebones StatefulSet + Service for PostgreSQL.
* `11-postgres-secret.yaml` – credentials consumed by both PostgreSQL and Keycloak.
* `20-keycloak.yaml` – the actual `Keycloak` CR.
* `30-realm-import.yaml` – imports your MAS realm. Start with a minimal realm until you’re ready to port the full JSON.
* `40-openldap.yaml` – simple OpenLDAP deployment + service. Swap in your production-ready manifests when needed.

## Usage

```bash
# 1. Create namespace and (optionally) install the operator subscription
kubectl apply -f manifests/00-namespace.yaml
kubectl apply -f manifests/01-operator-subscription.yaml

# 2. Deploy PostgreSQL + credentials
kubectl apply -f manifests/11-postgres-secret.yaml
kubectl apply -f manifests/10-postgres.yaml

# 3. Deploy Keycloak through the operator
kubectl apply -f manifests/20-keycloak.yaml

# 4. Import the realm once Keycloak pods are ready
kubectl apply -f manifests/30-realm-import.yaml

# 5. (Optional) Bring up OpenLDAP
kubectl apply -f manifests/40-openldap.yaml
```

> **Tip:** On OpenShift you can replace `kubectl` with `oc`. The operator will create a `Route` automatically when the `Keycloak` CR sets `spec.hostname`. You can also expose it manually via `oc create route edge keycloak --service mas-iam-keycloak-service`.

## Customisation Points

- **Namespace / names:** update `metadata.name` and `metadata.namespace` consistently across the manifests.
- **Database sizing:** adjust storage size and resources in `10-postgres.yaml` or replace it with your preferred Postgres Helm chart.
- **Secrets:** if you already manage secrets elsewhere (e.g. Vault, ExternalSecrets), point the `Keycloak.spec.db.*Secret` fields at those secrets instead.
- **TLS:** for production bring your own TLS cert and populate `spec.http.tlsSecret` in the `Keycloak` CR.
- **Realm JSON:** swap the stub JSON in `30-realm-import.yaml` with your full MAS realm file once you’ve validated the path.

## Next Steps

### Short term

- Validate that Keycloak comes up via the upstream operator (watch the `Keycloak` CR until it reports Ready).
- Apply the realm import and confirm MAS login flows or admin logins behave as expected.
- (Optional) Deploy the simple OpenLDAP manifest in this folder or replace it with your preferred chart/operator.

### Planning for SCIM (later)

To use the [Metatavu/keycloak-scim-server](https://github.com/Metatavu/keycloak-scim-server) extension once the basics are stable:

1. Build a custom Keycloak image that layers the SCIM provider artifacts onto the supported Red Hat base image (for example `registry.redhat.io/keycloak/keycloak-rhel9`).
2. Push the image to your registry and update `manifests/20-keycloak.yaml` (`spec.image`) to point at it. Add `spec.imagePullSecrets` if the registry requires authentication.
3. Provide the SCIM configuration (JSON/YAML) either baked into the image or mounted via ConfigMap/Secret.
4. Expose the SCIM endpoints through the existing route/service and map any required service accounts in your realm JSON.

Once those pieces are in place you can extend the realm import with SCIM-specific clients or roles, keeping the operator-driven workflow intact.

## Packaging for one-click installs

Once you like the defaults, build the wrapper bundle in `mas-iam-bundle/`.
That bundle bakes the upstream operator subscription and the manifests into a
bootstrap Deployment so teammates only need to install a single operator from
OperatorHub. See `mas-iam-bundle/README.md` for build and publishing steps.
