# RHBK Helm Deployment with LDAPS + Realm Seeding

This runbook covers Phase 1: deploying the Red Hat build of Keycloak (RHBK) on OpenShift via Helm, wiring it to an OpenLDAP instance over LDAPS, performing a one-time manual realm configuration, exporting that realm, and enabling import-at-start for subsequent installs.

## Prerequisites
- OpenShift or Kubernetes cluster with cluster-admin (or suitable namespace-admin) access
- CLI tools: `helm` 3.8+, `kubectl`/`oc`, `jq`, `podman` (for cert tooling), `mkcert`
- Local scripts from this repo (do **not** delete or modify `Local/Scripts/generate-certs.sh`)
- Entitlement to pull `registry.redhat.io/rhbk/keycloak-rhel9` (via an image pull secret)

## 1. Generate TLS Materials and Truststores
Run the provided helper to mint local CA, server certs, and the Keycloak truststore (idempotent):

```bash
pushd Local
./Scripts/generate-certs.sh
popd
```

Create Kubernetes secrets in the deployment namespace (`KEYCLOAK_NS`) using the generated artifacts:

```bash
# Truststore for LDAPS
kubectl -n ${KEYCLOAK_NS} create secret generic keycloak-truststore \
  --from-file=truststore.jks=./Local/certs/keycloak/truststore.jks \
  --from-literal=truststore-password='changeit'

# LDAP bind password (replace value with actual secret)
kubectl -n ${KEYCLOAK_NS} create secret generic ldap-bind \
  --from-literal=LDAP_ADMIN_PASSWORD='REDACTED'

# Optional: LDAP CA bundle if Keycloak should mount it separately
kubectl -n ${KEYCLOAK_NS} create secret generic ldap-ca \
  --from-file=ca.crt=./Local/certs/ldap/ca.crt
```

Image pull secret example (entitlement):

```bash
kubectl -n ${KEYCLOAK_NS} create secret docker-registry rh-registry-creds \
  --docker-server=registry.redhat.io \
  --docker-username='REDACTED' \
  --docker-password='REDACTED'
```

## 2. Draft Values
Use `maximo-iam-operator/helm-charts/keycloak-mas/values.example.yaml` as the baseline. Suggested edits:
- Set `global.imagePullSecrets` to the Red Hat registry secret name
- Populate `keycloak.admin.existingSecret` if reusing a pre-created admin credential secret; otherwise leave `createSecret: true`
- Point `keycloak.database` to external Postgres or enable the bundled Bitnami Postgres subchart (`postgresql.enabled: true`)
- Configure `keycloak.truststore.*` for the secret created above
- Set `service`, `route`, and `ingress` to match your ingress strategy
- Leave `keycloak.startup.import.enabled=false` and `realm.import.enabled=false` for the dry run

Apply the chart:

```bash
helm upgrade --install mas-iam maximo-iam-operator/helm-charts/keycloak-mas \
  --namespace ${KEYCLOAK_NS} \
  --create-namespace \
  -f <your-values>.yaml
```

Verify the pod:

```bash
kubectl -n ${KEYCLOAK_NS} get pods -l app.kubernetes.io/component=keycloak
```

## 3. Dry-Run Realm Configuration in the UI
1. Port-forward (only needed once) or browse via the exposed Route:
   ```bash
   kubectl -n ${KEYCLOAK_NS} port-forward svc/mas-iam-keycloak 8080:8080
   ```
2. Log into `http://127.0.0.1:8080` (or the Route host) with the admin credentials (secret `mas-iam-keycloak-admin` by default).
3. Create/verify the target realm (e.g. `maximo`).
4. Add LDAP federation (User Federation → `ldap`). Recommended settings:
   - Connection URL: `ldaps://<ldap-hostname>:636`
   - Bind DN: service account for LDAP
   - Use truststore SPI (`keycloak.truststore.*` already mounted)
   - Users DN / Groups DN: align with your directory tree (see `Local/OpenLDAP/ldifs/init.ldif` for sample structure)
   - Sync settings: enable periodic sync and "Import Users" if desired
