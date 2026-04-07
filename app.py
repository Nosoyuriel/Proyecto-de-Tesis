"""
DevSecOps Suite - Interfaz Web Streamlit
Sistema de 3 pestañas para usuarios no técnicos
"""

import streamlit as st
import subprocess
import json
from pathlib import Path
import pandas as pd

# Importar módulo de mapeo ATT&CK
import sys
sys.path.insert(0, str(Path(__file__).parent / "cti"))
from mapper import ATTACKMapper

# Configuración de la página
st.set_page_config(
    page_title="DevSecOps Suite",
    page_icon="🛡️",
    layout="wide"
)

# Rutas
REPORTS_DIR = Path("reports")
MASTER_REPORT = REPORTS_DIR / "MASTER_REPORT.json"

# Funciones auxiliares
def load_master_report():
    """Carga el reporte maestro si existe."""
    if MASTER_REPORT.exists():
        with open(MASTER_REPORT, 'r') as f:
            return json.load(f)
    return None

def run_setup(project_name):
    """Ejecuta el script setup.sh con el nombre del proyecto como argumento."""
    with st.spinner("Ejecutando setup. Esto puede tardar varios minutos."):
        result = subprocess.run(
            [f"./setup.sh {project_name}"],
            capture_output=True,
            text=True,
            shell=True
        )
        return result.returncode == 0, result.stdout, result.stderr

def run_analysis(project_path, project_key):
    """Ejecuta el script analyze.sh."""
    with st.spinner("Ejecutando analisis completo. Esto puede tardar varios minutos."):
        result = subprocess.run(
            [f"./analyze.sh {project_path} {project_key}"],
            capture_output=True,
            text=True,
            shell=True
        )
        return result.returncode == 0, result.stdout, result.stderr

def load_project_config():
    """Carga la configuración del proyecto si existe."""
    project_name = ""
    if Path(".sonar_project").exists():
        project_name = Path(".sonar_project").read_text().strip()
    return project_name

def get_severity_emoji(severity):
    """Retorna emoji según severidad."""
    emoji_map = {
        "CRITICAL": "🔴",
        "HIGH": "🟠",
        "MEDIUM": "🟡",
        "LOW": "🟢",
        "MAJOR": "🟣",
        "INFO": "🔵",
        "MINOR": "⚪",
        "BLOCKER": "⛔",
        "TRIVIAL": "⚫"
    }
    return emoji_map.get(severity, "⚪")

# ============================================
# INTERFAZ CON PESTAÑAS
# ============================================

st.title("🛡️ DevSecOps Suite")
st.markdown("**Panel de control de seguridad para analisis de vulnerabilidades**")
st.markdown("---")

# Crear las 3 pestañas
tab1, tab2, tab3 = st.tabs([
    "🔧 Analisis y Configuracion",
    "📊 Dashboard de Resultados",
    "⚡ Extras"
])

