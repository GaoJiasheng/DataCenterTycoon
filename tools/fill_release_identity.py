#!/usr/bin/env python3
"""Render owner-controlled release identity into App Store delivery files."""

import json
import html
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
IDENTITY_PATH = ROOT / "data/release_identity.json"
TARGETS = {
    "docs/public/privacy.html.tmpl": "docs/public/privacy.html",
    "docs/public/support.html.tmpl": "docs/public/support.html",
    "docs/store/metadata/en.md.tmpl": "docs/store/metadata/en.md",
    "docs/store/metadata/zh_CN.md.tmpl": "docs/store/metadata/zh_CN.md",
}
REQUIRED_FIELDS = (
    "product_name",
    "privacy_email",
    "support_email",
    "privacy_url",
    "support_url",
    "effective_date",
    "ad_providers",
)


def load_identity(path=IDENTITY_PATH):
    identity = json.loads(path.read_text(encoding="utf-8"))
    missing = [field for field in REQUIRED_FIELDS if field not in identity]
    if missing:
        raise ValueError(f"release identity is missing: {', '.join(missing)}")
    for field in REQUIRED_FIELDS[:-1]:
        if not isinstance(identity[field], str) or not identity[field].strip():
            raise ValueError(f"release identity field {field} must be a non-empty string")
    providers = identity["ad_providers"]
    if not isinstance(providers, list) or not providers or any(not isinstance(item, str) or not item.strip() for item in providers):
        raise ValueError("release identity field ad_providers must be a non-empty string array")
    return identity


def render_context(identity, html_mode=False):
    encode = html.escape if html_mode else lambda value: value
    context = {key: encode(value) if isinstance(value, str) else value for key, value in identity.items()}
    context["ad_provider_names"] = ", ".join(identity["ad_providers"])
    context["ad_provider_html"] = "\n".join(f"<li>{html.escape(provider)}</li>" for provider in identity["ad_providers"])
    if html_mode:
        context["ad_provider_names"] = html.escape(context["ad_provider_names"])
    return context


def render_template(template_text, identity, html_mode=False):
    rendered = template_text
    for key, value in render_context(identity, html_mode).items():
        if isinstance(value, str):
            rendered = rendered.replace("{{" + key + "}}", value)
    if "{{" in rendered or "}}" in rendered:
        raise ValueError("template contains an unknown or unclosed release identity token")
    return rendered


def rendered_outputs(identity=None):
    identity = identity or load_identity()
    outputs = {}
    for template_name, output_name in TARGETS.items():
        template = ROOT / template_name
        if not template.is_file():
            raise ValueError(f"missing release template {template_name}")
        outputs[ROOT / output_name] = render_template(template.read_text(encoding="utf-8"), identity, template.suffixes[-2:] == [".html", ".tmpl"])
    return outputs


def main():
    try:
        outputs = rendered_outputs()
        for path, content in outputs.items():
            path.write_text(content, encoding="utf-8")
            print(f"Rendered {path.relative_to(ROOT)}")
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"Release identity render failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