5. Create required groups, roles, clients, and mappers that must bootstrap with the realm.
6. Test a sample LDAP login to ensure LDAPS handshake succeeds.

## 4. Export the Realm JSON
Leverage the helper script to capture the realm without leaving credentials on disk:

```bash
# Exports to helm/seed/realm-export.json by default
./scripts/export-realm.sh -n ${KEYCLOAK_NS} -r mas-iam -R maximo
```

The script performs a temporary port-forward, fetches an admin token, and writes a pretty-printed export to `maximo-iam-operator/helm-charts/keycloak-mas/helm/seed/realm-export.json`.

Update the realm checksum so Helm can detect changes during upgrades:

```bash
sha256sum maximo-iam-operator/helm-charts/keycloak-mas/helm/seed/realm-export.json
```
Copy the hash into `values.yaml` under `realm.import.checksum`.

## 5. Enable Import-at-Start
Edit your values file:

```yaml
keycloak:
  startup:
    import:
      enabled: true
      behavior: IGNORE_EXISTING  # or OVERWRITE_EXISTING
      failOnError: true

realm:
  import:
    enabled: true
    filename: realm-export.json
    mountPath: /opt/keycloak/data/import
    checksum: "<sha256 from previous step>"
  postImportJob:
    enabled: true
    ldapSecretName: ldap-bind       # reuses the secret created earlier
    ldapSecretKey: LDAP_ADMIN_PASSWORD
```

Redeploy:

```bash
helm upgrade --install mas-iam maximo-iam-operator/helm-charts/keycloak-mas \
  --namespace ${KEYCLOAK_NS} \
  -f <your-values>.yaml
```

Helm will mount the ConfigMap containing the exported realm, start Keycloak with `--import-realm`, and run the optional post-import job to patch the LDAP bind credential from the Kubernetes secret (avoids committing passwords to Git).

## 6. Verification Checklist
- **Pod health**: `kubectl -n ${KEYCLOAK_NS} get pods -l app.kubernetes.io/component=keycloak`
- **Admin console reachable**: via Route or `kubectl port-forward`
- **Realm imported**: realm, clients, groups visible after fresh deploy
- **LDAP sync**: Users appear under User Federation → LDAP; login succeeds
- **Secrets mounted**: `kubectl -n ${KEYCLOAK_NS} describe pod <pod> | grep truststore`
- **Post-import job**: `kubectl -n ${KEYCLOAK_NS} logs job/mas-iam-keycloak-realm-postimport`

## 7. Troubleshooting
- `kubectl -n ${KEYCLOAK_NS} logs deployment/mas-iam-keycloak` for Keycloak Quarkus startup output
- `kubectl -n ${KEYCLOAK_NS} logs <pod> --container keycloak` for detailed stack traces
- `kubectl -n ${KEYCLOAK_NS} exec deploy/mas-iam-keycloak -- curl -k https://<ldap-host>:636` to validate LDAPS connectivity from inside the pod
- If LDAPS handshake fails, confirm:
  - The truststore secret contains the LDAP issuing CA (`keytool -list -keystore`)
  - `KC_SPI_TRUSTSTORE_FILE_*` env vars resolved correctly (`kubectl -n ${KEYCLOAK_NS} get deploy -o yaml`)
- Realm import errors surface in logs as `MigrationStrategy` or `RealmImport` exceptions; re-check `realm.import.filename` and checksum
- Post-import job failures: rerun with `kubectl -n ${KEYCLOAK_NS} create job --from=cronjob/...` or inspect logs; ensure LDAP bind secret is present

## 8. Useful Commands
- Check current admin password:
  ```bash
  kubectl -n ${KEYCLOAK_NS} get secret ${RELEASE}-keycloak-admin -o jsonpath='{.data.admin-password}' | base64 --decode
  ```
- Tear down:
  ```bash
  helm uninstall mas-iam -n ${KEYCLOAK_NS}
  kubectl delete secret keycloak-truststore ldap-bind ldap-ca -n ${KEYCLOAK_NS}
  ```

Document updates should accompany commits to `helm/seed/realm-export.json` whenever realm artifacts change.
