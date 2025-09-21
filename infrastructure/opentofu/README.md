# OpenTofu Beispiel-Stacks

Dieser Ordner enthält eine minimale, dateibasierte OpenTofu-Struktur zur Dokumentation der DevOps-Toolchain.

- `modules/toolchain`: Basismodul, das eine Manifestdatei mit allen Kernservices erzeugt.
- `stacks/dev`: Beispiel-Stack für Entwicklungsumgebungen mit zusätzlichen Diensten.
- `stacks/prod`: Reduzierter Produktions-Stack.

Die Konfiguration lässt sich mit `tofu init` und `tofu plan` pro Stack testen, sofern OpenTofu installiert ist.
