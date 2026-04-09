#!/bin/bash
# DevSecOps Suite - Script de inicio
# Inicia Streamlit

echo "=========================================="
echo "  DevSecOps Suite - Iniciando..."
echo "=========================================="

echo "  Accede a la aplicación en:"
echo "  - http://localhost:8501 (Streamlit)"
echo "  - http://localhost:9000 (SonarQube)"
echo "=========================================="

streamlit run app.py \
    --server.address 0.0.0.0 \
    --server.port 8501 \
    --browser.gatherUsageStats false \
    --server.headless true