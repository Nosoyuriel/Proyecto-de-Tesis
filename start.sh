#!/bin/bash
# DevSecOps Suite - Script de inicio
# Inicia Streamlit (SonarQube se inicia manualmente via setup.sh)

echo "=========================================="
echo "  DevSecOps Suite - Iniciando..."
echo "=========================================="

# Ir al directorio de la aplicación
cd /opt/sonarqube/app

echo "  Accede a la aplicación en:"
echo "  - http://localhost:8501 (Streamlit)"
echo "  - http://localhost:9000 (SonarQube - después de Setup)"
echo "=========================================="

# Iniciar Streamlit
streamlit run app.py \
    --server.address 0.0.0.0 \
    --server.port 8501 \
    --browser.gatherUsageStats false \
    --server.headless true
