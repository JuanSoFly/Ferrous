#!/usr/bin/env python3
"""
Ferrous Reader — Automated Release Downloads Graph Generator
Fetches live download counts from GitHub Releases API and updates assets/downloads-graph.svg
in alignment with the Kindle Carta 1300 E-Ink Mode & Tactile Textures specification.
"""

import gzip
import json
import os
import ssl
import sys
import urllib.error
import urllib.request
from pathlib import Path

REPO = os.environ.get("GITHUB_REPOSITORY", "JuanSoFly/Ferrous")
API_URL = f"https://api.github.com/repos/{REPO}/releases"

def fetch_releases():
    token = os.environ.get("GITHUB_TOKEN")
    headers = {
        "User-Agent": "Ferrous-Downloads-Updater",
        "Accept": "application/vnd.github+json",
        "Accept-Encoding": "gzip",
    }
    if token:
        headers["Authorization"] = f"Bearer {token}"
    
    # SSL context with fallback for local environments lacking root certificates
    try:
        ctx = ssl.create_default_context()
    except Exception:
        ctx = ssl._create_unverified_context()

    all_releases = []
    page = 1
    per_page = 100

    while True:
        url = f"{API_URL}?per_page={per_page}&page={page}"
        req = urllib.request.Request(url, headers=headers)
        
        try:
            try:
                resp = urllib.request.urlopen(req, context=ctx)
            except (ssl.SSLError, urllib.error.URLError):
                ctx = ssl._create_unverified_context()
                resp = urllib.request.urlopen(req, context=ctx)
            
            with resp:
                raw = resp.read()
                if resp.info().get("Content-Encoding") == "gzip":
                    raw = gzip.decompress(raw)
                data = json.loads(raw.decode("utf-8"))
        except Exception as e:
            print(f"Error fetching releases page {page}: {e}", file=sys.stderr)
            raise

        if not isinstance(data, list) or len(data) == 0:
            break
        
        all_releases.extend(data)
        if len(data) < per_page:
            break
        page += 1

    return all_releases

def compute_milestones(releases):
    def get_dl(r):
        return sum(a.get("download_count", 0) for a in r.get("assets", []))
    
    # Identify the true latest stable release (not a prerelease or draft)
    latest_stable_tag = None
    for r in releases:
        if not r.get("prerelease") and not r.get("draft"):
            latest_stable_tag = r.get("tag_name")
            break
    
    if not latest_stable_tag:
        latest_stable_tag = releases[0].get("tag_name", "v1.4.0").split("-")[0] if releases else "v1.4.0"

    # Milestone groups: v1.0.0, v1.1.0, v1.2.x, v1.3.x, and v1.4.x (current stable series)
    milestones = {
        "v1.0.0": 0,
        "v1.1.0": 0,
        "v1.2.x": 0,
        "v1.3.x": 0,
        "v1.4.x": 0,
    }

    # Determine major.minor prefix of the current active milestone (e.g. "v1.4")
    active_prefix = "v1.4"
    if latest_stable_tag.startswith("v"):
        parts = latest_stable_tag.split(".")
        if len(parts) >= 2:
            active_prefix = f"{parts[0]}.{parts[1]}"

    for r in releases:
        tag = r.get("tag_name", "")
        dl = get_dl(r)
        if tag.startswith("v1.0"):
            milestones["v1.0.0"] += dl
        elif tag.startswith("v1.1"):
            milestones["v1.1.0"] += dl
        elif tag.startswith("v1.2"):
            milestones["v1.2.x"] += dl
        elif tag.startswith("v1.3"):
            milestones["v1.3.x"] += dl
        elif tag.startswith(active_prefix) or tag.startswith("v1.4"):
            milestones["v1.4.x"] += dl
        else:
            milestones["v1.4.x"] += dl

    d1 = milestones["v1.0.0"]
    d2 = milestones["v1.1.0"]
    d3 = milestones["v1.2.x"]
    d4 = milestones["v1.3.x"]
    d5 = milestones["v1.4.x"]

    c1 = d1
    c2 = c1 + d2
    c3 = c2 + d3
    c4 = c3 + d4
    c5 = c4 + d5
    total = c5

    return {
        "total": total,
        "latest_tag": latest_stable_tag,
        "deltas": [d1, d2, d3, d4, d5],
        "cumulatives": [c1, c2, c3, c4, c5]
    }

