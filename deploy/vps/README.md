# Shahina site on the VPS
`/docker/shahina` on srv1991689 (Traefik routes it). `./deploy.sh` builds GitHub `main` and publishes it. A cron job runs `./deploy.sh --if-changed` every minute.
Rollback to Netlify: point the DNS back (Netlify keeps deploying the same repo).