# ============================================
# PESTAÑA 1: ANÁLISIS Y CONFIGURACIÓN
# ============================================
with tab1:
    # Sub-sección: Configuración
    st.subheader("Configuracion del Proyecto")

    col1, col2 = st.columns([3, 1])

    with col1:
        project_name = st.text_input(
            "Nombre del Proyecto SonarQube:",
            value=load_project_config(),
            placeholder="Ej: MiProyecto",
            help="Nombre del proyecto que se creará en SonarQube"
        )

    with col2:
        st.markdown("")
        st.markdown("")
        if st.button("✅ Nuevo Proyecto", type="primary", use_container_width=True):
            if not project_name:
                st.warning("⚠️ Por favor ingresa el nombre del proyecto.")
            else:
                success, stdout, stderr = run_setup(project_name)
                if success:
                    st.success("✅ Proyecto configurado exitosamente!")
                else:
                    st.error("❌ Error en la configuracion")
                    with st.expander("Ver error"):
                        st.text(stderr)

    # Estado actual
    if Path(".sonar_project").exists() and Path(".sonar_env").exists():
        col_a, col_b = st.columns(2)
        with col_a:
            st.info(f"**Proyecto:** {load_project_config()}")
        with col_b:
            st.info("**Token:** Configurado ✅")

    st.markdown("---")

    # Sub-sección: Análisis
    st.subheader("Ejecutar Analisis")

    col3, col4, col5 = st.columns([3, 1, 1])

    with col3:
        project_path = st.text_input(
            "Ruta del Proyecto a analizar:",
            value="/home/usuario/Documents/juice-shop",
            placeholder="/ruta/absoluta/al/proyecto",
            help="Ruta absoluta al código fuente a escanear"
        )

    with col4:
        st.markdown("")
        st.markdown("")
        if st.button("📂 Cargar", use_container_width=True):
            st.info("Escribe la ruta o usa el boton de analizar.")

    with col5:
        st.markdown("")
        st.markdown("")
        if st.button("▶️ Analizar", type="primary", use_container_width=True):
            if not load_project_config():
                st.warning("⚠️ Primero configura el proyecto.")
            elif not project_path:
                st.warning("⚠️ Por favor especifica la ruta del proyecto.")
            else:
                success, stdout, stderr = run_analysis(project_path, load_project_config())
                if success:
                    st.success("✅ Analisis completado! Ve a la pestana Dashboard para ver resultados.")
                else:
                    st.error("❌ Error en el analisis")
                    with st.expander("Ver error"):
                        st.text(stderr)

# ============================================
# PESTAÑA 2: DASHBOARD DE RESULTADOS
# ============================================
with tab2:
    st.subheader("Dashboard de Resultados")

    data = load_master_report()

    if data is None:
        st.info("ℹ️ No hay resultados disponibles. Ejecuta un analisis primero.")
    else:
        findings = data.get("findings", [])
        summary = data.get("scan_summary", {})

        # Detectar todas las severidades dinámicamente
        all_severities = sorted(set(f.get("severity", "UNKNOWN") for f in findings))
        severity_counts = {s: sum(1 for f in findings if f.get("severity") == s) for s in all_severities}

        total = len(findings)
        lines = summary.get("high_level_metrics", [{}])
        ncloc = next((m.get("value", "N/A") for m in lines if m.get("metric") == "ncloc"), "N/A")

        # Métricas generales en cards - una por cada severidad
        st.markdown("### Resumen General")

        cols = st.columns(len(all_severities) + 2)
        with cols[0]:
            st.metric("Total", total)
        for i, sev in enumerate(all_severities):
            with cols[i + 1]:
                emoji = get_severity_emoji(sev)
                st.metric(f"{emoji} {sev}", severity_counts[sev])
        with cols[-1]:
            st.metric("Lines", ncloc)

        # Gráfico de severidad con TODAS las severidades
        st.markdown("### Distribucion por Severidad")

        chart_data = pd.DataFrame({
            "Severidad": list(severity_counts.keys()),
            "Cantidad": list(severity_counts.values())
        })

        st.bar_chart(chart_data.set_index("Severidad"))

        # Gráfico por herramienta
        st.markdown("### Hallazgos por Herramienta")

        tool_counts = {}
        for f in findings:
            tool = f.get("tool", "Unknown")
            tool_counts[tool] = tool_counts.get(tool, 0) + 1

        tool_data = pd.DataFrame({
            "Herramienta": list(tool_counts.keys()),
            "Cantidad": list(tool_counts.values())
        })

        st.bar_chart(tool_data.set_index("Herramienta"))

        # Filtro avanzado de hallazgos
        st.markdown("### Filtro de Hallazgos")

        col_f1, col_f2 = st.columns(2)

        with col_f1:
            severity_filter = st.multiselect(
                "Severidad:",
                options=all_severities,
                default=all_severities
            )

        with col_f2:
            tool_filter = st.multiselect(
                "Herramienta:",
                options=list(set(f.get("tool", "") for f in findings)),
                default=list(set(f.get("tool", "") for f in findings))
            )

        # Aplicar filtros
        filtered_findings = [
            f for f in findings
            if f.get("severity") in severity_filter
            and f.get("tool") in tool_filter
        ]

        st.markdown(f"**Resultados filtrados:** {len(filtered_findings)} de {len(findings)}")

        # Botón de descarga JSON
        if MASTER_REPORT.exists():
            with open(MASTER_REPORT, 'r') as f:
                json_data = f.read()
            st.download_button(
                label="📥 Descargar Reporte JSON",
                data=json_data,
                file_name="MASTER_REPORT.json",
                mime="application/json"
            )

        # Mostrar hallazgos filtrados
        for finding in filtered_findings[:50]:
            severity = finding.get("severity", "N/A")
            severity_emoji = get_severity_emoji(severity)

            with st.expander(f"{severity_emoji} {finding.get('id', 'N/A')} - {finding.get('tool', 'N/A')}"):
                st.write(f"**Tipo:** {finding.get('type', 'N/A')}")
                st.markdown(f"**Mensaje:** {finding.get('message', 'N/A')}")

