# --- ETAPA 1: TRIVY BUILDER ---
# Extrae el binario de Trivy.
FROM aquasec/trivy:latest AS trivy_builder

# --- ETAPA 2: ZAP BUILDER ---
# Usamos la imagen oficial de ZAP para tener acceso a sus scripts de automatización.
FROM ghcr.io/zaproxy/zaproxy:stable AS zap_builder

# --- ETAPA 3: IMAGEN FINAL ---
# Imagen final que contendrá todas nuestras herramientas.
FROM eclipse-temurin:17-jre-focal

# --- Instalar dependencias adicionales ---
# ZAP requiere Python, así que lo instalamos.
RUN apt-get update && \
    apt-get install -y python3 python3-pip python-is-python3 && \
    pip3 install PyYAML python-owasp-zap-v2.4 && \
    rm -rf /var/lib/apt/lists/*

# --- Configuración de SonarScanner ---
ENV SONAR_SCANNER_HOME=/opt/sonar-scanner
ENV PATH="${SONAR_SCANNER_HOME}/bin:${PATH}"
COPY sonar-scanner-5.0.1.3006-linux ${SONAR_SCANNER_HOME}

# --- Configuración de Trivy ---
COPY --from=trivy_builder /usr/local/bin/trivy /usr/local/bin/trivy

# --- Configuración de OWASP ZAP ---
# Copiamos los scripts de escaneo de ZAP a /zap/ dentro de nuestra imagen.
COPY --from=zap_builder /zap/ /zap/
# Hacemos que los scripts sean ejecutables directamente desde el PATH.
RUN ln -s /zap/zap-baseline.py /usr/local/bin/zap-baseline.py

# --- Configuración Final del Contenedor ---
WORKDIR /scan
