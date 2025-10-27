# R.A.L.F. Agent Test Environments

Diese Vorlagen stellen leichtgewichtige Container-Szenarien bereit, um die einzelnen R.A.L.F.-Agenten isoliert zu testen.
Jedes Compose-File ordnet einem Agenten einen eigenen Container sowie seine wichtigsten Abhängigkeiten zu. Die Dienste sind
absichtlich minimal gehalten und nutzen Standard-Images, damit sie auch auf einer lokalen Entwickler:innen-Maschine lauffähig
sind.

## Verfügbare Templates

| Datei                             | Beschreibung                                                    |
| -------------------------------- | --------------------------------------------------------------- |
| `docker-compose.a_plan.yml`      | Planner-Agent mit PostgreSQL, Prometheus und Foreman-Mock       |
| `docker-compose.a_infra.yml`     | Infrastruktur-Agent inkl. Gitea-, Vaultwarden- und Runner-Dummy |
| `docker-compose.a_mon.yml`       | Monitoring-Agent zusammen mit Prometheus, Loki und Grafana      |
| `docker-compose.a_code.yml`      | Code-Agent mit Gitea-Spiegel, Doku-Ablage und Vektor-DB-Dummy   |
| `docker-compose.a_sec.yml`       | Security-Agent mit Vaultwarden, Audit-Log und Scanner           |
| `docker-compose.foreman.yml`     | Foreman-Discovery-Agent mit simulierten DHCP/TFTP-Diensten      |

Alle Templates teilen sich ein gemeinsames Netz `ralf_testing`. Beim Erzeugen einer Testumgebung werden sie in einen lokalen
Arbeitsordner kopiert. So können sie unabhängig voneinander mit `docker compose -f <template> up` gestartet werden.
