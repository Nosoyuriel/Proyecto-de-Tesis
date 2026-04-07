"""
MITRE ATT&CK Mapper for DevSecOps Suite
Módulo genérico para mapear vulnerabilidades (CVEs/CWEs) a técnicas ATT&CK
"""

import json
import re
from pathlib import Path
from typing import List, Dict, Optional, Any


class ATTACKMapper:
    """Mapeador genérico de vulnerabilidades a MITRE ATT&CK."""

    def __init__(self, mapping_path: str = None):
        """
        Inicializa el mapeador.

        Args:
            mapping_path: Ruta al archivo attack_mapping.json.
                         Si es None, busca en el directorio del módulo.
        """
        if mapping_path is None:
            mapping_path = Path(__file__).parent / "attack_mapping.json"

        self.mapping = self._load_mapping(mapping_path)
        self.cwe_map = self.mapping.get("cwe_to_techniques", {})
        self.cve_map = self.mapping.get("cve_to_techniques", {})
        self.technique_details = self.mapping.get("techniques", {})
        self.tactics = self.mapping.get("tactics", {})

    def _load_mapping(self, path: str) -> dict:
        """Carga el archivo JSON de mapeo."""
        with open(path, 'r', encoding='utf-8') as f:
            return json.load(f)

    def _extract_cwe_ids(self, text: str) -> List[str]:
        """
        Extrae todos los CWE IDs de un texto.

        Args:
            text: Texto que puede contener CWE IDs (ej: "CWE-79", "CWE-89")

        Returns:
            Lista de CWE IDs encontrados (ej: ["CWE-79", "CWE-89"])
        """
        if not text:
            return []

        pattern = r'CWE[-_]?(\d+)'
        matches = re.findall(pattern, str(text), re.IGNORECASE)
        return [f"CWE-{m}" for m in matches]

    def _extract_cve_ids(self, text: str) -> List[str]:
        """
        Extrae todos los CVE IDs de un texto.

        Args:
            text: Texto que puede contener CVE IDs (ej: "CVE-2021-44228")

        Returns:
            Lista de CVE IDs encontrados
        """
        if not text:
            return []

        pattern = r'CVE[-_]?(\d{4})[-_]?(\d+)'
        matches = re.findall(pattern, str(text), re.IGNORECASE)
        return [f"CVE-{year}-{num}" for year, num in matches]

    def _find_in_dict(self, data: Any, pattern: str) -> List[str]:
        """
        Busca recursivamente un patrón en un diccionario/lista.

        Args:
            data: Datos a buscar
            pattern: Patrón a buscar (CWE- o CVE-)

        Returns:
            Lista de strings que contienen el patrón
        """
        results = []

        if isinstance(data, dict):
            for key, value in data.items():
                results.extend(self._find_in_dict(value, pattern))
        elif isinstance(data, list):
            for item in data:
                results.extend(self._find_in_dict(item, pattern))
        elif isinstance(data, str):
            if pattern.upper() in data.upper():
                results.append(data)

        return results

    def extract_vulnerability_ids(self, data: dict) -> Dict[str, List[str]]:
        """
        Extrae todos los IDs de vulnerabilidad (CWE/CVE) de un JSON.

        Args:
            data: Diccionario JSON con vulnerabilidades

        Returns:
            Diccionario con 'cwes' y 'cves' como listas
        """
        all_strings = self._find_in_dict(data, "CWE")
        all_cves = self._find_in_dict(data, "CVE")

        cwe_ids = []
        for s in all_strings:
            cwe_ids.extend(self._extract_cwe_ids(s))

        return {
            "cwes": list(set(cwe_ids)),
            "cves": list(set(all_cves))
        }

    def map_cwe_to_attack(self, cwe_id: str) -> Optional[Dict]:
        """
        Mapea un CWE ID a técnicas ATT&CK.

        Args:
            cwe_id: ID del CWE (ej: "CWE-79")

        Returns:
            Diccionario con técnicas y detalles, o None si no hay mapeo
        """
        cwe_normalized = cwe_id.upper()

        if not cwe_normalized.startswith("CWE-"):
            cwe_normalized = f"CWE-{cwe_normalized}"

        if cwe_normalized in self.cwe_map:
            entry = self.cwe_map[cwe_normalized]
            techniques = entry.get("techniques", [])

            technique_details = []
            for tech_id in techniques:
                if tech_id in self.technique_details:
                    tech_info = self.technique_details[tech_id].copy()
                    tech_info["id"] = tech_id
                    technique_details.append(tech_info)

            return {
                "cwe_id": cwe_normalized,
                "cwe_name": entry.get("name", "Unknown"),
                "techniques": technique_details,
                "cwe_description": entry.get("description", "")
            }

        return None

    def map_cve_to_attack(self, cve_id: str) -> Optional[Dict]:
        """
        Mapea un CVE ID a técnicas ATT&CK.

        Args:
            cve_id: ID del CVE (ej: "CVE-2021-44228")

        Returns:
            Diccionario con técnicas y detalles, o None si no hay mapeo
        """
        cve_normalized = cve_id.upper()

        if not cve_normalized.startswith("CVE-"):
            cve_normalized = f"CVE-{cve_normalized}"

        if cve_normalized in self.cve_map:
            entry = self.cve_map[cve_normalized]
            techniques = entry.get("techniques", [])

            technique_details = []
            for tech_id in techniques:
                if tech_id in self.technique_details:
                    tech_info = self.technique_details[tech_id].copy()
                    tech_info["id"] = tech_id
                    technique_details.append(tech_info)

            return {
                "cve_id": cve_normalized,
                "techniques": technique_details
            }

        return None

    def map_finding(self, finding: Dict) -> Optional[Dict]:
        """
        Mapea un finding (vulnerabilidad) a ATT&CK.

        Args:
            finding: Diccionario con campos como 'id', 'message', 'type', etc.

        Returns:
            Diccionario con mapeo ATT&CK o None
        """
        vulnerability_ids = self.extract_vulnerability_ids(finding)

        mapped_techniques = []
        mapped_cwes = []
        mapped_cves = []

        # Primero: mapear CWEs
        for cwe_id in vulnerability_ids["cwes"]:
            mapping = self.map_cwe_to_attack(cwe_id)
            if mapping:
                mapped_techniques.extend(mapping["techniques"])
                mapped_cwes.append({
                    "id": cwe_id,
                    "name": mapping["cwe_name"],
                    "techniques": [t["id"] for t in mapping["techniques"]]
                })

        # Si no hay CWEs, buscar CVEs en el ID del finding
        if not mapped_techniques:
            finding_id = finding.get("id", "")
            cve_ids = self._extract_cve_ids(finding_id)
            for cve_id in cve_ids:
                mapping = self.map_cve_to_attack(cve_id)
                if mapping:
                    mapped_techniques.extend(mapping["techniques"])
                    mapped_cves.append({
                        "id": cve_id,
                        "techniques": [t["id"] for t in mapping["techniques"]]
                    })

        if not mapped_techniques:
            return None

        unique_techniques = []
        seen = set()
        for tech in mapped_techniques:
            if tech["id"] not in seen:
                seen.add(tech["id"])
                unique_techniques.append(tech)

        return {
            "finding_id": finding.get("id", "unknown"),
            "severity": finding.get("severity", "UNKNOWN"),
            "message": finding.get("message", ""),
            "cwes": mapped_cwes,
            "cves": mapped_cves,
            "techniques": unique_techniques
        }

    def generate_report(self, data: dict) -> Dict:
        """
        Genera un reporte completo de mapeo ATT&CK.

        Args:
            data: JSON con vulnerabilidades (puede ser MASTER_REPORT,
                  trivy report, o cualquier JSON con CVEs/CWEs)

        Returns:
            Diccionario con resumen de técnicas y tácticas detectadas
        """
        if "findings" in data:
            findings = data["findings"]
        elif isinstance(data, list):
            findings = data
        else:
            findings = [data]

        attack_mappings = []
        techniques_count = {}
        tactics_count = {}
        cwes_found = {}

        for finding in findings:
            mapping = self.map_finding(finding)
            if mapping:
                attack_mappings.append(mapping)

                for tech in mapping["techniques"]:
                    tech_id = tech["id"]
                    tech_name = tech.get("name", "")
                    tactic = tech.get("tactic", "")

                    techniques_count[tech_id] = techniques_count.get(tech_id, 0) + 1
                    tactics_count[tactic] = tactics_count.get(tactic, 0) + 1

                for cwe in mapping["cwes"]:
                    cwe_id = cwe["id"]
                    if cwe_id not in cwes_found:
                        cwes_found[cwe_id] = cwe

        techniques_list = []
        for tech_id, count in sorted(techniques_count.items(),
                                      key=lambda x: x[1],
                                      reverse=True):
            if tech_id in self.technique_details:
                techniques_list.append({
                    "technique_id": tech_id,
                    "name": self.technique_details[tech_id]["name"],
                    "tactic": self.technique_details[tech_id]["tactic"],
                    "count": count,
                    "description": self.technique_details[tech_id]["description"]
                })

        tactics_list = []
        for tactic_name, count in sorted(tactics_count.items(),
                                         key=lambda x: x[1],
                                         reverse=True):
            if tactic_name in self.tactics:
                tactics_list.append({
                    "tactic": tactic_name,
                    "description": self.tactics[tactic_name]["description"],
                    "count": count
                })

        return {
            "summary": {
                "total_findings": len(findings),
                "mapped_findings": len(attack_mappings),
                "unique_techniques": len(techniques_count),
                "unique_tactics": len(tactics_count),
                "unique_cwes": len(cwes_found)
            },
            "techniques": techniques_list,
            "tactics": tactics_list,
            "cwes": list(cwes_found.values()),
            "mappings": attack_mappings[:100]
        }


def load_mapper(mapping_path: str = None) -> ATTACKMapper:
    """Función helper para cargar el mapeador."""
    return ATTACKMapper(mapping_path)
