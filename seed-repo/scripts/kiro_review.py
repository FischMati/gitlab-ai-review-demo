#!/usr/bin/env python3
"""
Run Kiro CLI in headless mode against an MR diff and post the review back to
the merge request as:

  1. A single summary note (overview + all findings), and
  2. For findings that carry a concrete one-line fix, an inline discussion
     anchored to the diff line, containing a GitLab ```suggestion block so the
     author can apply the change with one click ("Apply suggestion").

The model is asked to reply with a JSON object so we can render Markdown
deterministically instead of trying to un-render Kiro's terminal output.

Required env (provided by GitLab CI):
  CI_API_V4_URL              GitLab API root, e.g. http://1.2.3.4/api/v4
  CI_PROJECT_ID              Numeric project id
  CI_MERGE_REQUEST_IID       MR iid (when running on a MR pipeline)
  GITLAB_API_TOKEN           Personal/Project access token with `api` scope
  KIRO_API_KEY               Kiro headless auth (set as masked CI variable)
  KIRO_MODEL                 (optional) model hint passed to Kiro
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from pathlib import Path

import requests

ANSI_RE = re.compile(r"\x1b\[[0-9;?]*[ -/]*[@-~]|\x1b\][^\x07]*(?:\x07|\x1b\\)")
JSON_OBJECT_RE = re.compile(r"\{.*\}", re.DOTALL)

CATEGORY_META = {
    "security": ("🔒", "Security"),
    "reliability": ("⚠️", "Reliability"),
    "cost": ("💰", "Cost"),
    "best-practice": ("💡", "Best-practice"),
}

PROMPT_TEMPLATE = """You are a senior cloud engineer reviewing a Terraform Merge Request. Review ONLY the lines added or modified in the unified diff below.

Reply with ONLY a single JSON object (no prose, no markdown fences, no preamble). The JSON must match this schema exactly:

{
  "summary": "two short sentences max describing the MR and overall risk",
  "findings": [
    {
      "category": "security" | "reliability" | "cost" | "best-practice",
      "file": "terraform/path/to/file.tf",
      "resource": "resource_type.name",
      "description": "one paragraph explaining what is wrong, why it matters, and the fix in plain English",
      "snippet": "optional HCL snippet (raw, no fences) — omit or empty string if not useful",
      "fix": {
        "match": "the EXACT, verbatim text of ONE added line from the diff that should be replaced (copy it character-for-character WITHOUT the leading + and without surrounding whitespace changes)",
        "replacement": "the full replacement line, including the same leading indentation as the matched line"
      }
    }
  ]
}

If there are no issues, reply with: {"summary": "LGTM — no blocking findings.", "findings": []}

