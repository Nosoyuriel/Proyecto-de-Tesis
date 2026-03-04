import json
import os

# Configuración de rutas
REPORTS_DIR = "reports"
OUTPUT_FILE = os.path.join(REPORTS_DIR, "MASTER_REPORT.json")

def load_json(filename):
    path = os.path.join(REPORTS_DIR, filename)
    if os.path.exists(path):
        with open(path, 'r') as f:
            return json.load(f)
    return None

def process_trivy(data):
    results = []
    if data and "Results" in data:
        for res in data["Results"]:
            for vuln in res.get("Vulnerabilities", []):
                results.append({
                    "tool": "SCA (Trivy)",
                    "id": vuln.get("VulnerabilityID"),
                    "severity": vuln.get("Severity"),
                    "type": "Dependency Vulnerability",
                    "component": vuln.get("PkgName"),
                    "message": vuln.get("Title")
                })
    return results

def process_sonar(issues_data, hotspots_data):
    results = []
    # Procesar Issues (Vulnerabilidades y Bugs)
    if issues_data and "issues" in issues_data:
        for issue in issues_data["issues"]:
            results.append({
                "tool": "SAST (SonarQube)",
                "id": issue.get("rule"),
                "severity": issue.get("severity"),
                "type": issue.get("type"),
                "component": issue.get("component"),
                "message": issue.get("message")
            })
    # Procesar Hotspots
    if hotspots_data and "hotspots" in hotspots_data:
        for hotspot in hotspots_data["hotspots"]:
            results.append({
                "tool": "SAST (Sonar-Hotspot)",
                "id": hotspot.get("ruleKey"),
                "severity": hotspot.get("vulnerabilityProbability"),
                "type": "SECURITY_HOTSPOT",
                "component": hotspot.get("component"),
                "message": hotspot.get("message")
            })
    return results

def process_zap(data):
    results = []
    if data and "site" in data:
        for site in data["site"]:
            for alert in site.get("alerts", []):
                results.append({
                    "tool": "DAST (OWASP ZAP)",
                    "id": alert.get("pluginid"),
                    "severity": alert.get("riskdesc").split(" ")[0],
                    "type": "Dynamic Analysis Alert",
                    "component": site.get("@name"),
                    "message": alert.get("alert")
                })
    return results

def main():
    print("--- 🧠 Iniciando Consolidación de Inteligencia de Seguridad ---")
    
    # Cargar datos
    trivy_data = load_json("trivy_report.json")
    sonar_issues = load_json("sonar_issues.json")
    sonar_hotspots = load_json("sonar_hotspots.json")
    zap_data = load_json("zap_report.json")
    sonar_metrics = load_json("sonar_metrics.json")

    # Procesar cada fuente
    master_list = []
    master_list.extend(process_trivy(trivy_data))
    master_list.extend(process_sonar(sonar_issues, sonar_hotspots))
    master_list.extend(process_zap(zap_data))

    # Crear estructura final
    final_report = {
        "scan_summary": {
            "total_findings": len(master_list),
            "tools_consulted": ["Trivy", "SonarQube", "OWASP ZAP"],
            "high_level_metrics": sonar_metrics.get("component", {}).get("measures", []) if sonar_metrics else []
        },
        "findings": master_list
    }

    # Guardar MASTER REPORT
    with open(OUTPUT_FILE, 'w') as f:
        json.dump(final_report, f, indent=4)

    print(f"--- ✅ ÉXITO: {len(master_list)} hallazgos consolidados en {OUTPUT_FILE} ---")

if __name__ == "__main__":
    main()