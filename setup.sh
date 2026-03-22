#!/bin/bash
set -e

# --- PASO 1: LIMPIEZA DEL ENTORNO ANTERIOR ---
echo "--- [1/5] Limpiando cualquier ejecución anterior... ---"
docker compose down --volumes --remove-orphans

# --- PASO 2: CONSTRUCCIÓN DE LA IMAGEN DE HERRAMIENTAS ---
echo "--- [2/5] Construyendo la imagen 'devsecops-suite'... ---"
docker build -t devsecops-suite .

# --- PASO 3: INICIO DE LOS SERVICIOS DE FONDO ---
echo "--- [3/5] Iniciando servicios de SonarQube y PostgreSQL... ---"
docker compose up -d

# --- PASO 4: ESPERA ACTIVA DEL SERVIDOR ---
echo "--- [4/5] Esperando a que SonarQube esté operativo... ---"
while [[ "$(curl -s -u admin:admin http://localhost:9000/api/system/status | jq -r '.status')" != "UP" ]]; do
    printf '.'
    sleep 5
done
echo -e "\n¡SonarQube está listo!"

# --- PASO 5: APROVISIONAMIENTO AUTOMÁTICO VÍA API ---
echo "--- [5/5] Aprovisionando SonarQube... ---"

# 5a. Cambiar la contraseña de admin por defecto.
echo "Cambiando la contraseña de 'admin' por defecto..."
curl -s -u admin:admin -X POST "http://localhost:9000/api/users/change_password?login=admin&previousPassword=admin&password=sonar_admin_password"

# --- !! CORRECCIÓN CRUCIAL !! ---
# Añadimos un pequeño retraso para asegurar que el cambio de contraseña se procese.
echo "Esperando un momento para que el cambio de contraseña se aplique..."
sleep 5

# 5b. Crear el proyecto.
echo "Creando el proyecto 'DevSecOps1'..."
# Usamos la nueva contraseña para esta y las siguientes peticiones.
curl -s -u admin:sonar_admin_password -X POST "http://localhost:9000/api/projects/create?name=DevSecOps%20Project%201&project=DevSecOps1"

# 5c. Generar un nuevo token para el proyecto.
echo "Generando token de análisis..."
TOKEN=$(curl -s -u admin:sonar_admin_password -X POST "http://localhost:9000/api/user_tokens/generate?name=devsecops-suite-token" | jq -r '.token')

# --- RESUMEN FINAL ---
echo ""
echo "========================================================================"
echo "  ¡CONFIGURACIÓN AUTOMÁTICA COMPLETA!"
echo "========================================================================"
echo "  Proyecto Creado: DevSecOps1"
echo "  Contraseña de admin cambiada a: sonar_admin_password"
echo ""
echo "  TU TOKEN DE ANÁLISIS ES (GUÁRDALO DE FORMA SEGURA):"
echo "  $TOKEN"
echo "========================================================================"
echo "  Para usar el token, expórtalo en tu terminal:"
echo "  export SONAR_TOKEN=\"$TOKEN\""
echo "========================================================================"
echo ""
