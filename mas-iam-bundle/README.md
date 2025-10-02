# MAS IAM Bootstrap Operator Bundle

This bundle wraps the upstream Keycloak Operator and applies the supporting
resources (PostgreSQL, secrets, Keycloak CR, realm import, optional OpenLDAP)
so teams can get a MAS-ready Keycloak stack from a single operator install.

## Components

- `bootstrap/` – container image that applies the manifests when the bundle is
  installed. It installs the upstream Keycloak operator subscription in the
  target namespace, then applies the supporting resources.
- `manifests/` – ClusterServiceVersion (CSV) describing the bootstrap operator.
- `metadata/` – bundle metadata consumed by Operator Lifecycle Manager.

## Build Steps

1. Build and push the bootstrap image:
   ```bash
   cd mas-iam-bundle/bootstrap
   podman build -t quay.io/your-org/mas-iam-bootstrap:0.1.0 .
   podman push quay.io/your-org/mas-iam-bootstrap:0.1.0
   ```

2. Update `manifests/mas-iam-operator.clusterserviceversion.yaml` so the
   container image reference matches the tag you pushed (search for
   `quay.io/your-org/mas-iam-bootstrap:0.1.0`). Adjust the maintainer info,
   links, and any passwords in `bootstrap/manifests/*.yaml` to suit your
   environment.

3. Build and push the bundle image:
   ```bash
   cd ..
   podman build -f bundle.Dockerfile -t quay.io/your-org/mas-iam-operator-bundle:0.1.0 .
   podman push quay.io/your-org/mas-iam-operator-bundle:0.1.0
   ```

4. (Optional) Add the bundle to an index image using `opm` if you want to make
   it available via OperatorHub:
   ```bash
   opm index add \
     --bundles quay.io/your-org/mas-iam-operator-bundle:0.1.0 \
     --tag quay.io/your-org/mas-iam-operator-index:0.1.0
   podman push quay.io/your-org/mas-iam-operator-index:0.1.0
   ```

5. On the cluster, create a `CatalogSource` that points at your custom index,
   then install the operator from the console or via a `Subscription`. Choose
   the namespace you want to own the MAS IAM stack (e.g. `mas-iam`) and set the
   install mode to `OwnNamespace`.

Once installed, the bootstrap Deployment runs, installs the upstream Keycloak
operator subscription in the same namespace, and applies the included manifests.
That results in:

- Postgres StatefulSet and secret
- Keycloak CR connected to that Postgres instance
- Realm import CR with the starter MAS realm
- Optional OpenLDAP deployment (adjust or disable as needed)

### Customising Secrets and Passwords

Before building the images, edit the files in `bootstrap/manifests/` to set the
passwords and user names that make sense for your environment. You can also
remove `openldap.yaml` from the directory if you do not want LDAP deployed by
default.

### Adding the SCIM Extension Later

When you build a custom Keycloak image that contains the Metatavu SCIM provider,
update `keycloak.yaml` to set `spec.image` and add a pull secret if required.
Rebuild the bootstrap and bundle images with the new defaults. The operator will
reconcile the Running instance on upgrade, ensuring the new image is applied.
