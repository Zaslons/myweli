#!/usr/bin/env bash
# Start the PostgreSQL that GitHub's Ubuntu runner image ships (installed,
# stopped) and create the job's database — instead of pulling a postgres image.
#
# Why not a service container: an anonymous image pull is rate-limited by IP,
# and GitHub's runners share IPs. Docker Hub failed both backend jobs on
# #558/#559 (2026-10-09); its ECR Public mirror then failed them again and
# again ("toomanyrequests: Data limit exceeded" — seven runs on 2026-10-15,
# twice in a row on #611). Nothing here downloads anything.
#
# Production is Cloud SQL PostgreSQL 16: the job fails loudly if the runner
# image ever moves to another major, rather than testing against it quietly.
#
# So the jobs that call this pin `runs-on: ubuntu-24.04`. A runner image
# installs the major its toolset names (images/ubuntu/toolsets/ in
# actions/runner-images): 24.04's has named 16 since the file was created on
# 2024-04-26, while 26.04's names 18. `ubuntu-latest` moved to 26.04 in
# November 2026 (actions/runner-images#14748), and this check failed both
# backend jobs from 2026-11-07 until the pin.
#
# When ubuntu-24.04 is retired, or production changes major to one no image
# ships, install the major here from apt.postgresql.org instead. That works on
# 26.04 — it was measured on 2026-11-09 (docs/roadmap/entries/2026-11-09-ci-
# postgres-16-pinned.md) — but it is a download on every run, the very thing
# this script exists to avoid.
#
# Usage: start-postgres.sh <database>   (role postgres / password postgres,
# on localhost:5432 — what the jobs' DATABASE_URL already says)
set -euo pipefail

DB="${1:?usage: start-postgres.sh <database>}"
WANT_MAJOR=16

sudo systemctl start postgresql.service

for _ in $(seq 1 30); do
  pg_isready -h localhost -p 5432 -q && break
  sleep 1
done
pg_isready -h localhost -p 5432

server=$(sudo -u postgres psql -tAc 'SHOW server_version_num')
major=$((server / 10000))
if [ "$major" != "$WANT_MAJOR" ]; then
  echo "::error::The runner's PostgreSQL is $major (server_version_num $server, runner image ${ImageOS:-unknown} ${ImageVersion:-unknown}); production is $WANT_MAJOR. Pin a runner image that ships $WANT_MAJOR (see this script's header), or install it here."
  exit 1
fi

sudo -u postgres psql -v ON_ERROR_STOP=1 -q \
  -c "ALTER USER postgres PASSWORD 'postgres';" \
  -c "CREATE DATABASE \"$DB\";"

# Prove the URL the jobs use works, over TCP with the password.
PGPASSWORD=postgres psql -h localhost -U postgres -d "$DB" -tAc 'SELECT 1' >/dev/null
echo "PostgreSQL $(sudo -u postgres psql -tAc 'SHOW server_version') ready: database $DB on localhost:5432"
