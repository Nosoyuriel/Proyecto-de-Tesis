# DevSecOps Suite - Contenedor Único
# Imagen Docker con todas las herramientas integradas

FROM sonarqube:10.5.1-community

LABEL maintainer="DevSecOps Suite"
LABEL description="Suite de análisis de seguridad integrado"

# Evitar prompts interactivos
ENV DEBIAN_FRONTEND=noninteractive

# ============================================
# 1. INSTALAR DEPENDENCIAS ADICIONALES
# ============================================
USER root
RUN apt-get update && apt-get install -y \
    # Python y pip
    python3.11 \
    python3-pip \
    # Utilidades
    curl \
    wget \
    unzip \
    dos2unix \
    netcat \
    # Java para SonarScanner
    openjdk-17-jdk \
    && rm -rf /var/lib/apt/lists/*

# ============================================
# 2. INSTALAR PYTHON (Streamlit)
# ============================================
RUN pip3 install --no-cache-dir \
    streamlit \
    pandas

# ============================================
# 3. INSTALAR SONARSCANNER CLI
# ============================================
ENV SONARSCANNER_VERSION=5.0.1.3006
RUN mkdir -p /opt/sonar-scanner && \
    curl -sL "https://binaries.sonarsource.com/Distribution/sonar-scanner-cli/sonar-scanner-cli-${SONARSCANNER_VERSION}.zip" -o /tmp/scanner.zip && \
    unzip -q /tmp/scanner.zip -d /opt/sonar-scanner && \
    mv /opt/sonar-scanner/sonar-scanner-${SONARSCANNER_VERSION}/* /opt/sonar-scanner/ && \
    rm -rf /tmp/scanner.zip /opt/sonar-scanner/sonar-scanner-${SONARSCANNER_VERSION} && \
    ln -s /opt/sonar-scanner/bin/sonar-scanner /usr/local/bin/sonar-scanner && \
    chown -R sonarqube /opt/sonar-scanner

# ============================================
# 4. INSTALAR TRIVY
# ============================================
ENV TRIVY_VERSION=0.69.3
RUN wget -q https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_linux-64bit.tar.gz -O - | \
    tar -xzf - -C /usr/local/bin && \
    chmod +x /usr/local/bin/trivy

# ============================================
# 5. INSTALAR OWASP ZAP
# ============================================
ENV ZAP_VERSION=2.17.0
RUN mkdir -p /zap && \
    cd /zap && \
    wget -q https://github.com/zaproxy/zaproxy/releases/download/v${ZAP_VERSION}/ZAP_${ZAP_VERSION}_linux.tar.gz && \
    tar -xzf ZAP_${ZAP_VERSION}_linux.tar.gz && \
    mv ZAP_${ZAP_VERSION}/* . && \
    rm -rf ZAP_${ZAP_VERSION}* && \
    ln -s /zap/zap-baseline.py /usr/local/bin/zap-baseline.py && \
    chmod +x /zap/*.sh

# ============================================
# 6. COPIAR CÓDIGO DE LA APLICACIÓN
# ============================================
# Crear estructura de directorios como root
RUN mkdir -p /opt/sonarqube/app && chown -R sonarqube /opt/sonarqube/app

# Cambiar a usuario sonarqube
USER sonarqube
WORKDIR /opt/sonarqube/app

# Copiar aplicación Python
COPY --chown=sonarqube app.py /opt/sonarqube/app/
COPY --chown=sonarqube final_report.py /opt/sonarqube/app/
COPY --chown=sonarqube requirements.txt /opt/sonarqube/app/

# Copiar módulo CTI
COPY --chown=sonarqube cti/ /opt/sonarqube/app/cti/

# Copiar scripts de análisis
COPY --chown=sonarqube analyze.sh /opt/sonarqube/app/
COPY --chown=sonarqube setup_container.sh /opt/sonarqube/app/setup.sh

# Dar permisos de ejecución
RUN chmod +x /opt/sonarqube/app/*.sh

# Crear script de inicio
COPY --chown=sonarqube start.sh /opt/sonarqube/app/start.sh
RUN chmod +x /opt/sonarqube/app/start.sh

# ============================================
# 7. VARIABLES DE ENTORNO
# ============================================
ENV JAVA_HOME=/opt/java/openjdk
ENV PATH="/opt/sonar-scanner/bin:${PATH}"
ENV SONAR_HOST_URL=http://localhost:9000

# ============================================
# 8. EXPONER PUERTOS
# ============================================
EXPOSE 8501 9000

# ============================================
# 9. COMANDO DE INICIO
# ============================================
WORKDIR /opt/sonarqube/app
CMD ["/opt/sonarqube/app/start.sh"]
