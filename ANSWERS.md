# Session 4: Observability, Alerting and Incident Response

## Part 1 - Instrument the Application

The application exposes Prometheus metrics on `/metrics` and writes one JSON log line per request to stdout. `/slow` waits for a random time up to 2 seconds, and `/error` returns HTTP 500 about 30% of the time.

Commands used to test it locally:

```sh
npm ci
node app.js
curl localhost:3000/health
curl localhost:3000/slow
curl localhost:3000/error
curl localhost:3000/metrics
```

Build tagged with the commit SHA:

```sh
docker build -t myapp:$(git rev-parse HEAD) .
```

The Session 1 workflow runs this build on each pull request. After the merge to `main`, it publishes the image to GitHub Container Registry with the commit SHA as its tag.

### 1. Why is it a problem to use a user ID or a full URL containing IDs as a metric label?

Prometheus stores one time series for each combination of label values. With a user ID as a label, every user adds new series, and a histogram multiplies that by its number of buckets. Memory use grows, queries slow down and Prometheus can end up crashing. This is called a cardinality explosion. The series are also of little use, since each one only describes a few requests.

We label requests with the Express route pattern instead, so `/users/1` and `/users/2` would share `/users/:id`. Requests that match no route are all labelled `unmatched`. The real path stays in the logs, where having many values is not a problem.

### 2. Why log to stdout in JSON rather than to a file in plain text?

A container's filesystem is temporary, so a log file disappears with the Pod, and it can fill the disk if nothing rotates it. With stdout, the container runtime collects the output, `kubectl logs` can show it, and an agent can send the logs of all Pods to a central place. The application doesn't need to know where its logs go.

JSON gives each value a named field. A log tool can filter on `status` or `level` directly, without a regular expression that breaks when the message wording changes.
