#!/usr/bin/env python
from __future__ import annotations

import base64
import json
import ssl
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path


OUTPUT_DIR = Path(
    r"C:\Users\samue\OneDrive - Leu Numismatik\Dokumente\Test Final Consignor App"
)
MANIFESTS = ["manifest_07022238.json", "manifest_07022242.json"]
CONTRACT_STORAGE = "f8caf8f8-07e4-84f8-524d-674a217eb483"


def load_config() -> dict[str, str]:
    root = ET.parse(r"C:\repos\Leu\backoffice\Web.config").getroot()
    return {
        node.attrib["key"]: node.attrib["value"]
        for node in root.findall("./appSettings/add")
        if "key" in node.attrib and "value" in node.attrib
    }


def get_token(values: dict[str, str], context: ssl.SSLContext) -> str:
    request = urllib.request.Request(
        values["OAuth:TokenUrl"],
        data=b"grant_type=client_credentials",
        method="POST",
    )
    basic = base64.b64encode(
        f"{values['OAuth:ClientId']}:{values['OAuth:ClientSecret']}".encode()
    ).decode()
    request.add_header("Authorization", f"Basic {basic}")
    request.add_header("Content-Type", "application/x-www-form-urlencoded")
    with urllib.request.urlopen(request, context=context, timeout=60) as response:
        return json.loads(response.read().decode("utf-8"))["access_token"]


def main() -> int:
    records = []
    for name in MANIFESTS:
        path = OUTPUT_DIR / name
        if path.exists():
            records.extend(json.loads(path.read_text(encoding="utf-8"))["records"])

    commercial = [
        record
        for record in records
        if record["scenario"].startswith("LegalEntity")
        or record["scenario"].startswith("SoleProprietor")
    ]

    context = ssl._create_unverified_context()
    values = load_config()
    token = get_token(values, context)
    base_url = values["OAuth:BaseUrl"].rstrip("/") + "/"
    results = []

    for record in commercial:
        subject_id = record["abacusSubjectId"]
        filter_value = f"SubjectId eq {subject_id}"
        path = (
            "entity/v1/mandants/1000/SubjectDocuments"
            "?$select=Name,SubjectId,StorageId"
            "&$filter="
            + urllib.parse.quote(filter_value, safe="")
        )
        request = urllib.request.Request(
            base_url + path,
            headers={
                "Authorization": f"Bearer {token}",
                "Accept": "application/json",
            },
        )
        with urllib.request.urlopen(request, context=context, timeout=60) as response:
            data = json.loads(response.read().decode("utf-8"))

        names = sorted(
            document.get("Name")
            for document in data.get("value", [])
            if str(document.get("StorageId", "")).lower() == CONTRACT_STORAGE
        )
        results.append(
            {
                "contract": record["contractNumber"],
                "subject": subject_id,
                "hasCommercialRegister": "Commercial-Register.png" in names,
                "contractStorageNames": names,
            }
        )

    print(
        json.dumps(
            {
                "checked": len(results),
                "missing": [
                    result for result in results if not result["hasCommercialRegister"]
                ],
                "results": results,
            },
            indent=2,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
