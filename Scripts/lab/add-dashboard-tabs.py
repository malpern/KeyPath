#!/usr/bin/env python3
import argparse
import pathlib


def main() -> None:
    parser = argparse.ArgumentParser(description="Add shared navigation to a rendered KeyPath dashboard")
    parser.add_argument("page", type=pathlib.Path)
    parser.add_argument("--active", choices=("automation", "issues"), required=True)
    args = parser.parse_args()
    document = args.page.read_text()
    tabs = (
        '<nav class="dashboard-tabs" aria-label="KeyPath dashboards">'
        '<a href="keypath-test-automation-progress.html" '
        f'aria-current="{"page" if args.active == "automation" else "false"}">Automation lab</a>'
        '<a href="keypath-github-issues-dashboard.html" '
        f'aria-current="{"page" if args.active == "issues" else "false"}">GitHub issues</a>'
        "</nav>"
    )
    styles = (
        ".dashboard-tabs{display:flex;width:min(1180px,calc(100% - 2rem));margin:0 auto .65rem;"
        "gap:.35rem;padding:.3rem;background:#0d1117;border:1px solid #30363d;border-radius:.65rem;box-sizing:border-box}"
        ".dashboard-tabs a{padding:.5rem .8rem;border-radius:.42rem;color:#8b949e;font:600 13px -apple-system,system-ui,sans-serif;"
        "text-decoration:none}.dashboard-tabs a:hover{color:#f0f6fc;background:#161b22}.dashboard-tabs a[aria-current=page]{"
        "color:#f0f6fc;background:#238636;box-shadow:inset 0 0 0 1px #2ea043}"
        "body{padding-top:.65rem!important}iframe{height:calc(100vh - 4.5rem)!important}"
    )
    document = document.replace("</style>", styles + "</style>", 1)
    document = document.replace("<body>", "<body>" + tabs, 1)
    args.page.write_text(document)


if __name__ == "__main__":
    main()