# ============================================
# PESTAÑA 3: EXTRAS
# ============================================
with tab3:
    # --- Sección de Mapeo MITRE ATT&CK ---
    st.markdown("---")
    st.markdown("### 🎯 Matriz MITRE ATT&CK")

    st.markdown("""
    Esta sección mapea las vulnerabilidades detectadas a las **técnicas y tácticas**
    del framework MITRE ATT&CK, ayudando a entender el impacto real de los hallazgos
    en términos de vectores de ataque conocidos.
    """)

    # Selector de archivo JSON
    col_m1, col_m2 = st.columns([2, 1])

    with col_m1:
        attack_file = st.file_uploader(
            "Carga un JSON con vulnerabilidades (CVE/CWE):",
            type=['json'],
            key="attack_file"
        )

    with col_m2:
        st.markdown("")
        st.markdown("")
        use_master = st.button("📊 Usar MASTER_REPORT", use_container_width=True)

    # Procesar archivo o MASTER_REPORT
    vuln_data = None
    if attack_file is not None:
        try:
            vuln_data = json.load(attack_file)
        except Exception as e:
            st.error(f"Error al leer el archivo: {e}")
    elif use_master and MASTER_REPORT.exists():
        with open(MASTER_REPORT, 'r') as f:
            vuln_data = json.load(f)

    if vuln_data:
        try:
            # Inicializar mapeador
            mapper = ATTACKMapper()

            # Generar reporte ATT&CK
            attack_report = mapper.generate_report(vuln_data)
            summary = attack_report["summary"]

            # Métricas de resumen
            st.markdown("#### Resumen de Mapeo")
            col_r1, col_r2, col_r3, col_r4 = st.columns(4)

            with col_r1:
                st.metric("Total Hallazgos", summary["total_findings"])
            with col_r2:
                st.metric("Mapeados", summary["mapped_findings"])
            with col_r3:
                st.metric("Técnicas Únicas", summary["unique_techniques"])
            with col_r4:
                st.metric("Tácticas", summary["unique_tactics"])

            # Distribución por táctica
            if attack_report["tactics"]:
                st.markdown("#### Distribución por Táctica ATT&CK")
                tactic_df = pd.DataFrame(attack_report["tactics"])
                st.bar_chart(tactic_df.set_index("tactic")["count"])

            # Tabla de técnicas detectadas
            if attack_report["techniques"]:
                st.markdown("#### Técnicas ATT&CK Detectadas")
                techniques_df = pd.DataFrame(attack_report["techniques"])
                st.dataframe(
                    techniques_df[["technique_id", "name", "tactic", "count"]],
                    use_container_width=True
                )

            # CWEs mapeados
            if attack_report["cwes"]:
                st.markdown("#### CWEs con Mapeo ATT&CK")
                cwes_df = pd.DataFrame(attack_report["cwes"])
                st.dataframe(
                    cwes_df[["id", "name", "techniques"]],
                    use_container_width=True
                )

        except Exception as e:
            st.error(f"Error al generar mapeo ATT&CK: {e}")

# ============================================
# FOOTER
# ============================================
st.markdown("---")
st.caption("DevSecOps Suite - Herramienta de analisis de seguridad | Powered by Streamlit")