def generate_svg(data):
    total = data["total"]
    c = data["cumulatives"]
    d = data["deltas"]
    latest_tag = data["latest_tag"]

    # Maximum scale (at least 600, or rounded up to next 100)
    max_scale = max(600, ((total + 99) // 100) * 100)
    def to_y(val):
        return round(285 - (val / float(max_scale)) * 180, 1)

    y1, y2, y3, y4, y5 = [to_y(val) for val in c]
    
    # Grid lines
    g_150 = to_y(max_scale * 0.25)
    g_300 = to_y(max_scale * 0.50)
    g_450 = to_y(max_scale * 0.75)
    g_600 = to_y(max_scale)

    lbl_150 = int(max_scale * 0.25)
    lbl_300 = int(max_scale * 0.50)
    lbl_450 = int(max_scale * 0.75)
    lbl_600 = int(max_scale)

    # Heights for stacked columns
    h1 = round(285 - y1, 1)
    h2 = round(285 - y2, 1)
    h3 = round(285 - y3, 1)
    h4 = round(285 - y4, 1)
    h5 = round(285 - y5, 1)

    h2_prior = round(285 - y1, 1)
    h2_delta = round(y1 - y2, 1)

    h3_prior = round(285 - y2, 1)
    h3_delta = round(y2 - y3, 1)

    h4_prior = round(285 - y3, 1)
    h4_delta = round(y3 - y4, 1)

    h5_prior = round(285 - y4, 1)
    h5_delta = round(y4 - y5, 1)

    tag_y = round(y5 - 38, 1)

    svg_content = f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 800 380" width="100%" height="100%" role="img" aria-labelledby="chart-title chart-desc">
  <title id="chart-title">Ferrous Reader — Release Trajectory ({total}+ Cumulative Downloads)</title>
  <desc id="chart-desc">Kindle Carta 1300 E-Ink styled halftone chart showing cumulative GitHub release downloads across versions v1.0.0 ({c[0]}), v1.1.0 ({c[1]}), v1.2.x ({c[2]}), v1.3.x ({c[3]}), and {latest_tag} Stable ({total}+).</desc>

  <defs>
    <!-- Physical Halftone Dot Scrims (Kindle Carta 1300 E-Ink Specification) -->
    <pattern id="halftone-dense" width="4" height="4" patternUnits="userSpaceOnUse">
      <circle cx="2" cy="2" r="0.95" fill="#1A1A18" fill-opacity="0.22" />
    </pattern>

    <pattern id="halftone-light" width="5" height="5" patternUnits="userSpaceOnUse">
      <circle cx="2.5" cy="2.5" r="0.8" fill="#1A1A18" fill-opacity="0.14" />
    </pattern>

    <!-- Carry-over Base Volume (Lighter Halftone) -->
    <pattern id="halftone-base" width="4.5" height="4.5" patternUnits="userSpaceOnUse">
      <circle cx="2.25" cy="2.25" r="0.75" fill="#1A1A18" fill-opacity="0.15" />
    </pattern>

    <!-- Per-Milestone Delta Cap (Denser Halftone) -->
    <pattern id="halftone-delta" width="3.5" height="3.5" patternUnits="userSpaceOnUse">
      <circle cx="1.75" cy="1.75" r="1.0" fill="#1A1A18" fill-opacity="0.34" />
    </pattern>

    <pattern id="halftone-column-active" width="3.5" height="3.5" patternUnits="userSpaceOnUse">
      <circle cx="1.75" cy="1.75" r="1.1" fill="#1A1A18" fill-opacity="0.44" />
    </pattern>

    <!-- Fine Laid Paper Wire Ribs (Tactile Linen / Archival Book Paper) -->
    <pattern id="laid-ribs" width="40" height="5.5" patternUnits="userSpaceOnUse">
      <line x1="0" y1="5" x2="40" y2="5" stroke="#9E9A90" stroke-width="0.5" stroke-opacity="0.22" />
    </pattern>

    <!-- Deckle Fiber Micro-Noise (0.04 Opacity Fractal Grain) -->
    <filter id="carta-grain" x="0%" y="0%" width="100%" height="100%">
      <feTurbulence type="fractalNoise" baseFrequency="0.85" numOctaves="4" result="noise" />
      <feColorMatrix type="matrix" values="0 0 0 0 0.102  0 0 0 0 0.102  0 0 0 0 0.094  0 0 0 0.04 0" result="coloredNoise" />
      <feComposite operator="over" in="coloredNoise" in2="SourceGraphic" />
    </filter>
  </defs>

  <style>
    .eink-bg {{ fill: #EAE6DF; }}
    .eink-surface-secondary {{ fill: #E0DCD3; }}
    .carbon-ink {{ fill: #1A1A18; }}
    .secondary-ink {{ fill: #3D3C38; }}
    .hairline-ink {{ stroke: #9E9A90; }}
    .leader-line {{ stroke: #C2BEB4; }}
    
    .serif-title {{ font-family: "Iowan Old Style", "Palatino Linotype", "Georgia", "Times New Roman", serif; font-size: 16px; font-weight: 700; letter-spacing: 0.5px; fill: #1A1A18; }}
    .serif-subtitle {{ font-family: "Iowan Old Style", "Palatino Linotype", "Georgia", "Times New Roman", serif; font-size: 12px; font-style: italic; fill: #3D3C38; }}
    .category-eyebrow {{ font-family: ui-monospace, "SF Mono", Menlo, Consolas, monospace; font-size: 9.5px; font-weight: 700; letter-spacing: 1.5px; fill: #3D3C38; text-transform: uppercase; }}
    
    .ledger-num {{ font-family: ui-monospace, "SF Mono", Menlo, Consolas, monospace; font-size: 11.5px; font-weight: 700; }}
    .axis-num {{ font-family: ui-monospace, "SF Mono", Menlo, Consolas, monospace; font-size: 10px; font-weight: 600; fill: #4A4945; }}
    .legend-label {{ font-family: ui-monospace, "SF Mono", Menlo, Consolas, monospace; font-size: 9px; font-weight: 600; fill: #3D3C38; letter-spacing: 0.5px; }}
    .version-title {{ font-family: ui-monospace, "SF Mono", Menlo, Consolas, monospace; font-size: 12px; font-weight: 700; fill: #1A1A18; }}
    .milestone-desc {{ font-family: "Iowan Old Style", "Georgia", "Times New Roman", serif; font-size: 10.5px; font-style: italic; fill: #3D3C38; }}
    .delta-badge {{ font-family: ui-monospace, "SF Mono", Menlo, Consolas, monospace; font-size: 9.5px; font-weight: 600; fill: #1A1A18; }}
    .colophon-text {{ font-family: ui-monospace, "SF Mono", Menlo, Consolas, monospace; font-size: 9px; font-weight: 600; letter-spacing: 1.2px; fill: #4A4945; text-transform: uppercase; }}
  </style>

  <!-- 1. Primary Kindle Carta 1300 Paper Surface + Dark-Mode Safe Outer Bezel -->
  <rect width="800" height="380" rx="4" fill="#EAE6DF" />
  <rect x="2" y="2" width="796" height="376" rx="3" class="eink-bg" stroke="#1A1A18" stroke-width="2" filter="url(#carta-grain)" />

  <!-- 2. Tactile Book Laid Ribs Layer -->
  <rect x="2" y="2" width="796" height="376" rx="3" fill="url(#laid-ribs)" />

  <!-- 3. Inner Architectural Hairline Rule (1px #9E9A90) -->
  <rect x="8" y="8" width="784" height="364" rx="2" fill="none" stroke="#9E9A90" stroke-width="1" />

  <!-- ==================== HEADER SECTION ==================== -->
  <g transform="translate(24, 22)">
    <!-- Eyebrow Tag -->
    <text x="0" y="11" class="category-eyebrow">Kindle Carta 1300 E-Ink Mode • Halftone Ledger</text>
    
    <!-- Title & Subtitle -->
    <text x="0" y="30" class="serif-title">FERROUS READER — RELEASE TRAJECTORY</text>
    <text x="0" y="45" class="serif-subtitle">Cumulative package distribution &amp; milestone velocity across GitHub releases</text>

    <!-- Total Downloads Inverted Stamp -->
    <g transform="translate(500, 6)">
      <rect x="0" y="0" width="132" height="30" rx="1.5" fill="#1A1A18" />
      <rect x="2" y="2" width="128" height="26" rx="1" fill="none" stroke="#EAE6DF" stroke-width="0.8" />
      <text x="66" y="19" text-anchor="middle" class="ledger-num" fill="#EAE6DF">{total} DOWNLOADS</text>
    </g>

    <!-- Active Release Carta Stamp -->
    <g transform="translate(642, 6)">
      <rect x="0" y="0" width="114" height="30" rx="1.5" fill="#E0DCD3" stroke="#1A1A18" stroke-width="1.5" />
      <rect x="0" y="0" width="114" height="30" rx="1.5" fill="url(#halftone-light)" />
      <text x="57" y="19" text-anchor="middle" class="ledger-num" fill="#1A1A18">{latest_tag} STABLE</text>
    </g>
  </g>

  <!-- Letterpress Double Divider Rule -->
  <line x1="20" y1="78" x2="780" y2="78" stroke="#1A1A18" stroke-width="1.5" />
  <line x1="20" y1="81" x2="780" y2="81" stroke="#9E9A90" stroke-width="0.8" />

  <!-- ==================== INLINE KEY / LEGEND ==================== -->
  <g transform="translate(68, 94)">
    <rect x="0" y="-7" width="12" height="8" fill="#D5D0C5" stroke="#1A1A18" stroke-width="0.8" />
    <rect x="0" y="-7" width="12" height="8" fill="url(#halftone-delta)" />
    <text x="17" y="0" class="legend-label">RELEASE SURGE [+DELTA]</text>

    <rect x="168" y="-7" width="12" height="8" fill="#E0DCD3" stroke="#1A1A18" stroke-width="0.8" />
    <rect x="168" y="-7" width="12" height="8" fill="url(#halftone-base)" />
    <text x="185" y="0" class="legend-label">PRIOR CUMULATIVE BASE</text>
  </g>

  <!-- ==================== GRAPH PLOT AREA ==================== -->
  <!-- Y-Axis Grid Lines & Numbers (Scale: 0 to {max_scale}, Baseline y=285, Top y=105) -->
  <g>
    <!-- {lbl_600} -->
    <line x1="68" y1="{g_600}" x2="755" y2="{g_600}" class="leader-line" stroke-dasharray="2, 3" stroke-width="1" />
    <text x="58" y="{g_600 + 4}" text-anchor="end" class="axis-num">{lbl_600}</text>

    <!-- {lbl_450} -->
    <line x1="68" y1="{g_450}" x2="755" y2="{g_450}" class="leader-line" stroke-dasharray="2, 3" stroke-width="1" />
    <text x="58" y="{g_450 + 4}" text-anchor="end" class="axis-num">{lbl_450}</text>

    <!-- {lbl_300} -->
    <line x1="68" y1="{g_300}" x2="755" y2="{g_300}" class="leader-line" stroke-dasharray="2, 3" stroke-width="1" />
    <text x="58" y="{g_300 + 4}" text-anchor="end" class="axis-num">{lbl_300}</text>

    <!-- {lbl_150} -->
    <line x1="68" y1="{g_150}" x2="755" y2="{g_150}" class="leader-line" stroke-dasharray="2, 3" stroke-width="1" />
    <text x="58" y="{g_150 + 4}" text-anchor="end" class="axis-num">{lbl_150}</text>
  </g>

  <!-- Shaded Halftone Scrim Under Curve (Rendered behind columns for clean contrast) -->
  <path d="M 145 285
           L 145 {y1}
           C 215 {y1}, 215 {y2}, 285 {y2}
           C 355 {y2}, 355 {y3}, 425 {y3}
           C 495 {y3}, 495 {y4}, 565 {y4}
           C 635 {y4}, 635 {y5}, 705 {y5}
           L 705 285 Z"
        fill="url(#halftone-dense)" />

  <!-- ==================== STACKED HALFTONE COLUMNS ==================== -->
  <!-- v1.0.0 (Total={c[0]}, Delta=+{d[0]}, y={y1}, h={h1}) -->
  <g>
    <rect x="116" y="{y1}" width="58" height="{h1}" fill="#D5D0C5" stroke="#1A1A18" stroke-width="1" />
    <rect x="116" y="{y1}" width="58" height="{h1}" fill="url(#halftone-delta)" />
  </g>

  <!-- v1.1.0 (Total={c[1]}, Prior={c[0]} [h={h2_prior}], Delta=+{d[1]} [h={h2_delta}], y={y2}) -->
  <g>
    <rect x="256" y="{y2}" width="58" height="{h2}" fill="#E0DCD3" stroke="#1A1A18" stroke-width="1" />
    <rect x="256" y="{y1}" width="58" height="{h2_prior}" fill="url(#halftone-base)" />
    <rect x="256" y="{y2}" width="58" height="{h2_delta}" fill="#D5D0C5" stroke="#1A1A18" stroke-width="1" />
    <rect x="256" y="{y2}" width="58" height="{h2_delta}" fill="url(#halftone-delta)" />
  </g>

  <!-- v1.2.x (Total={c[2]}, Prior={c[1]} [h={h3_prior}], Delta=+{d[2]} [h={h3_delta}], y={y3}) -->
  <g>
    <rect x="396" y="{y3}" width="58" height="{h3}" fill="#E0DCD3" stroke="#1A1A18" stroke-width="1" />
    <rect x="396" y="{y2}" width="58" height="{h3_prior}" fill="url(#halftone-base)" />
    <rect x="396" y="{y3}" width="58" height="{h3_delta}" fill="#D5D0C5" stroke="#1A1A18" stroke-width="1" />
    <rect x="396" y="{y3}" width="58" height="{h3_delta}" fill="url(#halftone-delta)" />
  </g>

  <!-- v1.3.x (Total={c[3]}, Prior={c[2]} [h={h4_prior}], Delta=+{d[3]} [h={h4_delta}], y={y4}) -->
  <g>
    <rect x="536" y="{y4}" width="58" height="{h4}" fill="#E0DCD3" stroke="#1A1A18" stroke-width="1" />
    <rect x="536" y="{y3}" width="58" height="{h4_prior}" fill="url(#halftone-base)" />
    <rect x="536" y="{y4}" width="58" height="{h4_delta}" fill="#D5D0C5" stroke="#1A1A18" stroke-width="1" />
    <rect x="536" y="{y4}" width="58" height="{h4_delta}" fill="url(#halftone-delta)" />
  </g>

  <!-- {latest_tag} (Active Stable Column: Total={c[4]}, Prior={c[3]} [h={h5_prior}], Delta=+{d[4]} [h={h5_delta}], y={y5}) -->
  <g>
    <rect x="676" y="{y5}" width="58" height="{h5}" fill="#E0DCD3" stroke="#1A1A18" stroke-width="1.8" />
    <rect x="676" y="{y4}" width="58" height="{h5_prior}" fill="url(#halftone-base)" />
    <rect x="676" y="{y5}" width="58" height="{h5_delta}" fill="#D5D0C5" stroke="#1A1A18" stroke-width="1" />
    <rect x="676" y="{y5}" width="58" height="{h5_delta}" fill="url(#halftone-column-active)" />
    <!-- Top solid carbon cap for latest delta (+{d[4]}) -->
    <rect x="676" y="{y5}" width="58" height="3.5" fill="#1A1A18" />
  </g>

  <!-- 0 Baseline (Solid Carbon Rule placed over bar bottoms for crisp alignment) -->
  <line x1="68" y1="285" x2="755" y2="285" stroke="#1A1A18" stroke-width="1.8" />
  <text x="58" y="289" text-anchor="end" class="axis-num">0</text>

  <!-- ==================== MAIN TRAJECTORY CURVE ==================== -->
  <!-- Paper halo behind curve so line reads clearly across bar edges -->
  <path d="M 145 {y1}
           C 215 {y1}, 215 {y2}, 285 {y2}
           C 355 {y2}, 355 {y3}, 425 {y3}
           C 495 {y3}, 495 {y4}, 565 {y4}
           C 635 {y4}, 635 {y5}, 705 {y5}"
        fill="none" stroke="#EAE6DF" stroke-width="5.5" stroke-linecap="round" stroke-linejoin="round" />

  <!-- Solid Carbon Ink Trajectory Rule (Monotone Cubic Bezier) -->
  <path d="M 145 {y1}
           C 215 {y1}, 215 {y2}, 285 {y2}
           C 355 {y2}, 355 {y3}, 425 {y3}
           C 495 {y3}, 495 {y4}, 565 {y4}
           C 635 {y4}, 635 {y5}, 705 {y5}"
        fill="none" stroke="#1A1A18" stroke-width="2.8" stroke-linecap="round" stroke-linejoin="round" />

  <!-- ==================== MILESTONE NODES & LABELS ==================== -->
  <!-- v1.0.0 -->
  <circle cx="145" cy="{y1}" r="5" fill="#EAE6DF" stroke="#1A1A18" stroke-width="2" />
  <text x="145" y="{y1 - 13}" text-anchor="middle" class="ledger-num" fill="#1A1A18">{c[0]}</text>
  <text x="145" y="303" text-anchor="middle" class="version-title">v1.0.0</text>
  <text x="145" y="316" text-anchor="middle" class="milestone-desc">Launch</text>
  <text x="145" y="329" text-anchor="middle" class="delta-badge">[+{d[0]}]</text>

  <!-- v1.1.0 -->
  <circle cx="285" cy="{y2}" r="5" fill="#EAE6DF" stroke="#1A1A18" stroke-width="2" />
  <text x="285" y="{y2 - 13}" text-anchor="middle" class="ledger-num" fill="#1A1A18">{c[1]}</text>
  <text x="285" y="303" text-anchor="middle" class="version-title">v1.1.0</text>
  <text x="285" y="316" text-anchor="middle" class="milestone-desc">PDFium &amp; TTS</text>
  <text x="285" y="329" text-anchor="middle" class="delta-badge">[+{d[1]}]</text>

  <!-- v1.2.x -->
  <circle cx="425" cy="{y3}" r="5" fill="#EAE6DF" stroke="#1A1A18" stroke-width="2" />
  <text x="425" y="{y3 - 13}" text-anchor="middle" class="ledger-num" fill="#1A1A18">{c[2]}</text>
  <text x="425" y="303" text-anchor="middle" class="version-title">v1.2.x</text>
  <text x="425" y="316" text-anchor="middle" class="milestone-desc">Library &amp; E-Ink</text>
  <text x="425" y="329" text-anchor="middle" class="delta-badge">[+{d[2]}]</text>

  <!-- v1.3.x -->
  <circle cx="565" cy="{y4}" r="5" fill="#EAE6DF" stroke="#1A1A18" stroke-width="2" />
  <text x="565" y="{y4 - 13}" text-anchor="middle" class="ledger-num" fill="#1A1A18">{c[3]}</text>
  <text x="565" y="303" text-anchor="middle" class="version-title">v1.3.x</text>
  <text x="565" y="316" text-anchor="middle" class="milestone-desc">DOM &amp; CBR</text>
  <text x="565" y="329" text-anchor="middle" class="delta-badge">[+{d[3]}]</text>

  <!-- v1.4.0 (Active Stable Highlight Marker) -->
  <circle cx="705" cy="{y5}" r="10.5" fill="#EAE6DF" fill-opacity="0.7" stroke="#1A1A18" stroke-width="1.2" stroke-dasharray="2, 2" />
  <circle cx="705" cy="{y5}" r="5.5" fill="#1A1A18" />
  
  <!-- Inverted Callout Tag for Current Milestone -->
  <g transform="translate(675, {tag_y})">
    <rect x="0" y="0" width="60" height="20" rx="1.5" fill="#1A1A18" />
    <polygon points="26,20 34,20 30,24" fill="#1A1A18" />
    <text x="30" y="14" text-anchor="middle" class="ledger-num" fill="#EAE6DF">{total}+</text>
  </g>
  <text x="705" y="303" text-anchor="middle" class="version-title">{latest_tag}</text>
  <text x="705" y="316" text-anchor="middle" class="milestone-desc">Safe Paging</text>
  <text x="705" y="329" text-anchor="middle" class="delta-badge">★ [+{d[4]}] Stable</text>

  <!-- ==================== FOOTER COLOPHON ==================== -->
  <line x1="20" y1="346" x2="780" y2="346" stroke="#9E9A90" stroke-width="0.8" />
  <text x="400" y="364" text-anchor="middle" class="colophon-text">
    Kindle Carta 1300 E-Paper Specification • Zero-Telemetry Offline Persistence • GitHub.com/JuanSoFly/Ferrous
  </text>
</svg>
"""
    return svg_content

def main():
    repo_root = Path(__file__).resolve().parent.parent
    target_svg = repo_root / "assets" / "downloads-graph.svg"

    print(f"Fetching GitHub releases for {REPO}...")
    try:
        releases = fetch_releases()
    except Exception as e:
        print(f"Error fetching releases: {e}", file=sys.stderr)
        sys.exit(1)

    data = compute_milestones(releases)
    print(f"Calculated metrics: Total={data['total']}, Latest Tag={data['latest_tag']}, Deltas={data['deltas']}")

    new_svg = generate_svg(data)
    target_svg.write_text(new_svg, encoding="utf-8")
    print(f"Updated {target_svg} successfully.")

if __name__ == "__main__":
    main()
