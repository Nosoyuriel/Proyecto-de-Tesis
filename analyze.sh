#!/bin/bash

# --- Script Orquestador para la Suite Completa de Análisis DevSecOps ---

# 'set -e' hace que el script se detenga inmediatamente si cualquier comando falla.
# Esto es CRUCIAL para un pipeline: si el SCA falla, no continuamos al SAST.
set -e

# Auto-cargar token y proyecto desde archivos de configuración si no están exportados
if [ -z "$SONAR_TOKEN" ] && [ -f ".sonar_env" ]; then
    echo "Cargando configuración desde .sonar_env..."
    source .sonar_env
fi

if [ -z "$DEFAULT_PROJECT" ] && [ -f ".sonar_project" ]; then
    DEFAULT_PROJECT=$(cat .sonar_project)
fi

# --- 1. VALIDACIÓN DE ENTRADA ---
if [ "$#" -eq 0 ]; then
    echo "Uso: $0 <ruta_al_proyecto> [sonar_project_key]"
    echo "Si no especificas sonar_project_key, se usará el proyecto guardado en .sonar_project"
    exit 1
fi

PROJECT_PATH=$1
SONAR_PROJECT_KEY=${2:-$DEFAULT_PROJECT}

if [ -z "$SONAR_PROJECT_KEY" ]; then
    echo "Error: No se especificó sonar_project_key y no hay uno guardado en .sonar_project"
    echo "Ejecuta ./setup.sh primero o especifica el proyecto como segundo argumento."
    exit 1
fi
ABS_PROJECT_PATH=$(cd "$PROJECT_PATH" && pwd)

if [ ! -d "$ABS_PROJECT_PATH" ]; then
    echo "Error: El directorio del proyecto '$ABS_PROJECT_PATH' no existe."
    exit 1
fi

# Determina dinámicamente el nombre de la red de Docker Compose basándose
# en el nombre del directorio actual, convertido a minúsculas.
NETWORK_NAME=$(basename "$(pwd)" | tr '[:upper:]' '[:lower:]')_devsecops-net

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

# Creamos la carpeta de reportes por si no existe
mkdir -p "$(pwd)/reports"

docker run --rm \
  -v "$ABS_PROJECT_PATH:/scan" \
  -v "$(pwd)/reports:/reports" \
  -v ~/.cache/trivy:/root/.cache/ \
  devsecops-suite trivy fs \
  --severity HIGH,CRITICAL \
  --format json \
  --output /reports/trivy_report.json \
  --scanners vuln \
  --list-all-pkgs \
  --detection-priority comprehensive \
  /scan

echo "--- ✅ SCA finalizado. Reposte dentro de la carpeta reports con el nombre <trivy_report.json> ---"

# --- 3. ANÁLISIS ESTÁTICO (SAST con SonarQube) ---
echo "\n--- [PASO 2/3] Ejecutando Análisis Estático (SAST) para el proyecto '$SONAR_PROJECT_KEY'... ---"

REPORTS_DIR="$(pwd)/reports"
mkdir -p "$REPORTS_DIR"

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

#Extracción de los resultados
echo "Esperando a que se procese el reporte..."
sleep 8 # Tiempo para que SonarQube se actualice

echo "Procesando el reporte JSON de SonarQube..."
# A. Todos los problemas (Vulnerabilidades + Bugs + Code Smells)
curl -s -u "$SONAR_TOKEN:" "http://localhost:9000/api/issues/search?componentKeys=$SONAR_PROJECT_KEY&ps=500" > "$REPORTS_DIR/sonar_issues.json"

# B. Security Hotspots (Puntos críticos que requieren revisión humana)
curl -s -u "$SONAR_TOKEN:" "http://localhost:9000/api/hotspots/search?projectKey=$SONAR_PROJECT_KEY" > "$REPORTS_DIR/sonar_hotspots.json"

# C. Métricas del Dashboard (Porcentajes de Duplicación, Líneas de código, etc.)
curl -s -u "$SONAR_TOKEN:" "http://localhost:9000/api/measures/component?component=$SONAR_PROJECT_KEY&metricKeys=reliability_rating,security_rating,sqale_rating,coverage,duplicated_lines_density,ncloc" > "$REPORTS_DIR/sonar_metrics.json"

echo "--- ✅ SAST finalizado. Reporte guardado en: $REPORTS_DIR/sonar_report.json ---"

# --- 4. ANÁLISIS DINÁMICO (DAST con OWASP ZAP) ---
echo "\n--- [PASO 3/4] Ejecutando Análisis Dinámico (DAST)... ---"

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
  -J "zap_report.json" \
  -r "zap_report_$(basename $ABS_PROJECT_PATH).html" || true
echo "--- ✅ DAST finalizado. ---"

echo "\n========================================================================"
echo "  ¡ANÁLISIS COMPLETO FINALIZADO, CREANDO REPORTE MAESTRO!"
echo "========================================================================"


# --- 4. CONSOLIDACIÓN DE RESULTADOS ---
echo -e "\n--- [PASO 4/4] Consolidando Reporte Maestro dentro del Contenedor ---"

# Ejecutamos el script usando la imagen de nuestra suite
# Montamos la carpeta de reportes y el propio script dentro del contenedor
docker run --rm \
  -v "$(pwd)/reports:/reports" \
  -v "$(pwd)/final_report.py:/scan/final_report.py" \
  devsecops-suite python3 /scan/final_report.py

echo -e "\n========================================================================"
echo "  ¡ANÁLISIS Y REPORTE FINALIZADOS!"
echo "  Resultados unificados en: reports/MASTER_REPORT.json"
echo "========================================================================"

# El 'trap' se encargará de detener el contenedor de la app aquí.
