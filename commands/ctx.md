Show current kubectl context and cluster health summary:
- Current context name and cluster server URL
- Node status — flag any NotReady
- All pods not in Running/Completed/Succeeded state (kubectl get pods -A, filter non-healthy)
- HelmRelease status across all namespaces (kubectl get hr -A) — flag any not Ready
- Keep output concise: only show problem rows for pods and HRs, not the full list
