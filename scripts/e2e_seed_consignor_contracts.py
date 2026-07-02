#!/usr/bin/env python
"""Seed E2E consignor contract scenarios through the Consignor App API.

The bearer token is intentionally read from LEU_E2E_BEARER so it never needs to
be written to disk. The script creates clear mock consignors, renders the
official backend PDFs, uploads the contract/passport/product files with the
current Abacus dossier naming rules, and writes a manifest beside the PDFs.
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import re
import ssl
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from PIL import Image, ImageDraw, ImageFont
from pypdf import PdfReader


DEFAULT_BASE_URL = "https://localhost:44364"
DEFAULT_OUTPUT_DIR = (
    r"C:\Users\samue\OneDrive - Leu Numismatik\Dokumente\Test Final Consignor App"
)
YEAR_CODE = "26"

PASSPORT_STORAGE = {
    "lookupText": "Passport",
    "storageId": "39c1d257-327c-bb79-0408-9be8b5a1dcca",
    "abbreviation": "PASS",
    "documentsEndpoint": "SubjectDocuments",
}
PRODUCT_STORAGE = {
    "lookupText": "Einlieferung Fotos",
    "storageId": "56d62f82-6053-d8b8-1dc8-abd6970e5aaf",
    "abbreviation": "EINL",
    "documentsEndpoint": "SubjectDocuments",
}
CONTRACT_STORAGE = {
    "lookupText": "Vertrag Einlieferung",
    "storageId": "f8caf8f8-07e4-84f8-524d-674a217eb483",
    "abbreviation": "VERT",
    "documentsEndpoint": "SubjectDocuments",
}


@dataclass(frozen=True)
class Scenario:
    index: int
    slug: str
    consignor_type: str
    representative_type: str | None = None
    provisional: bool = False

    @property
    def has_representative(self) -> bool:
        return self.representative_type is not None


SCENARIOS = [
    Scenario(1, "NaturalPerson_Self", "NaturalPerson"),
    Scenario(2, "NaturalPerson_ByNaturalRepresentative", "NaturalPerson", "NaturalPerson"),
    Scenario(3, "NaturalPerson_ByLegalRepresentative", "NaturalPerson", "LegalEntity"),
    Scenario(4, "LegalEntity_ByNaturalRepresentative", "LegalEntity", "NaturalPerson"),
    Scenario(5, "LegalEntity_ByLegalRepresentative", "LegalEntity", "LegalEntity"),
    Scenario(6, "SoleProprietor_Self", "SoleProprietor"),
    Scenario(7, "SoleProprietor_ByNaturalRepresentative", "SoleProprietor", "NaturalPerson"),
    Scenario(8, "SoleProprietor_ByLegalRepresentative", "SoleProprietor", "LegalEntity"),
]
PROVISIONAL_SCENARIO = Scenario(
    9,
    "Provisional_NaturalPerson_Self",
    "NaturalPerson",
    provisional=True,
)


class ApiClient:
    def __init__(self, base_url: str, bearer: str, timeout: int) -> None:
        self.base_url = base_url.rstrip("/")
        self.bearer = bearer.strip()
        self.timeout = timeout
        self.context = ssl._create_unverified_context()

    def get_json(self, path: str) -> Any:
        return self._request_json("GET", path)

    def post_json(self, path: str, payload: Any, expected: tuple[int, ...] = (200, 201)) -> Any:
        return self._request_json("POST", path, payload=payload, expected=expected)

    def post_bytes(self, path: str, payload: Any, expected: tuple[int, ...] = (200,)) -> bytes:
        body = json.dumps(payload).encode("utf-8")
        request = urllib.request.Request(
            self.base_url + path,
            data=body,
            method="POST",
            headers=self._headers("application/json"),
        )
        try:
            with urllib.request.urlopen(request, timeout=self.timeout, context=self.context) as response:
                if response.status not in expected:
                    raise RuntimeError(f"Unexpected HTTP {response.status} for POST {path}")
                return response.read()
        except urllib.error.HTTPError as exc:
            error_body = exc.read().decode("utf-8", errors="replace")
            raise RuntimeError(f"HTTP {exc.code} for POST {path}: {error_body[:1000]}") from exc

    def _request_json(
        self,
        method: str,
        path: str,
        payload: Any | None = None,
        expected: tuple[int, ...] = (200,),
    ) -> Any:
        body = None if payload is None else json.dumps(payload).encode("utf-8")
        request = urllib.request.Request(
            self.base_url + path,
            data=body,
            method=method,
            headers=self._headers("application/json"),
        )
        try:
            with urllib.request.urlopen(request, timeout=self.timeout, context=self.context) as response:
                raw = response.read()
                if response.status not in expected:
                    raise RuntimeError(f"Unexpected HTTP {response.status} for {method} {path}")
                if not raw:
                    return None
                return json.loads(raw.decode("utf-8"))
        except urllib.error.HTTPError as exc:
            error_body = exc.read().decode("utf-8", errors="replace")
            raise RuntimeError(f"HTTP {exc.code} for {method} {path}: {error_body[:1000]}") from exc

    def _headers(self, content_type: str) -> dict[str, str]:
        return {
            "Authorization": f"Bearer {self.bearer}",
            "Content-Type": content_type,
            "Accept": "application/json, application/pdf",
        }


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


def iso(dt: datetime) -> str:
    return dt.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


def country(code: str, name: str) -> dict[str, str]:
    return {"isoCountryCode": code, "countryName": name}


def person(
    first: str,
    last: str,
    *,
    owner: bool = True,
    dob: str = "1984-04-18T00:00:00Z",
    nationality_code: str = "CHE",
    nationality_name: str = "Switzerland",
) -> dict[str, Any]:
    return {
        "titleId": None,
        "salutationId": 2,
        "firstName": first,
        "lastName": last,
        "owner": owner,
        "dateOfBirth": dob,
        "nationality": country(nationality_code, nationality_name),
    }


def address(seed: int) -> dict[str, Any]:
    return {
        "streetAddress": "E2E Teststrasse",
        "streetAddressOptional": f"Scenario {seed}",
        "houseNumber": str(10 + seed),
        "postalCode": "8400",
        "adminregion": "ZH",
        "country": country("CHE", "Switzerland"),
        "city": "Winterthur",
    }


def banking(first: str, last: str, seed: int) -> dict[str, Any]:
    return {
        "bankName": "UBS Switzerland AG",
        "bankCountry": country("CHE", "Switzerland"),
        "bankAddress": {
            "streetAddress": "Bahnhofstrasse",
            "streetAddressOptional": "",
            "houseNumber": "45",
            "postalCode": "8001",
            "adminregion": "ZH",
            "country": country("CHE", "Switzerland"),
            "city": "Zurich",
        },
        "accountNumber": "CH9300762011623852957",
        "isIban": True,
        "bicSwift": "UBSWCHZH80A",
        "clearingNumber": "",
        "routingNumber": "",
        "beneficiary": person(first, last, dob="1980-01-01T00:00:00Z"),
        "beneficiaryAddress": address(seed),
    }


def compact_name(value: str) -> str:
    return re.sub(r"[^A-Za-z0-9]+", "", value)


def display_parts(slug: str) -> tuple[str, str]:
    if "_By" in slug:
        first, second = slug.split("_By", 1)
        return first, "By" + second
    if "_" in slug:
        first, second = slug.split("_", 1)
        return first, second
    return slug, "Scenario"


def make_consignor(
    scenario: Scenario,
    language: str,
    run_id: str,
    sequence: int,
    *,
    representative: bool = False,
    representative_type: str | None = None,
) -> dict[str, Any]:
    active_type = representative_type or scenario.consignor_type
    first_base, last_base = display_parts(scenario.slug)
    role = "Representative" if representative else "Consignor"
    language_label = language.upper()
    first = f"{first_base}{role}"
    last = f"{last_base}{language_label}{run_id}"
    trading_name = ""
    is_legal = active_type == "LegalEntity"
    is_sole = active_type == "SoleProprietor"
    if is_legal:
        trading_name = f"E2E {language_label} {scenario.slug} {role} AG {run_id}"
        first = f"{first_base}{role}Contact"
    elif is_sole:
        trading_name = f"E2E {language_label} {scenario.slug} Sole Firm {run_id}"

    if scenario.provisional and not representative:
        first = "ProvisionalConsignor"
        last = f"NaturalPersonSelf{language_label}{run_id}"

    email = f"e2e-{run_id.lower()}-{language}-{sequence}-{role.lower()}@example.com"
    username = f"E2E{run_id}{language_label}{sequence}{role[0]}"
    passport_valid_until = "2025-12-31T00:00:00Z" if sequence % 5 == 0 else "2032-12-31T00:00:00Z"
    payload = {
        "id": f"{run_id}-{language}-{sequence}-{role.lower()}",
        "systemReferenceConsignor": 0,
        "systemReferenceCustomer": 0,
        "abacusSubjectId": None,
        "existingCustomerId": None,
        "existingCustomerLabel": None,
        "isLegalEntity": is_legal,
        "isSoleProprietor": is_sole,
        "consignorType": active_type,
        "tradingName": trading_name or None,
        "consignorInfo": person(first, last, owner=True),
        # Abacus validates RegisteredCompanyUID strictly for organisations.
        # These are mock companies, so leave VAT empty instead of inventing an
        # invalid UID that prevents legal entities from being created.
        "vatLiability": False,
        "vatNumber": None,
        "phonePrefix": "+41",
        "phonePrefixOriginId": None,
        "phoneNumber": f"+41 52 555 {sequence:04d}",
        "emailAddress": email,
        "consignorAddress": address(sequence),
        "bankingDetails": banking(first, last, sequence),
        "bankingDetailsDto": banking(first, last, sequence),
        "paymentOption": "BankTransfer",
        "passportValidUntil": passport_valid_until,
        "checkedByLeu": True,
        "ancientCoinsSubscribed": True,
        "worldCoinsSubscribed": True,
        "newsletterSubscribed": False,
        "collectingArea": "E2E mock coins",
        "correspondence": language,
        "references": f"E2E final consignor app run {run_id} scenario {scenario.slug}",
        "creditLimit": 500000,
        "discount": 15.0,
        "consignmentFeeFloorAuction": 12.5,
        "consignmentFeeWebAuction": 10.0,
        "eori": f"CHEE2E{run_id}{sequence:02d}" if active_type in {"LegalEntity", "SoleProprietor"} else None,
        "username": username,
        "password": "E2Epass26!",
        "lastModifiedUtc": iso(utc_now()),
        "syncStatus": "pendingSync",
        "synced": False,
    }
    return payload


def add_representative_link(consignor: dict[str, Any], representative: dict[str, Any]) -> None:
    consignor["abacusRepresentativeLink"] = {
        "queueForAbacus": True,
        "target": "LinkedAddress",
        "trigger": "ConsignorSync",
        "relation": "Representative",
        "linksEndpoint": "Links",
        "sourceSubjectIdField": "mainConsignor.systemReferenceCustomer",
        "targetSubjectId": None,
        "targetExistingCustomerId": None,
        "targetExistingCustomerLabel": None,
        "representative": representative,
        "linkTypeIds": {
            "test": "e174dc18-df58-ff73-edec-742a9302ec72",
            "production": "e174dc18-df58-ff73-edec-742a9302ec72",
        },
        "verifyExistingFilter": "SourceSubjectId eq {sourceSubjectId} and LinkTypeId eq {linkTypeId}",
        "retry": {"maxAttempts": 3, "logBackofficeError": True},
    }


def font(size: int) -> ImageFont.ImageFont:
    for candidate in ("arial.ttf", "segoeui.ttf", "calibri.ttf"):
        try:
            return ImageFont.truetype(candidate, size)
        except OSError:
            pass
    return ImageFont.load_default()


def write_labeled_image(path: Path, title: str, lines: list[str], *, color: tuple[int, int, int]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image = Image.new("RGB", (1400, 900), (248, 250, 252))
    draw = ImageDraw.Draw(image)
    draw.rectangle((0, 0, 1400, 120), fill=color)
    draw.text((48, 34), title, fill="white", font=font(42))
    draw.rounded_rectangle((46, 170, 1354, 815), radius=18, outline=color, width=5)
    y = 215
    for line in lines:
        draw.text((92, y), line, fill=(20, 31, 47), font=font(32))
        y += 58
    draw.line((92, 760, 600, 760), fill=color, width=4)
    draw.text((92, 780), "Mock image for Consignor App E2E", fill=(71, 85, 105), font=font(24))
    image.save(path, "PNG")


def write_signature(path: Path, name: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image = Image.new("RGBA", (900, 280), (255, 255, 255, 0))
    draw = ImageDraw.Draw(image)
    draw.line((90, 180, 780, 180), fill=(14, 30, 58, 255), width=5)
    draw.text((120, 90), name, fill=(14, 30, 58, 255), font=font(54))
    image.save(path, "PNG")


def b64(path: Path) -> str:
    return base64.b64encode(path.read_bytes()).decode("ascii")


def content_type(path: Path) -> str:
    suffix = path.suffix.lower()
    if suffix == ".pdf":
        return "application/pdf"
    if suffix == ".png":
        return "image/png"
    if suffix in {".jpg", ".jpeg"}:
        return "image/jpeg"
    return "application/octet-stream"


def attachment(path: Path, file_type: int, kind: str, local_id: str, auction_id: int) -> dict[str, Any]:
    return {
        "localId": local_id,
        "fileId": 0,
        "auctionId": auction_id,
        "fileType": file_type,
        "kind": kind,
        "fileName": path.name,
        "fileData": b64(path),
        "contentType": content_type(path),
        "isDeleted": False,
        "signedAt": None,
        "lastModifiedUtc": iso(utc_now()),
    }


def contract_base_number(contract_number: str) -> str:
    return contract_number[5:] if contract_number.upper().startswith("PROV-COC-") else contract_number


def abacus_sync(
    *,
    document_kind: str,
    subject_id: int,
    label: str,
    document_name: str,
    source_file_name: str,
    storage: dict[str, Any],
    trigger: str,
    verify_receipt: bool = True,
) -> dict[str, Any]:
    return {
        "queueForAbacus": True,
        "target": "VendorDossier",
        "documentKind": document_kind,
        "subjectId": subject_id,
        "storage": storage,
        "label": label,
        "documentName": document_name,
        "sourceFileName": source_file_name,
        "contentType": content_type(Path(source_file_name)),
        "fileStoreEndpoint": "/api/file-store/v1/user",
        "documentsEndpoint": "SubjectDocuments",
        "trigger": trigger,
        "verifyReceipt": verify_receipt,
        "retry": {"maxAttempts": 3, "logBackofficeError": True},
    }


def upload_payload(
    path: Path,
    *,
    file_type: int,
    kind: str,
    local_id: str,
    auction_id: int,
    signed_at: str | None,
    sync: dict[str, Any] | None,
) -> dict[str, Any]:
    payload = attachment(path, file_type, kind, local_id, auction_id)
    payload["signedAt"] = signed_at
    if sync is not None:
        payload["abacusSync"] = sync
    return payload


def make_assets(
    output_dir: Path,
    scenario_key: str,
    scenario: Scenario,
    language: str,
    contract_number: str,
    consignor: dict[str, Any],
    representative: dict[str, Any] | None,
) -> dict[str, Path]:
    asset_dir = output_dir / "_assets" / scenario_key
    contact = consignor["consignorInfo"]
    company = consignor.get("tradingName") or ""
    product_base = contract_base_number(contract_number)
    assets: dict[str, Path] = {}

    assets["passport_1"] = asset_dir / "Passport-1.png"
    write_labeled_image(
        assets["passport_1"],
        "Passport Front",
        [
            f"Contract: {contract_number}",
            f"Name: {contact['firstName']} {contact['lastName']}",
            f"Company: {company or '-'}",
            f"Language: {language.upper()}",
        ],
        color=(26, 86, 132),
    )
    assets["passport_2"] = asset_dir / "Passport-2.png"
    write_labeled_image(
        assets["passport_2"],
        "Passport Back",
        [
            f"Contract: {contract_number}",
            "Mock MRZ / back side",
            "Valid until: " + (consignor.get("passportValidUntil") or ""),
            "Source: generated E2E asset",
        ],
        color=(26, 86, 132),
    )

    for index, tone in [(1, (104, 75, 37)), (2, (70, 105, 86))]:
        key = f"product_{index}"
        assets[key] = asset_dir / f"{product_base}-Product-{index}.png"
        write_labeled_image(
            assets[key],
            f"Product Image {index}",
            [
                f"Contract: {contract_number}",
                f"Dossier name: {product_base}-Product-{index}",
                f"Mock lot: Ancient coin #{index}",
                "Metal: silver / bronze mock",
            ],
            color=tone,
        )

    if scenario.consignor_type in {"LegalEntity", "SoleProprietor"}:
        assets["commercial_register"] = asset_dir / "CommercialRegister.png"
        write_labeled_image(
            assets["commercial_register"],
            "Commercial Register",
            [
                f"Contract: {contract_number}",
                f"Organisation: {company}",
                "Register excerpt: mock",
                "Purpose: E2E PDF attachment",
            ],
            color=(91, 64, 120),
        )

    if representative is not None:
        rep_contact = representative["consignorInfo"]
        rep_company = representative.get("tradingName") or ""
        assets["representative_1"] = asset_dir / "Representative-1.png"
        write_labeled_image(
            assets["representative_1"],
            "Representative Passport Front",
            [
                f"Contract: {contract_number}",
                f"Name: {rep_contact['firstName']} {rep_contact['lastName']}",
                f"Company: {rep_company or '-'}",
                "Source: generated E2E asset",
            ],
            color=(121, 61, 66),
        )
        assets["representative_2"] = asset_dir / "Representative-2.png"
        write_labeled_image(
            assets["representative_2"],
            "Representative Passport Back",
            [
                f"Contract: {contract_number}",
                "Mock representative document back side",
                "Purpose: representative image sync",
                "Source: generated E2E asset",
            ],
            color=(121, 61, 66),
        )
        if scenario.representative_type == "LegalEntity":
            assets["representative_register"] = asset_dir / "RepresentativeRegister.png"
            write_labeled_image(
                assets["representative_register"],
                "Legal Representative Register",
                [
                    f"Contract: {contract_number}",
                    f"Organisation: {rep_company}",
                    "Register excerpt: mock",
                    "Purpose: E2E PDF attachment",
                ],
                color=(91, 64, 120),
            )

    assets["customer_signature"] = asset_dir / "CustomerSignature.png"
    write_signature(assets["customer_signature"], f"{contact['firstName']} {contact['lastName']}")
    assets["annex_a_signature"] = asset_dir / "AnnexASignature.png"
    write_signature(assets["annex_a_signature"], f"{contact['firstName']} {contact['lastName']}")
    assets["annex_c_signature"] = asset_dir / "AnnexCSignature.png"
    write_signature(assets["annex_c_signature"], f"{contact['firstName']} {contact['lastName']}")
    assets["leu_signature"] = asset_dir / "LeuSignature.png"
    write_signature(assets["leu_signature"], "Yves Gunzenreiner")
    return assets


def render_payload(
    scenario: Scenario,
    language: str,
    contract_number: str,
    consignor: dict[str, Any],
    representative: dict[str, Any] | None,
    assets: dict[str, Path],
    auction: dict[str, Any],
) -> dict[str, Any]:
    signed_at = utc_now()
    auction_id = int(auction.get("auction_id") or auction.get("AuctionId") or auction.get("auctionId"))
    auction_name = auction.get("DisplayName") or auction.get("displayName") or f"Auction {auction_id}"
    attachments = [
        attachment(assets["passport_1"], 1, "NaturalPersonId", "passport-1", auction_id),
        attachment(assets["passport_2"], 1, "NaturalPersonId", "passport-2", auction_id),
        attachment(assets["product_1"], 3, "ProductImage", "product-1", auction_id),
        attachment(assets["product_2"], 3, "ProductImage", "product-2", auction_id),
    ]
    if "commercial_register" in assets:
        attachments.append(
            attachment(assets["commercial_register"], 2, "CommercialRegister", "commercial-register", auction_id)
        )
    if representative is not None:
        attachments.extend(
            [
                attachment(assets["representative_1"], 1, "RepresentativeId", "representative-1", auction_id),
                attachment(assets["representative_2"], 1, "RepresentativeId", "representative-2", auction_id),
            ]
        )
    if "representative_register" in assets:
        attachments.append(
            attachment(
                assets["representative_register"],
                2,
                "LegalRepresentativeRegister",
                "representative-register",
                auction_id,
            )
        )

    is_prov = scenario.provisional
    signature = {
        "customerSignaturePngBase64": "" if is_prov else b64(assets["customer_signature"]),
        "leuSignaturePngBase64": "" if is_prov else b64(assets["leu_signature"]),
        "annexASignaturePngBase64": "" if is_prov else b64(assets["annex_a_signature"]),
        "annexCSignaturePngBase64": "" if is_prov else b64(assets["annex_c_signature"]),
        "leuRepresentativeName": "" if is_prov else "Yves Gunzenreiner",
        "leuRepresentativeFunction": "CEO",
        "consignorSignerNameFunction": "",
    }

    return {
        "templateVersion": "Einlieferungsvertrag",
        "record": {
            "consignorId": consignor.get("systemReferenceConsignor"),
            "auctionId": auction_id,
            "auctionDisplayName": auction_name,
            "auctionDate": "2026-10-25T00:00:00Z",
            "signedAt": iso(signed_at),
            "lastModifiedUtc": iso(signed_at),
        },
        "consignor": consignor,
        "authorizedRepresentative": representative,
        "beneficialOwner": consignor if representative is not None else None,
        "consignorType": scenario.consignor_type,
        "consignorIsOwner": representative is None,
        "auctionName": auction_name,
        "auctionDate": "2026-10-25T00:00:00Z",
        "commissionPercent": "15%",
        "consignmentCountry": "Switzerland",
        "consignmentCountryIsoCountryCode": "CHE",
        "originCountry": "Switzerland",
        "leuRepresentativeName": "" if is_prov else "Yves Gunzenreiner",
        "leuRepresentativeFunction": "CEO",
        "isProvisional": is_prov,
        "watermarkText": "PROVISIONAL" if is_prov else "",
        "pageWatermarkText": "PROVISIONAL" if is_prov else "",
        "watermark": {"text": "PROVISIONAL" if is_prov else ""},
        "pageWatermark": {"text": "PROVISIONAL" if is_prov else ""},
        "signatureData": signature,
        "attachments": attachments,
        "saveToUploads": False,
    }


def build_uploads(
    contract_pdf: Path,
    assets: dict[str, Path],
    contract_number: str,
    auction_id: int,
    subject_id: int,
    signed_at: str | None,
    trigger: str,
) -> list[dict[str, Any]]:
    base_number = contract_base_number(contract_number)
    uploads: list[dict[str, Any]] = []
    uploads.append(
        upload_payload(
            contract_pdf,
            file_type=2,
            kind="GeneratedContract",
            local_id="contract-pdf",
            auction_id=auction_id,
            signed_at=signed_at,
            sync=abacus_sync(
                document_kind="ConsignmentContract",
                subject_id=subject_id,
                label=contract_number,
                document_name=f"{contract_number}.pdf",
                source_file_name=contract_pdf.name,
                storage=CONTRACT_STORAGE,
                trigger=trigger,
            ),
        )
    )
    for index in (1, 2):
        path = assets[f"passport_{index}"]
        label = f"Passport-{index}"
        uploads.append(
            upload_payload(
                path,
                file_type=1,
                kind="NaturalPersonId",
                local_id=f"passport-{index}",
                auction_id=auction_id,
                signed_at=signed_at,
                sync=abacus_sync(
                    document_kind="Passport",
                    subject_id=subject_id,
                    label=label,
                    document_name=f"{label}.png",
                    source_file_name=path.name,
                    storage=PASSPORT_STORAGE,
                    trigger=trigger,
                ),
            )
        )
    for index in (1, 2):
        path = assets[f"product_{index}"]
        label = f"{base_number}-Product-{index}"
        uploads.append(
            upload_payload(
                path,
                file_type=3,
                kind="ProductImage",
                local_id=f"product-{index}",
                auction_id=auction_id,
                signed_at=signed_at,
                sync=abacus_sync(
                    document_kind="CoinImage",
                    subject_id=subject_id,
                    label=label,
                    document_name=f"{label}.png",
                    source_file_name=path.name,
                    storage=PRODUCT_STORAGE,
                    trigger=trigger,
                ),
            )
        )
    if "representative_1" in assets:
        for index in (1, 2):
            path = assets[f"representative_{index}"]
            label = f"Representative-{index}"
            uploads.append(
                upload_payload(
                    path,
                    file_type=1,
                    kind="RepresentativeId",
                    local_id=f"representative-{index}",
                    auction_id=auction_id,
                    signed_at=signed_at,
                    sync=abacus_sync(
                        document_kind="RepresentativePassport",
                        subject_id=subject_id,
                        label=label,
                        document_name=f"{label}.png",
                        source_file_name=path.name,
                        storage=PASSPORT_STORAGE,
                        trigger=trigger,
                    ),
                )
            )
    if "commercial_register" in assets:
        commercial_register = assets["commercial_register"]
        uploads.append(
            upload_payload(
                commercial_register,
                file_type=2,
                kind="CommercialRegister",
                local_id="commercial_register",
                auction_id=auction_id,
                signed_at=signed_at,
                sync=abacus_sync(
                    document_kind="ConsignmentContract",
                    subject_id=subject_id,
                    label="Commercial-Register",
                    document_name=f"Commercial-Register{commercial_register.suffix.lower()}",
                    source_file_name=commercial_register.name,
                    storage=CONTRACT_STORAGE,
                    trigger=trigger,
                ),
            )
        )

    if "representative_register" in assets:
        uploads.append(
            upload_payload(
                assets["representative_register"],
                file_type=2,
                kind="LegalRepresentativeRegister",
                local_id="representative_register",
                auction_id=auction_id,
                signed_at=signed_at,
                sync=None,
            )
        )
    return uploads


def max_contract_suffix(groups: Any) -> int:
    max_seen = 0
    pattern = re.compile(r"\b(?:PROV-)?COC-" + re.escape(YEAR_CODE) + r"-(\d+)\b", re.IGNORECASE)
    text = json.dumps(groups)
    for match in pattern.finditer(text):
        max_seen = max(max_seen, int(match.group(1)))
    return max_seen


def verify_pdf(path: Path) -> dict[str, Any]:
    reader = PdfReader(str(path))
    return {
        "file": str(path),
        "bytes": path.stat().st_size,
        "pages": len(reader.pages),
    }


def verify_contracts(client: ApiClient, expected: set[str]) -> dict[str, Any]:
    groups = client.get_json("/api/consignors-app/contracts/get-all")
    found: dict[str, dict[str, Any]] = {}
    if isinstance(groups, dict):
        groups_iter = groups.get("contracts") or groups.get("value") or []
    else:
        groups_iter = groups or []
    for group in groups_iter:
        if not isinstance(group, dict):
            continue
        contract_id = (group.get("ContractId") or group.get("contractId") or group.get("AuctionDisplayName") or "").strip()
        if contract_id in expected:
            files = group.get("List") or group.get("list") or []
            found[contract_id] = {
                "owner": group.get("ConsignorId") or group.get("consignorId"),
                "files": [
                    item.get("FileName") or item.get("fileName")
                    for item in files
                    if isinstance(item, dict)
                ],
            }
    return {
        "expected": sorted(expected),
        "found": found,
        "missing": sorted(expected.difference(found.keys())),
    }


def scenario_runs() -> list[tuple[str, Scenario]]:
    runs: list[tuple[str, Scenario]] = []
    for language in ("de", "en"):
        runs.extend((language, scenario) for scenario in SCENARIOS)
    runs.append(("de", PROVISIONAL_SCENARIO))
    return runs


def scenario_by_slug(slug: str) -> Scenario:
    for scenario in SCENARIOS + [PROVISIONAL_SCENARIO]:
        if scenario.slug == slug:
            return scenario
    raise ValueError(f"Unknown scenario slug: {slug}")


def sequence_for(language: str, scenario: Scenario) -> int:
    if scenario.provisional:
        return 17
    offset = 0 if language.lower() == "de" else len(SCENARIOS)
    return offset + scenario.index


def reupload_manifest_records(
    args: argparse.Namespace,
    client: ApiClient,
    output_dir: Path,
    auction: dict[str, Any],
    run_id: str,
    manifest: dict[str, Any],
) -> dict[str, Any]:
    expected_contracts: set[str] = set()
    pdf_checks: list[dict[str, Any]] = []
    source_records: list[tuple[str, dict[str, Any]]] = []

    for manifest_path in args.reupload_manifest:
        path = Path(manifest_path)
        data = json.loads(path.read_text(encoding="utf-8"))
        source_run_id = str(data.get("runId") or path.stem.replace("manifest_", "")).strip()
        for record in data.get("records", []):
            if isinstance(record, dict):
                source_records.append((source_run_id, record))

    auction_id = int(auction.get("auction_id") or auction.get("AuctionId") or auction.get("auctionId"))
    print(f"Re-rendering and re-uploading {len(source_records)} existing manifest records...")

    for index, (source_run_id, record) in enumerate(source_records, start=1):
        language = str(record["language"])
        scenario = scenario_by_slug(str(record["scenario"]))
        sequence = sequence_for(language, scenario)
        contract_number = str(record["contractNumber"])
        expected_contracts.add(contract_number)
        scenario_key = f"{language.upper()}_{scenario.index:02d}_{scenario.slug}_{contract_number}"
        print(f"[{index}/{len(source_records)}] Re-uploading {scenario_key}...")

        representative = None
        if scenario.has_representative:
            representative = make_consignor(
                scenario,
                language,
                source_run_id,
                sequence,
                representative=True,
                representative_type=scenario.representative_type,
            )

        consignor = make_consignor(scenario, language, source_run_id, sequence)
        consignor["systemReferenceConsignor"] = int(record["consignorId"])
        consignor["systemReferenceCustomer"] = int(record["customerId"])
        consignor["abacusSubjectId"] = int(record["abacusSubjectId"])
        if representative is not None:
            add_representative_link(consignor, representative)

        assets = make_assets(
            output_dir,
            scenario_key,
            scenario,
            language,
            contract_number,
            consignor,
            representative,
        )
        payload = render_payload(
            scenario,
            language,
            contract_number,
            consignor,
            representative,
            assets,
            auction,
        )
        pdf_bytes = client.post_bytes("/api/consignors-app/contracts/render-pdf", payload)
        language_dir = output_dir / ("PROV" if scenario.provisional else language.upper())
        language_dir.mkdir(parents=True, exist_ok=True)
        pdf_path = language_dir / f"{scenario.index:02d}_{scenario.slug}_{contract_number}.pdf"
        pdf_path.write_bytes(pdf_bytes)
        pdf_check = verify_pdf(pdf_path)
        pdf_checks.append(pdf_check)

        upload_result = None
        signed_at = None if scenario.provisional else payload["record"]["signedAt"]
        trigger = "ContractGenerated" if scenario.provisional else "ContractSigned"
        if not args.no_upload:
            uploads = build_uploads(
                pdf_path,
                assets,
                contract_number,
                auction_id,
                int(consignor["abacusSubjectId"]),
                signed_at,
                trigger,
            )
            upload_result = client.post_json(
                f"/api/consignors-app/consignors/{consignor['systemReferenceConsignor']}/contracts",
                {
                    "consignorId": consignor["systemReferenceConsignor"],
                    "auctionId": auction_id,
                    "signedAt": signed_at,
                    "lastModifiedUtc": iso(utc_now()),
                    "replaceExistingFiles": False,
                    "abacusSync": {
                        "queueForAbacus": True,
                        "trigger": trigger,
                        "target": "VendorDossier",
                        "verifyReceipt": True,
                    },
                    "files": uploads,
                },
                expected=(200, 201),
            )

        manifest["records"].append(
            {
                "language": language,
                "scenario": scenario.slug,
                "contractNumber": contract_number,
                "provisional": scenario.provisional,
                "consignorId": consignor["systemReferenceConsignor"],
                "customerId": consignor["systemReferenceCustomer"],
                "abacusSubjectId": consignor["abacusSubjectId"],
                "pdfPath": str(pdf_path),
                "pdfPages": pdf_check["pages"],
                "uploadFileCount": len(upload_result.get("List") or upload_result.get("list") or [])
                if isinstance(upload_result, dict)
                else 0,
                "sourceRunId": source_run_id,
            }
        )

    manifest["pdfChecks"] = pdf_checks
    if not args.no_upload and not args.skip_verify:
        print("Verifying re-uploaded contracts from Abacus dossier metadata...")
        manifest["abacusVerification"] = verify_contracts(client, expected_contracts)

    manifest["finishedAtUtc"] = iso(utc_now())
    manifest["summary"] = {
        "newConsignorsCreated": 0,
        "contractsCreatedOrUpdated": len(source_records) if not args.no_upload else 0,
        "pdfsGenerated": len(pdf_checks),
        "provisionalContracts": sum(1 for _, item in source_records if item.get("provisional")),
    }
    manifest_path = output_dir / f"manifest_{run_id}.json"
    manifest_path.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print(f"Manifest written to {manifest_path}")
    print(json.dumps(manifest["summary"], indent=2))
    return manifest


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", default=os.environ.get("LEU_E2E_API_BASE", DEFAULT_BASE_URL))
    parser.add_argument("--output-dir", default=os.environ.get("LEU_E2E_OUTPUT_DIR", DEFAULT_OUTPUT_DIR))
    parser.add_argument("--token-env", default="LEU_E2E_BEARER")
    parser.add_argument("--timeout", type=int, default=300)
    parser.add_argument("--start-number", type=int, default=0)
    parser.add_argument("--from-sequence", type=int, default=1)
    parser.add_argument("--limit", type=int, default=0)
    parser.add_argument("--run-id", default="")
    parser.add_argument("--skip-verify", action="store_true")
    parser.add_argument("--no-upload", action="store_true")
    parser.add_argument("--reupload-manifest", action="append", default=[])
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    bearer = os.environ.get(args.token_env, "").strip()
    if not bearer:
        print(f"Set {args.token_env} to a valid bearer token.", file=sys.stderr)
        return 2

    client = ApiClient(args.base_url, bearer, args.timeout)
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    run_id = args.run_id.strip() or datetime.now().strftime("%m%d%H%M")
    manifest: dict[str, Any] = {
        "runId": run_id,
        "baseUrl": args.base_url,
        "createdAtUtc": iso(utc_now()),
        "outputDir": str(output_dir),
        "records": [],
    }

    print("Checking auctions...")
    auctions = client.get_json("/api/consignors-app/auctions/dropdown")
    if not isinstance(auctions, list) or not auctions:
        raise RuntimeError("No auctions returned by the API.")
    auction = auctions[0]
    auction_id = int(auction.get("auction_id") or auction.get("AuctionId") or auction.get("auctionId"))
    print(f"Using auction {auction.get('DisplayName') or auction_id} ({auction_id}).")

    if args.reupload_manifest:
        reupload_manifest_records(args, client, output_dir, auction, run_id, manifest)
        return 0

    if args.start_number > 0:
        next_number = args.start_number
    else:
        print("Analyzing existing COC contract numbers...")
        try:
            existing = client.get_json("/api/consignors-app/contracts/get-all")
            next_number = max_contract_suffix(existing) + 1
            if next_number <= 1:
                next_number = int(datetime.now().strftime("%m%d%H"))
        except Exception as exc:  # noqa: BLE001
            print(f"Could not analyze existing contracts; using timestamp fallback. Reason: {exc}")
            next_number = int(datetime.now().strftime("%m%d%H"))
    print(f"First generated contract number will be COC-{YEAR_CODE}-{next_number}.")

    expected_contracts: set[str] = set()
    pdf_checks: list[dict[str, Any]] = []
    all_runs = scenario_runs()
    from_sequence = max(1, min(args.from_sequence, len(all_runs)))
    runs = all_runs[from_sequence - 1 :]
    if args.limit > 0:
        runs = runs[: args.limit]
    for offset, (language, scenario) in enumerate(runs):
        sequence = from_sequence + offset
        suffix = next_number + offset
        contract_number = (
            f"PROV-COC-{YEAR_CODE}-{suffix}"
            if scenario.provisional
            else f"COC-{YEAR_CODE}-{suffix}"
        )
        expected_contracts.add(contract_number)
        scenario_key = f"{language.upper()}_{scenario.index:02d}_{scenario.slug}_{contract_number}"
        print(f"[{sequence}/{len(all_runs)}] Creating {scenario_key}...")

        representative = None
        if scenario.has_representative:
            representative = make_consignor(
                scenario,
                language,
                run_id,
                sequence,
                representative=True,
                representative_type=scenario.representative_type,
            )
        consignor = make_consignor(scenario, language, run_id, sequence)
        if representative is not None:
            add_representative_link(consignor, representative)

        response = client.post_json("/api/consignors-app/consignors/bulk-create", [consignor])
        if not isinstance(response, list) or not response:
            raise RuntimeError(f"Unexpected bulk-create response for {scenario_key}: {response}")
        result = response[0]
        if result.get("Error") or result.get("error"):
            raise RuntimeError(f"Consignor create failed for {scenario_key}: {result}")
        consignor["systemReferenceConsignor"] = result.get("SystemReferenceConsignor") or result.get("systemReferenceConsignor")
        consignor["systemReferenceCustomer"] = result.get("SystemReferenceCustomer") or result.get("systemReferenceCustomer")
        consignor["abacusSubjectId"] = result.get("AbacusSubjectId") or result.get("abacusSubjectId")
        if not consignor["systemReferenceConsignor"] or not consignor["abacusSubjectId"]:
            raise RuntimeError(f"Missing remote references for {scenario_key}: {result}")

        assets = make_assets(
            output_dir,
            scenario_key,
            scenario,
            language,
            contract_number,
            consignor,
            representative,
        )
        payload = render_payload(
            scenario,
            language,
            contract_number,
            consignor,
            representative,
            assets,
            auction,
        )
        pdf_bytes = client.post_bytes("/api/consignors-app/contracts/render-pdf", payload)
        language_dir = output_dir / ("PROV" if scenario.provisional else language.upper())
        language_dir.mkdir(parents=True, exist_ok=True)
        pdf_path = language_dir / f"{scenario.index:02d}_{scenario.slug}_{contract_number}.pdf"
        pdf_path.write_bytes(pdf_bytes)
        pdf_check = verify_pdf(pdf_path)
        pdf_checks.append(pdf_check)
        if pdf_check["pages"] <= 0:
            raise RuntimeError(f"Rendered PDF has no pages: {pdf_path}")

        upload_result = None
        signed_at = None if scenario.provisional else payload["record"]["signedAt"]
        trigger = "ContractGenerated" if scenario.provisional else "ContractSigned"
        if not args.no_upload:
            uploads = build_uploads(
                pdf_path,
                assets,
                contract_number,
                auction_id,
                int(consignor["abacusSubjectId"]),
                signed_at,
                trigger,
            )
            upload_result = client.post_json(
                f"/api/consignors-app/consignors/{consignor['systemReferenceConsignor']}/contracts",
                {
                    "consignorId": consignor["systemReferenceConsignor"],
                    "auctionId": auction_id,
                    "signedAt": signed_at,
                    "lastModifiedUtc": iso(utc_now()),
                    "replaceExistingFiles": False,
                    "abacusSync": {
                        "queueForAbacus": True,
                        "trigger": trigger,
                        "target": "VendorDossier",
                        "verifyReceipt": True,
                    },
                    "files": uploads,
                },
                expected=(200, 201),
            )

        record = {
            "language": language,
            "scenario": scenario.slug,
            "contractNumber": contract_number,
            "provisional": scenario.provisional,
            "consignorId": consignor["systemReferenceConsignor"],
            "customerId": consignor["systemReferenceCustomer"],
            "abacusSubjectId": consignor["abacusSubjectId"],
            "pdfPath": str(pdf_path),
            "pdfPages": pdf_check["pages"],
            "uploadFileCount": len(upload_result.get("List") or upload_result.get("list") or [])
            if isinstance(upload_result, dict)
            else 0,
        }
        manifest["records"].append(record)
        manifest_path = output_dir / f"manifest_{run_id}.json"
        manifest_path.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
        print(
            f"    Created consignor {record['consignorId']} / Abacus {record['abacusSubjectId']} "
            f"and PDF {pdf_check['pages']} pages."
        )

    manifest["pdfChecks"] = pdf_checks
    if not args.no_upload and not args.skip_verify:
        print("Verifying created contracts from Abacus dossier metadata...")
        verification = verify_contracts(client, expected_contracts)
        manifest["abacusVerification"] = verification
        if verification["missing"]:
            print("Missing contracts after Abacus verification: " + ", ".join(verification["missing"]))
        else:
            print("All generated contract numbers were found in Abacus dossier metadata.")

    manifest["finishedAtUtc"] = iso(utc_now())
    manifest["summary"] = {
        "newConsignorsCreated": len(runs),
        "contractsCreatedOrUpdated": len(runs) if not args.no_upload else 0,
        "pdfsGenerated": len(pdf_checks),
        "provisionalContracts": 1,
    }
    manifest_path = output_dir / f"manifest_{run_id}.json"
    manifest_path.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print(f"Manifest written to {manifest_path}")
    print(json.dumps(manifest["summary"], indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
