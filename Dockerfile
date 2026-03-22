# --- ETAPA 1: TRIVY BUILDER ---
# Extrae el binario de Trivy.
FROM aquasec/trivy:latest AS trivy_builder

# --- ETAPA 2: ZAP BUILDER ---
# Usamos la imagen oficial de ZAP para tener acceso a sus scripts de automatización.
FROM ghcr.io/zaproxy/zaproxy:stable AS zap_builder

# --- ETAPA 3: IMAGEN FINAL ---
FROM eclipse-temurin:17-jdk-focal

# --- Instalar dependencias ---
RUN apt-get update && apt-get install -y python3 python3-pip dos2unix curl && rm -rf /var/lib/apt/lists/*

# 2. Configuración de SonarScanner
ENV SONAR_SCANNER_HOME=/opt/sonar-scanner
COPY sonar-scanner-5.0.1.3006-linux ${SONAR_SCANNER_HOME}

RUN mkdir -p ${SONAR_SCANNER_HOME}/jre/bin && \
    ln -s $(which java) ${SONAR_SCANNER_HOME}/jre/bin/java && \
    dos2unix ${SONAR_SCANNER_HOME}/bin/sonar-scanner && \
    chmod -R +x ${SONAR_SCANNER_HOME}/bin/

# 4. Variables de entorno globales
ENV PATH="${SONAR_SCANNER_HOME}/bin:${PATH}"
# --- Configuración de Trivy ---
COPY --from=trivy_builder /usr/local/bin/trivy /usr/local/bin/trivy

# --- Configuración de OWASP ZAP ---
# Copiamos los scripts de escaneo de ZAP a /zap/ dentro de nuestra imagen.
COPY --from=zap_builder /zap/ /zap/
# Hacemos que los scripts sean ejecutables directamente desde el PATH.
RUN ln -s /zap/zap-baseline.py /usr/local/bin/zap-baseline.py

# --- Configuración Final del Contenedor ---
WORKDIR /scan

