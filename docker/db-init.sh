#!/bin/bash
# Lot 14 : construit la base de demonstration TraceabilityDev, puis charge les donnees de demo.
# Lance une seule fois par le conteneur db-init. Le mot de passe vient de SQLCMDPASSWORD.
# Pas de volume : "docker compose down" supprime la base, le "up" suivant la reconstruit.
set -euo pipefail

SQLCMD="/opt/mssql-tools18/bin/sqlcmd -C -S sql,1433 -U sa -b"

# 002 n'est pas rejouable : si le schema existe deja, on ne refait rien.
schema=$($SQLCMD -h -1 -W -Q "SET NOCOUNT ON; SELECT CASE WHEN OBJECT_ID(N'TraceabilityDev.trace.Farm', N'U') IS NULL THEN 0 ELSE 1 END")
if [ "$schema" = "1" ]; then
  farms=$($SQLCMD -h -1 -W -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM TraceabilityDev.trace.Farm")
  if [ "$farms" -gt 0 ]; then
    echo "TraceabilityDev existe deja et contient des donnees : rien a faire."
    exit 0
  fi
  echo "TraceabilityDev existe mais est incomplete. Lancer 'docker compose down' puis 'docker compose up'." >&2
  exit 1
fi

for f in 001_create_database 002_create_schema_and_tables 004_create_reference_procedures \
         005_create_batch_procedures 011_create_list_procedures 017_optimize_list_batches \
         022_demo_data; do
  echo "=== $f.sql"
  $SQLCMD -i "/database/$f.sql"
done
echo "TraceabilityDev est prete."