Rules:
- Output MUST be valid JSON parseable by json.loads.
- Do NOT wrap the JSON in markdown fences like ```json.
- Escape inner double quotes in description/snippet/fix as \\".
- Use \\n inside snippet to separate lines.
- Categories must be lowercase exactly as listed.
- The "fix" field is OPTIONAL. Only include it when the fix is a SINGLE line that
  replaces ONE existing added line from the diff. "match" MUST be copied verbatim
  from a line that starts with + in the diff (excluding the + marker). If the fix
  spans multiple lines or adds new lines, OMIT "fix" entirely and explain in the
  description/snippet instead.

--- DIFF START ---
__DIFF__
--- DIFF END ---
"""


def run_kiro(diff_text: str) -> dict:
    prompt = PROMPT_TEMPLATE.replace("__DIFF__", diff_text)
    model = os.environ.get("KIRO_MODEL", "claude-opus-4.7")
    cmd = [
        "kiro-cli",
        "chat",
        "--no-interactive",
        "--model", model,
        "--wrap", "never",
        "--trust-tools=read,grep",
        prompt,
    ]
    env = os.environ.copy()
    env.setdefault("NO_COLOR", "1")
    env.setdefault("TERM", "dumb")
    proc = subprocess.run(
        cmd,
        capture_output=True,
        text=True,
        timeout=300,
        env=env,
    )
    if proc.returncode != 0:
        sys.stderr.write(f"kiro-cli exit {proc.returncode}\nSTDERR:\n{proc.stderr}\n")

    raw = proc.stdout or proc.stderr or ""
    cleaned = ANSI_RE.sub("", raw)
    match = JSON_OBJECT_RE.search(cleaned)
    if not match:
        raise RuntimeError(f"Could not find JSON object in Kiro output:\n{cleaned[:2000]}")
    return json.loads(match.group(0))


# --- Diff parsing -----------------------------------------------------------

DIFF_GIT_RE = re.compile(r"^diff --git a/(.+?) b/(.+)$")
HUNK_RE = re.compile(r"^@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@")


def index_added_lines(diff_text: str) -> dict[str, list[tuple[int, str]]]:
    """Return {new_path: [(new_line_number, line_content), ...]} for every line
    ADDED in the diff. Used to anchor suggestions to the right line."""
    added: dict[str, list[tuple[int, str]]] = {}
    current_file: str | None = None
    new_line = 0
    for line in diff_text.splitlines():
        gm = DIFF_GIT_RE.match(line)
        if gm:
            current_file = gm.group(2)
            added.setdefault(current_file, [])
            continue
        hm = HUNK_RE.match(line)
        if hm:
            new_line = int(hm.group(1))
            continue
        if current_file is None:
            continue
        if line.startswith("+++") or line.startswith("---"):
            continue
        if line.startswith("+"):
            added[current_file].append((new_line, line[1:]))
            new_line += 1
        elif line.startswith("-"):
            # Removed line: does not advance the new-file counter.
            continue
        elif line.startswith("\\"):
            # "\ No newline at end of file"
            continue
        else:
            # Context line advances the new-file counter.
            new_line += 1
    return added


def locate_fix_line(
    added_index: dict[str, list[tuple[int, str]]],
    file_path: str,
    match_text: str,
) -> int | None:
    """Find the new-file line number of the added line matching match_text.
    Returns None if there is no unique match (ambiguous or missing) so the
    caller can fall back to the summary-only note."""
    candidates = added_index.get(file_path) or []
    target = match_text.strip()
    hits = [ln for (ln, content) in candidates if content.strip() == target]
    if len(hits) == 1:
        return hits[0]
    return None


# --- Rendering --------------------------------------------------------------

def render_markdown(payload: dict, applied: set[int]) -> str:
    """Render the summary note. `applied` holds indices of findings that also
    got an inline suggestion, so we annotate them."""
    summary = payload.get("summary", "").strip()
    findings = payload.get("findings", [])

    parts: list[str] = ["## 🤖 Kiro AI Review · Terraform MR", ""]

    parts.append("### Summary")
    parts.append(summary or "_(no summary)_")
    parts.append("")

    if not findings:
        parts.append("✅ LGTM — no blocking findings.")
        return "\n".join(parts).strip() + "\n"

    parts.append("### Findings")
    parts.append("")

    for idx, f in enumerate(findings):
        cat = (f.get("category") or "").strip().lower()
        emoji, cat_word = CATEGORY_META.get(cat, ("•", cat.title() or "Finding"))
        file_ = f.get("file", "").strip()
        resource = f.get("resource", "").strip()
        description = (f.get("description") or "").strip()
        snippet = (f.get("snippet") or "").strip()

        suffix = " · 💬 _suggestion applied inline_" if idx in applied else ""
        parts.append(f"- {emoji} **{cat_word}** · `{file_}` · `{resource}`{suffix}")
        parts.append("")
        for line in description.splitlines():
            parts.append(f"  {line}" if line else "")
        if snippet:
            parts.append("")
            parts.append("  ```hcl")
            for line in snippet.splitlines():
                parts.append(f"  {line}")
            parts.append("  ```")
        parts.append("")

    return "\n".join(parts).strip() + "\n"


def build_suggestion_body(finding: dict, replacement: str) -> str:
    cat = (finding.get("category") or "").strip().lower()
    emoji, cat_word = CATEGORY_META.get(cat, ("•", cat.title() or "Finding"))
    description = (finding.get("description") or "").strip()
    # ```suggestion:-0+0 replaces only the commented line.
    return (
        f"{emoji} **{cat_word}** — {description}\n\n"
        f"```suggestion:-0+0\n{replacement}\n```"
    )


# --- GitLab API -------------------------------------------------------------

