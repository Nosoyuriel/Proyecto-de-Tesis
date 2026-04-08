#!/bin/bash

# --- DevSecOps Suite - Setup para Contenedor Único ---
# Este script inicia SonarQube embebido (H2) y aprovisiona el proyecto
# NO usa Docker ni PostgreSQL - SonarQube ya viene embebido en la imagen

echo "========================================================================"
echo "  DevSecOps Suite - Configuración del Contenedor Único"
echo "========================================================================"
echo ""

# --- PASO 1: LIMPIEZA DEL ENTORNO ANTERIOR ---
echo "--- [1/5] Limpiando cualquier ejecución anterior..."
# Matar cualquier proceso de SonarQube existente
pkill -f "sonarqube.jar" 2>/dev/null || true
sleep 2

# --- PASO 2: INICIAR SONARQUBE EMBEBIDO ---
echo "--- [2/5] Iniciando SonarQube embebido (H2)..."

# Verificar que el JAR existe
if [ ! -f "/opt/sonarqube/lib/sonarqube.jar" ]; then
    echo "ERROR: No se encontró /opt/sonarqube/lib/sonarqube.jar"
    exit 1
fi

# Limpiar logs anteriores
rm -f /opt/sonarqube/logs/sonar.log 2>/dev/null || true

# Iniciar SonarQube en segundo plano
echo "Iniciando SonarQube via Java..."
cd /opt/sonarqube
nohup /opt/java/openjdk/bin/java -jar /opt/sonarqube/lib/sonarqube.jar -Dsonar.log.console=true -Dsonar.log.level=DEBUG > /opt/sonarqube/logs/sonar.log 2>&1 &
SONAR_PID=$!
echo "SonarQube iniciado con PID: $SONAR_PID"

# --- PASO 3: ESPERA ACTIVA DEL SERVIDOR ---
echo "--- [3/5] Esperando a que SonarQube esté operativo..."
SONAR_URL="http://localhost:9000"
MAX_RETRIES=90
RETRY_COUNT=0

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    STATUS=$(curl -s -u admin:admin ${SONAR_URL}/api/system/status 2>/dev/null | jq -r '.status' 2>/dev/null || echo "UNKNOWN")
    if [ "$STATUS" = "UP" ]; then
        echo -e "\n¡SonarQube está listo!"
        break
    fi
    printf '.'
    RETRY_COUNT=$((RETRY_COUNT + 1))
    sleep 5
done

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
    echo -e "\nERROR: SonarQube no respondió después de ${MAX_RETRIES} intentos"
    echo "Último estado recibido: $STATUS"
    echo "Revisando log de SonarQube:"
    tail -50 /opt/sonarqube/logs/sonar.log 2>/dev/null || echo "No hay log disponible"
    exit 1
fi

# Espera adicional crítica para que H2 complete inicialización
echo "Esperando 15 segundos para que la base de datos H2 complete inicialización..."
sleep 15

# --- PASO 4: APROVISIONAMIENTO AUTOMÁTICO VÍA API ---
echo "--- [4/5] Aprovisionando SonarQube..."

# Usar argumento o valor por defecto
PROJECT_KEY=${1:-DevSecOps1}
PROJECT_NAME=$(echo "$PROJECT_KEY" | sed 's/-/ /g' | sed 's/_/ /g')

echo "Usando nombre de proyecto: $PROJECT_KEY"

# 4a. Verificar que el API responde correctamente
echo "Verificando conexión al API..."
PING_RESPONSE=$(curl -s -u admin:admin ${SONAR_URL}/api/system/ping)
echo "Ping response: $PING_RESPONSE"

# 4b. Cambiar la contraseña de admin por defecto.
echo "Cambiando la contraseña de 'admin' por defecto..."
echo "URL: ${SONAR_URL}/api/users/change_password?login=admin&previousPassword=admin&password=sonar_admin_password"
PASSWORD_RESPONSE=$(curl -s -w "\nHTTP_CODE:%{http_code}" -u admin:admin -X POST "${SONAR_URL}/api/users/change_password?login=admin&previousPassword=admin&password=sonar_admin_password")
echo "Respuesta cambio contraseña: $PASSWORD_RESPONSE"

# Pequeño retraso para que el cambio de contraseña se aplique
echo "Esperando 5 segundos para que el cambio de contraseña se aplique..."
sleep 5

# 4c. Crear el proyecto.
echo "Creando el proyecto '$PROJECT_KEY'..."
PROJECT_RESPONSE=$(curl -s -w "\nHTTP_CODE:%{http_code}" -u admin:sonar_admin_password -X POST "${SONAR_URL}/api/projects/create?name=${PROJECT_NAME}&project=${PROJECT_KEY}")
echo "Respuesta crear proyecto: $PROJECT_RESPONSE"

# 4d. Generar un nuevo token para el proyecto.
echo "Generando token de análisis..."
TOKEN_RESPONSE=$(curl -s -w "\nHTTP_CODE:%{http_code}" -u admin:sonar_admin_password -X POST "${SONAR_URL}/api/user_tokens/generate?name=devsecops-suite-token")
echo "Respuesta generar token: $TOKEN_RESPONSE"
TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.token')

# Guardar token y nombre del proyecto en archivos para facilitar el uso posterior
cd /opt/sonarqube/app
echo "export SONAR_TOKEN=\"$TOKEN\"" > .sonar_env
echo "$PROJECT_KEY" > .sonar_project

# --- PASO 5: RESUMEN FINAL ---
echo "--- [5/5] Configuración completada..."
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
echo "  Accede a SonarQube en: http://localhost:9000"
echo "  Accede a la app en:   http://localhost:8501"
echo "========================================================================"
echo ""
