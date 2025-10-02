# 0) Choose the ONE namespace you want to use
export NS=maximo-iam
export REL=mas-iam

# 1) Delete the CR (remove finalizers if present so it can't hang)
kubectl -n "$NS" patch maximoiam "$REL" --type=merge -p '{"metadata":{"finalizers":[]}}' 2>/dev/null || true
kubectl -n "$NS" delete maximoiam "$REL" --ignore-not-found=true

# 2) Delete the entire namespace (fastest full purge)
kubectl delete namespace "$NS" --wait=false || true

# 3) If the namespace sticks in Terminating, force-finalize it
if kubectl get ns "$NS" -o jsonpath='{.status.phase}' 2>/dev/null | grep -qi Terminating; then
  kubectl get ns "$NS" -o json > /tmp/ns.json
  # Open /tmp/ns.json in your editor and remove the entire "spec": {"finalizers":[...]} block, save file
  kubectl replace --raw "/api/v1/namespaces/$NS/finalize" -f /tmp/ns.json
fi

# 4) Clean up any PVs that may have "Retain" reclaim policy (rare, but safe to check)
for pv in $(kubectl get pv -o jsonpath='{range .items[*]}{.metadata.name}{"|"}{.spec.claimRef.namespace}{"\n"}{end}' \
           | awk -F'|' '$2=="'"$NS"'"{print $1}'); do
  kubectl delete pv "$pv"
done
