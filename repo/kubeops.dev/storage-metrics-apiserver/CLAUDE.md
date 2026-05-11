What the repo does

This is a Kubernetes Custom Metrics API server (built on top of k8s-sigs/custom-metrics-apiserver) that exposes PVC (PersistentVolumeClaim) storage metrics ? capacity, available bytes, used bytes, inodes, and percentages ?    
under the custom.metrics.k8s.io/v1beta2 API. This lets HPAs and other controllers query real-time disk usage for PVCs.

The data source is kubelet's /stats/summary endpoint on each node (not Prometheus/CSI), which means it works for any mounted PVC regardless of storage driver.

---
Core logic files (the new storagemetrics stack)

?                        File                         ?                                             Role                                              ?
? pkg/storagemetrics/scraper/client/summary_client.go ? Hits each node's kubelet /stats/summary, parses VolumeStats[] ? per-PVC batch                 ?
? pkg/storagemetrics/scraper/scraper.go               ? Fans out goroutines per node with jitter delays, merges results (keeps freshest for RWX PVCs) ?
? pkg/storagemetrics/manager/manager.go               ? Runs the periodic tick loop; calls Scraper ? writes to Storage                                ?
? pkg/storagemetrics/storage/storage.go               ? Thread-safe in-memory cache (map[NamespacedName]PVCMetricsPoint)                              ?
? pkg/storagemetrics/provider/provider.go             ? Implements CustomMetricsProvider; answers GetMetricByName and GetMetricBySelector from cache  ?
? pkg/storagemetrics/provider/metrics.go              ? Defines the 8 metric names and extracts resource.Quantity values from cached points           ?
???????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????

The 8 exposed metrics: volume_capacity_bytes, volume_available_bytes, volume_used_bytes, volume_used_percentage, volume_inodes, volume_inodes_free, volume_inodes_used, volume_inodes_used_percentage.
