#!/usr/bin/env python3
"""Render owner-controlled release identity into App Store delivery files."""

import json
import html
import sys
from html.parser import HTMLParser
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
IDENTITY_PATH = ROOT / "data/release_identity.json"
TARGETS = {
    "docs/public/privacy.html.tmpl": "docs/public/privacy.html",
    "docs/public/support.html.tmpl": "docs/public/support.html",
    "docs/public/terms.html.tmpl": "docs/public/terms.html",
    "docs/store/metadata/en.md.tmpl": "docs/store/metadata/en.md",
    "docs/store/metadata/zh_CN.md.tmpl": "docs/store/metadata/zh_CN.md",
}
RUNTIME_LEGAL_TARGETS = {
    "docs/public/privacy.html.tmpl": "assets/legal/privacy.txt",
    "docs/public/terms.html.tmpl": "assets/legal/terms.txt",
    "docs/public/support.html.tmpl": "assets/legal/support.txt",
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


class LegalTextExtractor(HTMLParser):
    """Extract the visible body while preserving readable paragraph breaks."""

    BREAK_TAGS = {"h1", "h2", "h3", "p", "li", "hr", "br"}

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.in_body = False
        self.parts = []

    def handle_starttag(self, tag, attrs):
        if tag == "body":
            self.in_body = True
        elif self.in_body and tag in self.BREAK_TAGS:
            self.parts.append("\n")
            if tag == "li":
                self.parts.append("• ")

    def handle_endtag(self, tag):
        if tag == "body":
            self.in_body = False
        elif self.in_body and tag in self.BREAK_TAGS:
            self.parts.append("\n")

    def handle_data(self, data):
        if self.in_body:
            self.parts.append(data)

    def text(self):
        lines = []
        for raw_line in "".join(self.parts).splitlines():
            line = " ".join(raw_line.split())
            if line:
                lines.append(line)
            elif lines and lines[-1] != "":
                lines.append("")
        return "\n".join(lines).strip() + "\n"


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


def runtime_identity(identity):
    """Use honest in-app labels until the owner supplies release identity."""
    result = dict(identity)
    result["product_name"] = "This game" if "REPLACE_WITH_" in identity["product_name"] else identity["product_name"]
    for field in ("privacy_email", "support_email", "privacy_url", "support_url", "effective_date"):
        if "REPLACE_WITH_" in identity[field]:
            result[field] = "Coming soon / 即将公布"
    if any("REPLACE_WITH_" in provider for provider in identity["ad_providers"]):
        result["ad_providers"] = ["Coming soon / 即将公布"]
    return result


def html_to_legal_text(rendered_html):
    extractor = LegalTextExtractor()
    extractor.feed(rendered_html)
    return extractor.text()


def rendered_outputs(identity=None):
    identity = identity or load_identity()
    outputs = {}
    for template_name, output_name in TARGETS.items():
        template = ROOT / template_name
        if not template.is_file():
            raise ValueError(f"missing release template {template_name}")
        outputs[ROOT / output_name] = render_template(template.read_text(encoding="utf-8"), identity, template.suffixes[-2:] == [".html", ".tmpl"])
    safe_identity = runtime_identity(identity)
    for template_name, output_name in RUNTIME_LEGAL_TARGETS.items():
        template = ROOT / template_name
        if not template.is_file():
            raise ValueError(f"missing release template {template_name}")
        rendered_html = render_template(template.read_text(encoding="utf-8"), safe_identity, True)
        outputs[ROOT / output_name] = html_to_legal_text(rendered_html)
    return outputs


def main():
    try:
        outputs = rendered_outputs()
        for path, content in outputs.items():
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content, encoding="utf-8")
            print(f"Rendered {path.relative_to(ROOT)}")
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"Release identity render failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
