# Skalierungsszenarien des Core-Profils

Die verteilte Planung des Core-Profils weist allen kritischen Diensten explizite
Rollen zu und dokumentiert die Ressourcenauslastung pro Node. Die Basisverteilung
mit den neuen Node-Definitionen ergibt folgende Zuordnung:

| Node   | Rolle    | Komponenten                                                | CPU (genutzt/gesamt) | RAM (genutzt/gesamt) | Storage (genutzt/gesamt) | Netzwerk (genutzt/gesamt) |
|--------|----------|------------------------------------------------------------|----------------------|----------------------|---------------------------|----------------------------|
| pve01  | Compute  | postgresql, gitea, vector-db, ralf-ui                      | 20 / 24 vCPU         | 40 / 128 GB          | 690 / 1800 GB             | 8 / 20 Gbit/s              |
| pve02  | Compute  | vaultwarden, automation, observability                     | 12 / 16 vCPU         | 24 / 64 GB           | 440 / 1200 GB             | 7 / 12 Gbit/s              |
| pbs01  | Storage  | backups                                                     | 4 / 12 vCPU          | 8 / 48 GB            | 2000 / 8000 GB            | 4 / 10 Gbit/s              |
| net01  | Network  | —                                                           | 0 / 8 vCPU           | 0 / 32 GB            | 0 / 500 GB                | 0 / 40 Gbit/s              |

## Simulation: Doppelte Vektordatenbank & 3× Observability-Last

Ein Simulationlauf mit doppelter Last auf `vector-db` und einer Verdreifachung
für `observability` zeigt, wo erste Engpässe auftreten:

- **pve01** benötigt 28 vCPU, verfügbar sind 24 vCPU → *CPU-Defizit 4 vCPU*.
- **pve02** benötigt 24 vCPU bei 16 vCPU Kapazität → *CPU-Defizit 8 vCPU*.
- **pve02** erreicht 15 Gbit/s Netzwerkbedarf, bereitstehen 12 Gbit/s → *Netzwerk-Defizit 3 Gbit/s*.

Die Simulation bestätigt damit die Notwendigkeit zusätzlicher Compute-Ressourcen
oder eine Umverteilung der Observability-Workloads bei steigendem Monitoring- und
Ingestion-Volumen. Die Ergebnisse werden automatisch in den Tests geprüft und
sichern reproduzierbare Kapazitätsanalysen.
