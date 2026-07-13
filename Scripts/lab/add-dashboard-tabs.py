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
        "gap:.15rem;padding:0 .45rem;border-bottom:1px solid light-dark(#d0d7de,#30363d);box-sizing:border-box}"
        ".dashboard-tabs a{position:relative;margin-bottom:-1px;padding:.58rem .85rem;border:1px solid transparent;"
        "border-radius:.45rem .45rem 0 0;color:light-dark(#57606a,#8b949e);font:600 13px -apple-system,system-ui,sans-serif;"
        "text-decoration:none}.dashboard-tabs a:hover{color:light-dark(#24292f,#f0f6fc);background:light-dark(#f6f8fa,#161b22)}"
        ".dashboard-tabs a[aria-current=page]{color:light-dark(#24292f,#f0f6fc);background:light-dark(#fff,#181818);"
        "border-color:light-dark(#d0d7de,#30363d);border-bottom-color:light-dark(#fff,#181818)}"
        ".dashboard-tabs a[aria-current=page]::before{content:'';position:absolute;top:-1px;left:.42rem;right:.42rem;"
        "height:2px;border-radius:2px 2px 0 0;background:#2da44e}"
        "body{padding-top:.65rem!important}iframe{height:calc(100vh - 4.5rem)!important}"
    )
    document = document.replace("</style>", styles + "</style>", 1)
    document = document.replace("<body>", "<body>" + tabs, 1)
    args.page.write_text(document)


if __name__ == "__main__":
    main()
