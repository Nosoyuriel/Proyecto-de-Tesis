#!/bin/bash

# ==============================================================================
#  SCRIPT PARA INICIAR SERVICIOS Y AÑADIR UN NUEVO PROYECTO A SONARQUBE
# ==============================================================================

set -e

# --- 1. VALIDACIÓN DE ENTRADA ---
if [ "$#" -ne 2 ]; then
    echo "Uso: $0 <NUEVA_PROJECT_KEY> \"<Nombre del Nuevo Proyecto>\""
    echo "Ejemplo: $0 mi-nueva-app \"Mi Nueva Aplicación Web\""
    exit 1
fi

if [ -z "$SONAR_ADMIN_PASSWORD" ]; then
    echo "Error: La contraseña de administrador de SonarQube no está configurada."
    echo "Por favor, expórtala en la variable de entorno SONAR_ADMIN_PASSWORD."
    echo "Ejemplo: export SONAR_ADMIN_PASSWORD=\"la_contraseña_que_estableciste\""
    exit 1
fi

PROJECT_KEY=$1
PROJECT_NAME=$2

# --- PASO 2: INICIO DE LOS SERVICIOS DE FONDO ---
echo "--- [1/4] Iniciando servicios de SonarQube y PostgreSQL (si no están corriendo)... ---"
docker compose up -d

# --- PASO 3: ESPERA ACTIVA DEL SERVIDOR ---
echo "--- [2/4] Esperando a que el servidor SonarQube esté completamente operativo... ---"
while [[ "$(curl -s -u admin:$SONAR_ADMIN_PASSWORD http://localhost:9000/api/system/status | jq -r '.status')" != "UP" ]]; do
    printf '.'
    sleep 5
done
echo -e "\n¡SonarQube está listo!"

# --- PASO 4: APROVISIONAMIENTO DEL NUEVO PROYECTO ---
echo "--- [3/4] Creando el nuevo proyecto en SonarQube... ---"
echo "Creando el proyecto '$PROJECT_NAME' con la clave '$PROJECT_KEY'..."

# --- !! BLOQUE CORREGIDO !! ---
# Usamos --data-urlencode para que curl maneje correctamente los espacios
# y otros caracteres especiales en los nombres de los proyectos.
curl -s -u admin:$SONAR_ADMIN_PASSWORD -X POST \
  --data-urlencode "name=$PROJECT_NAME" \
  --data-urlencode "project=$PROJECT_KEY" \
  "http://localhost:9000/api/projects/create" > /dev/null

# --- PASO 5: GENERACIÓN DE TOKEN PARA EL NUEVO PROYECTO ---
echo "--- [4/4] Generando un token de análisis para el nuevo proyecto... ---"
TOKEN=$(curl -s -u admin:$SONAR_ADMIN_PASSWORD -X POST "http://localhost:9000/api/user_tokens/generate?name=token-$PROJECT_KEY" | jq -r '.token')

# --- RESUMEN FINAL ---
echo ""
echo "========================================================================"
echo "  ¡NUEVO PROYECTO CREADO Y CONFIGURADO!"
echo "========================================================================"
echo "  Proyecto Creado: $PROJECT_KEY"
echo ""
echo "  TU NUEVO TOKEN DE ANÁLISIS ES (GUÁRDALO DE FORMA SEGURA):"
echo "  $TOKEN"
echo "========================================================================"
echo "  Para usar este token en un análisis, expórtalo en tu terminal:"
echo "  export SONAR_TOKEN=\"$TOKEN\""
echo "========================================================================"
echo ""
