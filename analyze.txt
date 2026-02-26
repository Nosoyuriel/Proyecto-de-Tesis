#!/bin/bash

# --- Script Orquestador para la Suite Completa de Análisis DevSecOps ---

# 'set -e' hace que el script se detenga inmediatamente si cualquier comando falla.
# Esto es CRUCIAL para un pipeline: si el SCA falla, no continuamos al SAST.
set -e

# --- 1. VALIDACIÓN DE ENTRADA ---
if [ "$#" -ne 2 ]; then
    echo "Uso: $0 <ruta_al_proyecto> <sonar_project_key>"
    exit 1
fi

PROJECT_PATH=$1
SONAR_PROJECT_KEY=$2
ABS_PROJECT_PATH=$(readlink -f "$PROJECT_PATH")

if [ ! -d "$ABS_PROJECT_PATH" ]; then
    echo "Error: El directorio del proyecto '$ABS_PROJECT_PATH' no existe."
    exit 1
fi

# Determina dinámicamente el nombre de la red de Docker Compose basándose
# en el nombre del directorio actual, convertido a minúsculas.
NETWORK_NAME=$(basename "$(pwd)" | tr '[:upper:]' '[:lower:]')_devsecops-net
echo "--- Usando la red de Docker: $NETWORK_NAME ---"

# Verifica si los servicios de SonarQube están corriendo.
if ! docker compose ps | grep -q "sonarqube-server.*Up"; then
    echo "Error: Los servicios de SonarQube no están corriendo. Ejecuta 'docker compose up -d' primero."
    exit 1
fi

echo "========================================================================"
echo "  INICIANDO ANÁLISIS COMPLETO PARA: $ABS_PROJECT_PATH"
echo "========================================================================"

# --- 2. ANÁLISIS DE DEPENDENCIAS (SCA con Trivy) ---
echo "\n--- [PASO 1/3] Ejecutando Análisis de Dependencias (SCA)... ---"
docker run --rm \
  -v "$ABS_PROJECT_PATH:/scan" \
  -v ~/.cache/trivy:/root/.cache/ \
  devsecops-suite trivy fs --severity HIGH,CRITICAL --scanners vuln /scan

echo "--- ✅ SCA finalizado. Resultados mostrados arriba. ---"

# --- 3. ANÁLISIS ESTÁTICO (SAST con SonarQube) ---
echo "\n--- [PASO 2/3] Ejecutando Análisis Estático (SAST) para el proyecto '$SONAR_PROJECT_KEY'... ---"
if [ -z "$SONAR_TOKEN" ]; then
    echo "Error: La variable de entorno SONAR_TOKEN no está configurada."
    exit 1
fi

docker run --rm \
  --network=$NETWORK_NAME \
  -v "$ABS_PROJECT_PATH:/scan" \
  devsecops-suite sonar-scanner \
  -Dsonar.projectKey="$SONAR_PROJECT_KEY" \
  -Dsonar.sources=. \
  -Dsonar.host.url=http://sonarqube-server:9000 \
  -Dsonar.token="$SONAR_TOKEN" \
  -Dsonar.qualitygate.wait=true \
  -Dsonar.qualitygate.break=false

echo "--- ✅ SAST finalizado: El Quality Gate fue superado. ---"

# --- 4. ANÁLISIS DINÁMICO (DAST con OWASP ZAP) ---
echo "\n--- [PASO 3/3] Ejecutando Análisis Dinámico (DAST)... ---"

# Asumimos que el proyecto tiene un Dockerfile para ser construido y ejecutado.
APP_IMAGE_TAG="target-app-dast-$(basename $ABS_PROJECT_PATH)"
APP_CONTAINER_NAME="dast-target-$(basename $ABS_PROJECT_PATH)"
REPORTS_DIR="$(pwd)/reports"
mkdir -p "$REPORTS_DIR"

echo "Construyendo la imagen de la aplicación objetivo: $APP_IMAGE_TAG"
docker build -t "$APP_IMAGE_TAG" "$ABS_PROJECT_PATH"

# 'trap' es un comando robusto para asegurar que el contenedor de la app se detenga al final,
# incluso si el script falla.
trap "echo 'Limpiando contenedor de la aplicación...'; docker stop $APP_CONTAINER_NAME" EXIT

echo "Iniciando la aplicación en un contenedor para el análisis..."
docker run -d --rm \
  --name "$APP_CONTAINER_NAME" \
  --network=$NETWORK_NAME \
  "$APP_IMAGE_TAG"
echo "Esperando 15 segundos a que la aplicación se inicie..."
sleep 15

echo "Lanzando escáner DAST contra http://$APP_CONTAINER_NAME:3000 ..."
echo "Los informes se guardarán en: $REPORTS_DIR"

# Añadimos el puerto :3000 a la URL objetivo.
docker run --rm -w /zap/wrk \
  --network=$NETWORK_NAME \
  -v "$REPORTS_DIR:/zap/wrk" \
  ghcr.io/zaproxy/zaproxy:stable \
  zap-baseline.py \
  -t "http://$APP_CONTAINER_NAME:3000" \
  -r "zap_report_$(basename $ABS_PROJECT_PATH).html"
echo "--- ✅ DAST finalizado. Revisa el informe en la carpeta 'reports'. ---"

echo "\n========================================================================"
echo "  ¡ANÁLISIS COMPLETO FINALIZADO!"
echo "========================================================================"

# El 'trap' se encargará de detener el contenedor de la app aquí.