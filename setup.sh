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

# Usar argumento o valor por defecto
PROJECT_KEY=${1:-DevSecOps1}
PROJECT_NAME=$(echo "$PROJECT_KEY" | sed 's/-/ /g' | sed 's/_/ /g')

echo "Usando nombre de proyecto: $PROJECT_KEY"

# 5a. Cambiar la contraseña de admin por defecto.
echo "Cambiando la contraseña de 'admin' por defecto..."
curl -s -u admin:admin -X POST "http://localhost:9000/api/users/change_password?login=admin&previousPassword=admin&password=sonar_admin_password"

# --- !! CORRECCIÓN CRUCIAL !! ---
# Añadimos un pequeño retraso para asegurar que el cambio de contraseña se procese.
echo "Esperando un momento para que el cambio de contraseña se aplique..."
sleep 5

# 5b. Crear el proyecto.
echo "Creando el proyecto '$PROJECT_KEY'..."
# Usamos la nueva contraseña para esta y las siguientes peticiones.
curl -s -u admin:sonar_admin_password -X POST "http://localhost:9000/api/projects/create?name=${PROJECT_NAME}&project=${PROJECT_KEY}"

# 5c. Generar un nuevo token para el proyecto.
echo "Generando token de análisis..."
TOKEN=$(curl -s -u admin:sonar_admin_password -X POST "http://localhost:9000/api/user_tokens/generate?name=devsecops-suite-token" | jq -r '.token')

# Guardar token y nombre del proyecto en archivos para facilitar el uso posterior
echo "export SONAR_TOKEN=\"$TOKEN\"" > .sonar_env
echo "$PROJECT_KEY" > .sonar_project

# --- RESUMEN FINAL ---
echo ""
echo "========================================================================"
echo "  ¡CONFIGURACIÓN AUTOMÁTICA COMPLETA!"
echo "========================================================================"
echo "  Proyecto Creado: $PROJECT_KEY"
echo "  Contraseña de admin cambiada a: sonar_admin_password"
echo ""
echo "  TU TOKEN DE ANÁLISIS ES:"
echo "  $TOKEN"
echo ""
echo "  Configuración guardada:"
echo "  - Token: .sonar_env"
echo "  - Proyecto: .sonar_project ($PROJECT_KEY)"
echo ""
echo "  El script analyze.sh cargará esta configuración automáticamente."
echo "  Si deseas especificar otro proyecto, usa:"
echo "  ./analyze.sh <ruta_proyecto> <project_key>"
echo "========================================================================"
echo ""