class GitLab:
    def __init__(self) -> None:
        self.api = os.environ["CI_API_V4_URL"].rstrip("/")
        self.project_id = os.environ["CI_PROJECT_ID"]
        self.mr_iid = os.environ.get("CI_MERGE_REQUEST_IID")
        self.token = os.environ.get("GITLAB_API_TOKEN")

    @property
    def enabled(self) -> bool:
        return bool(self.mr_iid and self.token)

    def _headers(self) -> dict:
        return {"PRIVATE-TOKEN": self.token}

    def get_diff_refs(self) -> dict | None:
        url = f"{self.api}/projects/{self.project_id}/merge_requests/{self.mr_iid}"
        r = requests.get(url, headers=self._headers(), timeout=30)
        if r.status_code >= 300:
            sys.stderr.write(f"Could not fetch MR diff_refs: {r.status_code} {r.text}\n")
            return None
        return r.json().get("diff_refs")

    def post_note(self, body: str) -> None:
        url = f"{self.api}/projects/{self.project_id}/merge_requests/{self.mr_iid}/notes"
        r = requests.post(url, headers=self._headers(), data={"body": body}, timeout=30)
        if r.status_code >= 300:
            sys.stderr.write(f"Failed to post note: {r.status_code} {r.text}\n")
            sys.exit(1)
        print(f"Posted summary note: {r.json().get('id')}")

    def post_suggestion(
        self, body: str, diff_refs: dict, new_path: str, new_line: int
    ) -> bool:
        url = f"{self.api}/projects/{self.project_id}/merge_requests/{self.mr_iid}/discussions"
        data = {
            "body": body,
            "position[position_type]": "text",
            "position[base_sha]": diff_refs["base_sha"],
            "position[start_sha]": diff_refs["start_sha"],
            "position[head_sha]": diff_refs["head_sha"],
            "position[new_path]": new_path,
            "position[old_path]": new_path,
            "position[new_line]": new_line,
        }
        r = requests.post(url, headers=self._headers(), data=data, timeout=30)
        if r.status_code >= 300:
            sys.stderr.write(
                f"Suggestion on {new_path}:{new_line} rejected "
                f"({r.status_code}); will remain in summary note only.\n{r.text}\n"
            )
            return False
        print(f"Posted inline suggestion on {new_path}:{new_line}")
        return True


def main() -> int:
    if len(sys.argv) < 3:
        print("usage: kiro_review.py <diff-file> <findings-out>", file=sys.stderr)
        return 2
    diff_path = Path(sys.argv[1])
    out_path = Path(sys.argv[2])
    diff_text = diff_path.read_text()
    if not diff_text.strip():
        print("Empty diff; nothing to review.")
        return 0

    payload = run_kiro(diff_text)
    findings = payload.get("findings", [])
    added_index = index_added_lines(diff_text)

    gl = GitLab()
    applied: set[int] = set()

    # Post inline suggestions first, so the summary can annotate which findings
    # got one. Suggestions are best-effort; any failure falls back to the note.
    if gl.enabled and findings:
        diff_refs = gl.get_diff_refs()
        if diff_refs:
            for idx, f in enumerate(findings):
                fix = f.get("fix") or {}
                match_text = (fix.get("match") or "").strip()
                replacement = fix.get("replacement")
                if not match_text or replacement is None:
                    continue
                new_path = (f.get("file") or "").strip()
                line_no = locate_fix_line(added_index, new_path, match_text)
                if line_no is None:
                    sys.stderr.write(
                        f"Finding {idx}: fix.match not uniquely found in diff for "
                        f"{new_path!r}; keeping it in summary only.\n"
                    )
                    continue
                body = build_suggestion_body(f, replacement)
                if gl.post_suggestion(body, diff_refs, new_path, line_no):
                    applied.add(idx)

    review = render_markdown(payload, applied)
    out_path.write_text(review)

    if gl.enabled:
        gl.post_note(review)
    elif not gl.mr_iid:
        print("Not a MR pipeline; printing review to stdout instead:\n")
        print(review)
    else:
        sys.stderr.write("GITLAB_API_TOKEN not set; cannot post note. Review:\n")
        print(review)

    return 0


if __name__ == "__main__":
    sys.exit(main())
