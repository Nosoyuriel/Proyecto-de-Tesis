#!/bin/bash

# Actualizamos el uso para aceptar un tercer argumento opcional para SAST
if [[ "$1" = "sast" && "$#" -ne 3 ]] || [[ "$1" != "sast" && "$#" -ne 2 ]]; then
    echo "Uso:"
    echo "  $0 sast <ruta_al_proyecto> <project_key_en_sonarqube>"
    echo "  $0 sca <ruta_al_proyecto>"
    echo "  $0 dast <URL_de_la_aplicacion>"
    exit 1
fi

SCAN_TYPE=$1
TARGET=$2

# --- PORTABILIDAD ---
# Convertimos el nombre del directorio a minúsculas para que coincida con Docker Compose.
NETWORK_NAME=$(basename "$(pwd)" | tr '[:upper:]' '[:lower:]')_devsecops-net

# --- Lógica principal ---
case $SCAN_TYPE in
    sast)
        PROJECT_KEY=$3
        ABS_PROJECT_PATH=$(readlink -f "$TARGET")
        if [ ! -d "$ABS_PROJECT_PATH" ]; then echo "Error: El directorio '$ABS_PROJECT_PATH' no existe."; exit 1; fi
        if [ -z "$SONAR_TOKEN" ]; then echo "Error: La variable SONAR_TOKEN no está configurada."; exit 1; fi
        echo "--- Ejecutando Análisis Estático (SAST) para el proyecto '$PROJECT_KEY'... ---"
        docker run --rm \
          --network=$NETWORK_NAME \
          -v "$ABS_PROJECT_PATH:/scan" \
          devsecops-suite sonar-scanner \
          -Dsonar.projectKey="$PROJECT_KEY" \
          -Dsonar.sources=. \
          -Dsonar.host.url=http://sonarqube-server:9000 \
          -Dsonar.token="$SONAR_TOKEN"
        ;;
    sca)
        ABS_PROJECT_PATH=$(readlink -f "$TARGET")
        if [ ! -d "$ABS_PROJECT_PATH" ]; then echo "Error: El directorio '$ABS_PROJECT_PATH' no existe."; exit 1; fi
        echo "--- Ejecutando Análisis de Dependencias (SCA) con Trivy... ---"
        docker run --rm \
            -v "$ABS_PROJECT_PATH:/scan" \
            -v ~/.cache/trivy:/root/.cache/ \
            devsecops-suite trivy fs --severity HIGH,CRITICAL --exit-code 1 /scan
        ;;
    dast)
        echo "--- Ejecutando Análisis Dinámico (DAST)... ---"
        REPORTS_DIR="$(pwd)/reports"
        mkdir -p "$REPORTS_DIR"
        echo "Los informes se guardarán en: $REPORTS_DIR"

        docker run --rm -w /zap/wrk \
          --network=$NETWORK_NAME \
          -v "$(pwd)/reports:/zap/wrk" \
          ghcr.io/zaproxy/zaproxy:stable \
          zap-baseline.py \
          -t http://juice-shop-dast:3000 \
          -r "zap_report.html"
        ;;
    *)
        echo "Error: Tipo de scan '$SCAN_TYPE' no reconocido."
        exit 1
        ;;
esac
