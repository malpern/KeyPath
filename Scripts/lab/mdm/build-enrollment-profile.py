#!/usr/bin/env python3

import argparse
import plistlib
import uuid
from pathlib import Path


NAMESPACE = uuid.UUID("3f53bb0e-671a-48a6-b7ee-91480af3110e")


def payload_uuid(name: str) -> str:
    return str(uuid.uuid5(NAMESPACE, name)).upper()


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Build the private KeyPath lab MDM enrollment profile."
    )
    parser.add_argument("--scep-url", required=True)
    parser.add_argument("--mdm-url", required=True)
    parser.add_argument("--challenge-file", required=True, type=Path)
    parser.add_argument("--topic", required=True)
    parser.add_argument("--tls-root-der", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()

    challenge = args.challenge_file.read_text().strip()
    if not challenge:
        raise SystemExit("SCEP challenge is empty")
    if not args.topic.startswith("com.apple.mgmt."):
        raise SystemExit("APNs topic must start with com.apple.mgmt.")

    root_uuid = payload_uuid("https-root")
    scep_uuid = payload_uuid("scep")
    mdm_uuid = payload_uuid("mdm")

    profile = {
        "PayloadContent": [
            {
                "PayloadContent": args.tls_root_der.read_bytes(),
                "PayloadDisplayName": "KeyPath Lab MDM HTTPS Root",
                "PayloadIdentifier": "com.keypath.lab.mdm.https-root",
                "PayloadType": "com.apple.security.root",
                "PayloadUUID": root_uuid,
                "PayloadVersion": 1,
            },
            {
                "PayloadContent": {
                    "Challenge": challenge,
                    "Key Type": "RSA",
                    "Key Usage": 5,
                    "Keysize": 2048,
                    "URL": args.scep_url,
                },
                "PayloadIdentifier": "com.keypath.lab.mdm.scep",
                "PayloadType": "com.apple.security.scep",
                "PayloadUUID": scep_uuid,
                "PayloadVersion": 1,
            },
            {
                "AccessRights": 8191,
                "CheckInURL": args.mdm_url,
                "CheckInURLPinningCertificateUUIDs": [root_uuid],
                "CheckOutWhenRemoved": True,
                "IdentityCertificateUUID": scep_uuid,
                "PayloadIdentifier": "com.keypath.lab.mdm.enrollment",
                "PayloadType": "com.apple.mdm",
                "PayloadUUID": mdm_uuid,
                "PayloadVersion": 1,
                "ServerCapabilities": [
                    "com.apple.mdm.per-user-connections",
                    "com.apple.mdm.bootstraptoken",
                    "com.apple.mdm.token",
                ],
                "ServerURL": args.mdm_url,
                "ServerURLPinningCertificateUUIDs": [root_uuid],
                "SignMessage": True,
                "Topic": args.topic,
                "UseDevelopmentAPNS": False,
            },
        ],
        "PayloadDescription": "Enrolls a disposable KeyPath VM in the private test lab.",
        "PayloadDisplayName": "KeyPath Lab MDM Enrollment",
        "PayloadIdentifier": "com.keypath.lab.mdm",
        "PayloadOrganization": "KeyPath",
        "PayloadRemovalDisallowed": False,
        "PayloadScope": "System",
        "PayloadType": "Configuration",
        "PayloadUUID": payload_uuid("profile"),
        "PayloadVersion": 1,
    }

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("wb") as handle:
        plistlib.dump(profile, handle, fmt=plistlib.FMT_XML, sort_keys=True)
    args.output.chmod(0o600)
    print(args.output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
