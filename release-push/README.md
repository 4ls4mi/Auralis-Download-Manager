# Auralis release notifications

The Worker accepts signed GitHub release webhooks, sends a version hint over a WebSocket, and stores the latest verified release metadata for `/latest`. Auralis checks GitHub first and uses that metadata only when the GitHub API is unavailable or rate-limited. The installer is downloaded from GitHub and checked against its declared SHA-256 and size. The fallback is unavailable until a signed public Auralis release webhook has been received after deployment. Running clients reconnect and check GitHub on connection; there is no five-minute polling when a push endpoint is configured. A client started after a release checks GitHub at startup. This is not an operating-system push service: the app must be running to receive the WebSocket signal. If Cloudflare or the network is down, an already connected client can miss a notification; GitHub does not automatically retry failed webhooks. Check failed GitHub webhook deliveries and redeliver them after fixing the failure.

## Deploy

1. Enable Workers on the Cloudflare account and create an API token using the **Edit Cloudflare Workers** template scoped to that account. The first deployment may require enabling the workers.dev subdomain.
2. In GitHub repository **Settings → Secrets and variables → Actions**, add repository secrets `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`, and `AURALIS_WEBHOOK_SECRET`. Generate a long random webhook secret and retain it securely; use the same value when configuring GitHub's webhook. Never commit or post these values.
3. Run **Deploy Auralis release notifications** using `workflow_dispatch` on the branch containing this workflow. The deployment output includes the Worker URL; no secrets should be printed.
4. In GitHub repository **Settings → Webhooks**, add the payload URL `https://<worker-host>/github/webhook`, content type `application/json`, the same webhook secret, and select only **Releases**. Do not subscribe to all events. Check deliveries in GitHub.
5. The Windows app must use `wss://<worker-host>/events` and allow that exact `wss:` origin in the Tauri CSP. The push service is not operational for users until a new app build containing the deployed endpoint is released and the GitHub webhook is configured.

Durable Object hibernation reduces idle work, but free-tier quotas, socket limits, account configuration and pricing can change. Monitor Cloudflare usage and limits before scaling.
