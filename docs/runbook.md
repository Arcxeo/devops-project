# Runbook: HighErrorRate

| | |
|---|---|
| Severity | critical |
| Condition | More than 10% of the requests to `myapp` in `dev` return a 5xx response, for 2 minutes |
| Rule | `monitoring/prometheusrule.yaml` |
| Dashboard | Grafana, `myapp - Golden Signals` |

The ratio excludes `/health` and `/metrics`. It says nothing when there is no traffic.

## Symptoms

- `HighErrorRate` is `FIRING` in Prometheus and Alertmanager.
- The Errors panel is above the 10% line.
- Users get HTTP 5xx responses.

## Quick checks

Open the tools if needed:

```sh
kubectl port-forward -n monitoring svc/monitoring-grafana 3001:80
kubectl port-forward -n monitoring svc/monitoring-kube-prometheus-prometheus 9090:9090
```

1. Look at the four panels. Note when the errors started, and whether traffic, latency or memory changed at the same time.

2. Find the failing routes and Pods in Prometheus:

   ```promql
   sum by (route, status, pod) (rate(http_requests_total{namespace="dev", status=~"5.."}[2m]))
   ```

3. Check the Pods, for restarts or a status other than `Running`:

   ```sh
   kubectl get pods -n dev -l app=myapp
   kubectl get events -n dev --sort-by=.metadata.creationTimestamp
   ```

4. Check whether a deployment happened just before the errors, and which image is running:

   ```sh
   kubectl rollout history deployment/myapp -n dev
   kubectl get deployment myapp -n dev -o jsonpath='{.spec.template.spec.containers[0].image}'
   ```

5. Read the error logs:

   ```sh
   kubectl logs -n dev -l app=myapp --tail=200 | grep '"level":"error"'
   ```

## Mitigation

Restore the service first and look for the root cause afterwards.

1. The errors started after a deployment: roll back.

   ```sh
   kubectl rollout undo deployment/myapp -n dev
   kubectl rollout status deployment/myapp -n dev
   ```

   The faulty Pod can keep answering on open connections for up to 30 seconds, because the application does not handle `SIGTERM`.

2. No recent deployment and only some Pods fail: restart them.

   ```sh
   kubectl rollout restart deployment/myapp -n dev
   ```

3. Traffic or memory is unusually high: add replicas.

   ```sh
   kubectl scale deployment/myapp -n dev --replicas=3
   ```

4. None of this helps: escalate to the owner of the service.

## After the mitigation

- Check that the Errors panel goes down and that the alert is resolved. This takes about 2 minutes, since the rule uses a 2-minute window.
- Put the working image tag back in `k8s/overlays/dev`. Otherwise, the next `kubectl apply -k` deploys the faulty version again.
- Write down the timeline in UTC and start a postmortem in `docs/postmortem.md`.
