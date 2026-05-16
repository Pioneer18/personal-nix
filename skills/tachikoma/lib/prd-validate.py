#!/usr/bin/env python3
"""
Validate a Tachikoma PRD JSON file against lib/prd-schema.json.

Hand-written validator (python3 stdlib only; no jsonschema lib).
Supports the subset of JSON Schema draft 2020-12 used by prd-schema.json:
type, required, additionalProperties, properties, items, enum, const,
pattern, minLength, minItems, minimum, maximum, format=uuid.

Plus one hard-coded business rule: objective_id requires operation_slug.

Usage:
    prd-validate.py <prd-json-file>
        Exit 0 on valid.
        Exit 1 on invalid; errors printed to stderr, one per line.
        Exit 2 on file read or JSON parse error.
"""
import json
import re
import sys
import uuid
from pathlib import Path

SCHEMA_PATH = Path(__file__).parent / "prd-schema.json"


def load_schema():
    with open(SCHEMA_PATH) as f:
        return json.load(f)


def _type_ok(value, expected):
    if expected == "string":
        return isinstance(value, str)
    if expected == "integer":
        return isinstance(value, int) and not isinstance(value, bool)
    if expected == "array":
        return isinstance(value, list)
    if expected == "object":
        return isinstance(value, dict)
    if expected == "boolean":
        return isinstance(value, bool)
    if expected == "number":
        return isinstance(value, (int, float)) and not isinstance(value, bool)
    return False


def _check_format(value, fmt):
    if fmt == "uuid":
        try:
            uuid.UUID(str(value))
            return True
        except (ValueError, AttributeError):
            return False
    return True


def validate(data, schema, path=""):
    errors = []

    if "const" in schema:
        if data != schema["const"]:
            errors.append(f"{path or '<root>'}: must equal {schema['const']!r}, got {data!r}")
            return errors

    if "enum" in schema:
        if data not in schema["enum"]:
            errors.append(f"{path or '<root>'}: must be one of {schema['enum']!r}, got {data!r}")
            return errors

    if "type" in schema:
        if not _type_ok(data, schema["type"]):
            errors.append(f"{path or '<root>'}: must be {schema['type']}, got {type(data).__name__}")
            return errors

    if isinstance(data, str):
        if "minLength" in schema and len(data) < schema["minLength"]:
            errors.append(f"{path or '<root>'}: shorter than minLength={schema['minLength']}")
        if "pattern" in schema and not re.search(schema["pattern"], data):
            errors.append(f"{path or '<root>'}: does not match pattern {schema['pattern']!r}")
        if "format" in schema and not _check_format(data, schema["format"]):
            errors.append(f"{path or '<root>'}: invalid format {schema['format']!r}")

    if isinstance(data, int) and not isinstance(data, bool):
        if "minimum" in schema and data < schema["minimum"]:
            errors.append(f"{path or '<root>'}: less than minimum={schema['minimum']}")
        if "maximum" in schema and data > schema["maximum"]:
            errors.append(f"{path or '<root>'}: greater than maximum={schema['maximum']}")

    if isinstance(data, list):
        if "minItems" in schema and len(data) < schema["minItems"]:
            errors.append(f"{path or '<root>'}: fewer than minItems={schema['minItems']}")
        if "items" in schema:
            for i, item in enumerate(data):
                errors.extend(validate(item, schema["items"], f"{path}[{i}]"))

    if isinstance(data, dict):
        if "required" in schema:
            for req in schema["required"]:
                if req not in data:
                    errors.append(f"{path or '<root>'}: missing required field '{req}'")
        if schema.get("additionalProperties") is False and "properties" in schema:
            allowed = set(schema["properties"].keys())
            for key in data:
                if key not in allowed:
                    errors.append(f"{path or '<root>'}: unknown field '{key}' (additionalProperties=false)")
        if "properties" in schema:
            for prop, prop_schema in schema["properties"].items():
                if prop in data:
                    child_path = f"{path}.{prop}" if path else prop
                    errors.extend(validate(data[prop], prop_schema, child_path))

    return errors


def business_rules(data):
    errors = []
    if "objective_id" in data and "operation_slug" not in data:
        errors.append("<root>: 'objective_id' requires 'operation_slug'")
    return errors


def main():
    if len(sys.argv) != 2:
        sys.stderr.write("usage: prd-validate.py <prd-json-file>\n")
        return 2
    prd_file = sys.argv[1]
    try:
        with open(prd_file) as f:
            data = json.load(f)
    except OSError as e:
        sys.stderr.write(f"prd-validate: cannot read {prd_file}: {e}\n")
        return 2
    except json.JSONDecodeError as e:
        sys.stderr.write(f"prd-validate: invalid JSON in {prd_file}: {e}\n")
        return 2

    schema = load_schema()
    errors = validate(data, schema)
    errors.extend(business_rules(data))
    if errors:
        for err in errors:
            sys.stderr.write(f"prd-validate: {err}\n")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
