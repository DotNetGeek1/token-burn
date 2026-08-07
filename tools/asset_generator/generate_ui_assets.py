#!/usr/bin/env python3
"""Generate Token Burn UI SVG assets matching the visual style guide."""

from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "presentation" / "ui"

# Style guide palette
COLORS = {
    "bg": "#121212",
    "bg_panel": "#1a1a24",
    "stroke_dim": "#2a2a3a",
    "green": "#39ff88",
    "blue": "#4dc3ff",
    "orange": "#ff6b35",
    "red": "#e94560",
    "purple": "#b066ff",
    "yellow": "#ffd54a",
    "white": "#e8e8f0",
    "grey": "#6a6a7a",
}

RARITY_COLORS = {
    "common": COLORS["green"],
    "rare": COLORS["blue"],
    "epic": COLORS["purple"],
    "legendary": COLORS["yellow"],
}


def svg_header(size: int = 128) -> str:
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" '
        f'viewBox="0 0 {size} {size}">\n'
    )


def svg_footer() -> str:
    return "</svg>\n"


def write_svg(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")
    print(f"  wrote {path.relative_to(ROOT)}")


def icon_circle(color: str, glow: bool = True) -> str:
    glow_filter = ""
    if glow:
        glow_filter = (
            f'<defs><filter id="glow" x="-50%" y="-50%" width="200%" height="200%">'
            f'<feGaussianBlur stdDeviation="2" result="blur"/>'
            f'<feMerge><feMergeNode in="blur"/><feMergeNode in="SourceGraphic"/></feMerge>'
            f"</filter></defs>"
        )
    filter_attr = ' filter="url(#glow)"' if glow else ""
    return (
        f"{glow_filter}"
        f'<circle cx="64" cy="64" r="58" fill="{COLORS["bg"]}" stroke="{COLORS["stroke_dim"]}" stroke-width="2"/>'
        f'<circle cx="64" cy="64" r="52" fill="none" stroke="{color}" stroke-width="1.5" opacity="0.35"/>'
    )


def make_icon(name: str, color: str, inner: str, folder: str) -> None:
    content = svg_header() + icon_circle(color) + inner + svg_footer()
    write_svg(OUT / "icons" / folder / f"{name}.svg", content)


def generate_nav_icons() -> None:
    print("Nav icons...")
    make_icon(
        "office",
        COLORS["blue"],
        '<g stroke="#4dc3ff" stroke-width="3" fill="none" stroke-linecap="round" stroke-linejoin="round">'
        '<rect x="36" y="44" width="56" height="40" rx="4"/>'
        '<line x1="36" y1="56" x2="92" y2="56"/>'
        '<rect x="44" y="62" width="16" height="10" rx="1" fill="#4dc3ff" opacity="0.3"/>'
        '<rect x="68" y="62" width="16" height="10" rx="1" fill="#4dc3ff" opacity="0.3"/>'
        "</g>",
        "nav",
    )
    make_icon(
        "jobs",
        COLORS["green"],
        '<g stroke="#39ff88" stroke-width="3" fill="none" stroke-linecap="round">'
        '<rect x="40" y="38" width="48" height="56" rx="6"/>'
        '<line x1="50" y1="54" x2="78" y2="54"/>'
        '<line x1="50" y1="66" x2="72" y2="66"/>'
        '<line x1="50" y1="78" x2="68" y2="78"/>'
        '<polyline points="46,50 50,54 58,46" stroke-width="2.5"/>'
        "</g>",
        "nav",
    )
    make_icon(
        "build",
        COLORS["purple"],
        '<g stroke="#b066ff" stroke-width="3" fill="none" stroke-linecap="round" stroke-linejoin="round">'
        '<circle cx="64" cy="64" r="22"/>'
        '<circle cx="64" cy="64" r="8" fill="#b066ff" opacity="0.4"/>'
        '<line x1="64" y1="38" x2="64" y2="46"/>'
        '<line x1="64" y1="82" x2="64" y2="90"/>'
        '<line x1="38" y1="64" x2="46" y2="64"/>'
        '<line x1="82" y1="64" x2="90" y2="64"/>'
        '<polygon points="64,44 68,52 60,52" fill="#b066ff" opacity="0.6"/>'
        "</g>",
        "nav",
    )
    make_icon(
        "market",
        COLORS["yellow"],
        '<g stroke="#ffd54a" stroke-width="3" fill="none" stroke-linecap="round" stroke-linejoin="round">'
        '<path d="M40 52 L48 36 L80 36 L88 52 Z"/>'
        '<rect x="44" y="52" width="40" height="36" rx="4"/>'
        '<line x1="52" y1="64" x2="76" y2="64"/>'
        "</g>",
        "nav",
    )
    make_icon(
        "menu",
        COLORS["grey"],
        '<g stroke="#9a9aaa" stroke-width="3" fill="none" stroke-linecap="round">'
        '<line x1="40" y1="48" x2="88" y2="48"/>'
        '<line x1="40" y1="64" x2="88" y2="64"/>'
        '<line x1="40" y1="80" x2="88" y2="80"/>'
        "</g>",
        "nav",
    )


def generate_stat_icons() -> None:
    print("Stat icons...")
    make_icon(
        "cash",
        COLORS["green"],
        '<g stroke="#39ff88" stroke-width="3" fill="none">'
        '<circle cx="64" cy="64" r="26"/>'
        '<text x="64" y="72" font-family="Arial,sans-serif" font-size="28" font-weight="bold" '
        'fill="#39ff88" text-anchor="middle">$</text>'
        "</g>",
        "stat",
    )
    make_icon(
        "tokens",
        COLORS["blue"],
        '<g stroke="#4dc3ff" stroke-width="3" fill="none">'
        '<circle cx="64" cy="64" r="26"/>'
        '<text x="64" y="72" font-family="Arial,sans-serif" font-size="24" font-weight="bold" '
        'fill="#4dc3ff" text-anchor="middle">T</text>'
        "</g>",
        "stat",
    )
    make_icon(
        "heat",
        COLORS["orange"],
        '<g stroke="#ff6b35" stroke-width="3" fill="none" stroke-linecap="round" stroke-linejoin="round">'
        '<path d="M64 90 C52 78 48 68 52 58 C54 52 58 48 64 38 C70 48 74 52 76 58 C80 68 76 78 64 90 Z"/>'
        '<path d="M64 82 C58 74 56 68 58 62 C59 58 61 56 64 50 C67 56 69 58 70 62 C72 68 70 74 64 82 Z" '
        'fill="#ff6b35" opacity="0.4"/>'
        "</g>",
        "stat",
    )
    make_icon(
        "power",
        COLORS["yellow"],
        '<g stroke="#ffd54a" stroke-width="3" fill="none" stroke-linecap="round" stroke-linejoin="round">'
        '<polygon points="72,36 48,68 60,68 56,96 80,60 68,60 72,36" fill="#ffd54a" opacity="0.25"/>'
        "</g>",
        "stat",
    )
    make_icon(
        "reputation",
        COLORS["green"],
        '<g stroke="#39ff88" stroke-width="3" fill="none" stroke-linecap="round" stroke-linejoin="round">'
        '<path d="M40 72 L52 48 L64 60 L76 44 L88 72 Z"/>'
        '<line x1="40" y1="72" x2="88" y2="72"/>'
        "</g>",
        "stat",
    )
    make_icon(
        "quality",
        COLORS["yellow"],
        '<g stroke="#ffd54a" stroke-width="3" fill="none" stroke-linecap="round" stroke-linejoin="round">'
        '<circle cx="64" cy="64" r="28"/>'
        '<polyline points="48,64 58,76 82,50"/>'
        "</g>",
        "stat",
    )
    make_icon(
        "deadline",
        COLORS["green"],
        '<g stroke="#39ff88" stroke-width="3" fill="none" stroke-linecap="round">'
        '<circle cx="64" cy="68" r="26"/>'
        '<line x1="64" y1="68" x2="64" y2="52"/>'
        '<line x1="64" y1="68" x2="76" y2="72"/>'
        '<line x1="64" y1="38" x2="64" y2="44"/>'
        "</g>",
        "stat",
    )
    make_icon(
        "agents",
        COLORS["blue"],
        '<g stroke="#4dc3ff" stroke-width="3" fill="none" stroke-linecap="round">'
        '<circle cx="48" cy="50" r="8"/><circle cx="80" cy="50" r="8"/><circle cx="64" cy="42" r="10"/>'
        '<path d="M32 88 C32 72 42 64 48 64"/><path d="M80 64 C86 64 96 72 96 88"/>'
        '<path d="M52 66 C56 62 72 62 76 66 L76 88 L52 88 Z" fill="#4dc3ff" opacity="0.15"/>'
        "</g>",
        "stat",
    )


def generate_category_icons() -> None:
    print("Category icons...")
    make_icon(
        "cloud",
        COLORS["blue"],
        '<g stroke="#4dc3ff" stroke-width="3" fill="none" stroke-linecap="round" stroke-linejoin="round">'
        '<path d="M36 72 C28 72 24 64 28 56 C30 48 38 44 46 46 C50 36 62 32 72 38 C82 44 86 56 80 66 C84 70 84 76 78 80 L42 80 C36 80 32 76 36 72 Z"/>'
        "</g>",
        "category",
    )
    make_icon(
        "local",
        COLORS["green"],
        '<g stroke="#39ff88" stroke-width="3" fill="none" stroke-linecap="round" stroke-linejoin="round">'
        '<rect x="44" y="40" width="40" height="48" rx="4"/>'
        '<rect x="50" y="48" width="12" height="8" rx="1" fill="#39ff88" opacity="0.3"/>'
        '<line x1="48" y1="88" x2="80" y2="88"/>'
        "</g>",
        "category",
    )
    make_icon(
        "hybrid",
        COLORS["purple"],
        '<g stroke="#b066ff" stroke-width="3" fill="none" stroke-linecap="round">'
        '<path d="M32 70 C26 70 22 64 26 56 C28 50 34 46 40 48"/>'
        '<rect x="48" y="48" width="32" height="36" rx="4"/>'
        '<line x1="40" y1="64" x2="48" y2="64" stroke-dasharray="4 3"/>'
        "</g>",
        "category",
    )
    make_icon(
        "hardware",
        COLORS["blue"],
        '<g stroke="#4dc3ff" stroke-width="3" fill="none" stroke-linecap="round" stroke-linejoin="round">'
        '<rect x="36" y="36" width="56" height="56" rx="8"/>'
        '<rect x="44" y="44" width="16" height="16" rx="2" fill="#4dc3ff" opacity="0.2"/>'
        '<rect x="68" y="44" width="16" height="16" rx="2" fill="#4dc3ff" opacity="0.2"/>'
        '<rect x="44" y="68" width="16" height="16" rx="2" fill="#4dc3ff" opacity="0.2"/>'
        '<rect x="68" y="68" width="16" height="16" rx="2" fill="#4dc3ff" opacity="0.2"/>'
        "</g>",
        "category",
    )
    make_icon(
        "perks",
        COLORS["purple"],
        '<g stroke="#b066ff" stroke-width="3" fill="none" stroke-linecap="round" stroke-linejoin="round">'
        '<circle cx="64" cy="58" r="20"/>'
        '<polygon points="64,34 68,46 80,46 70,54 74,66 64,58 54,66 58,54 48,46 60,46" '
        'fill="#b066ff" opacity="0.35"/>'
        "</g>",
        "category",
    )


def generate_status_icons() -> None:
    print("Status icons...")
    make_icon(
        "warning",
        COLORS["orange"],
        '<g stroke="#ff6b35" stroke-width="3" fill="none" stroke-linecap="round" stroke-linejoin="round">'
        '<path d="M64 36 L92 84 L36 84 Z"/>'
        '<line x1="64" y1="54" x2="64" y2="68"/>'
        '<circle cx="64" cy="76" r="2" fill="#ff6b35"/>'
        "</g>",
        "status",
    )
    make_icon(
        "event",
        COLORS["purple"],
        '<g stroke="#b066ff" stroke-width="3" fill="none" stroke-linecap="round">'
        '<circle cx="64" cy="64" r="28"/>'
        '<line x1="64" y1="48" x2="64" y2="72"/>'
        '<circle cx="64" cy="80" r="3" fill="#b066ff"/>'
        "</g>",
        "status",
    )
    make_icon(
        "bug",
        COLORS["red"],
        '<g stroke="#e94560" stroke-width="3" fill="none" stroke-linecap="round" stroke-linejoin="round">'
        '<ellipse cx="64" cy="60" rx="16" ry="20"/>'
        '<line x1="48" y1="52" x2="38" y2="44"/><line x1="80" y1="52" x2="90" y2="44"/>'
        '<line x1="48" y1="68" x2="36" y2="72"/><line x1="80" y1="68" x2="92" y2="72"/>'
        '<line x1="56" y1="48" x2="58" y2="40"/><line x1="72" y1="48" x2="70" y2="40"/>'
        "</g>",
        "status",
    )


PERK_ICONS: dict[str, tuple[str, str]] = {
    "ship_it": (COLORS["green"], '<polygon points="64,36 72,56 92,56 76,68 82,88 64,76 46,88 52,68 36,56 56,56" fill="#39ff88" opacity="0.2"/>'),
    "recursive_intern": (COLORS["blue"], '<circle cx="64" cy="50" r="12"/><path d="M44 88 C44 72 52 64 64 64 C76 64 84 72 84 88" fill="#4dc3ff" opacity="0.15"/><path d="M64 64 L64 48 M64 48 L58 54 M64 48 L70 54" stroke-width="2.5"/>'),
    "stack_overflow_tab": (COLORS["orange"], '<rect x="40" y="40" width="48" height="36" rx="4"/><line x1="48" y1="52" x2="80" y2="52"/><line x1="48" y1="62" x2="72" y2="62"/><text x="64" y="82" font-size="14" fill="#ff6b35" text-anchor="middle">SO</text>'),
    "free_trial": (COLORS["blue"], '<path d="M36 72 C28 72 24 64 28 56 C30 48 38 44 46 46 C50 36 62 32 72 38 C82 44 86 56 80 66 C84 70 84 76 78 80 L42 80 C36 80 32 76 36 72 Z"/><text x="64" y="68" font-size="16" fill="#4dc3ff" text-anchor="middle">FREE</text>'),
    "quantised_everything": (COLORS["purple"], '<rect x="40" y="40" width="48" height="48" rx="6"/><line x1="48" y1="56" x2="80" y2="56"/><line x1="48" y1="72" x2="80" y2="72"/><line x1="56" y1="48" x2="56" y2="80"/><line x1="72" y1="48" x2="72" y2="80"/>'),
    "works_on_my_machine": (COLORS["green"], '<rect x="44" y="48" width="40" height="28" rx="3"/><line x1="52" y1="84" x2="76" y2="84"/><polyline points="52,72 58,66 64,70 76,58" stroke-width="2.5"/>'),
    "technical_debt": (COLORS["red"], '<path d="M40 80 L48 48 L80 48 L88 80 Z" fill="#e94560" opacity="0.15"/><line x1="48" y1="60" x2="80" y2="60"/><line x1="52" y1="72" x2="76" y2="72"/>'),
    "founder_mode": (COLORS["yellow"], '<circle cx="64" cy="50" r="14"/><path d="M40 88 C40 72 50 62 64 62 C78 62 88 72 88 88" fill="#ffd54a" opacity="0.15"/><line x1="64" y1="36" x2="64" y2="28"/>'),
    "infinite_context": (COLORS["purple"], '<rect x="36" y="44" width="56" height="40" rx="4"/><path d="M36 52 L92 52" stroke-dasharray="6 4"/><text x="64" y="72" font-size="14" fill="#b066ff" text-anchor="middle">∞</text>'),
    "the_wrapper": (COLORS["blue"], '<rect x="44" y="44" width="40" height="40" rx="4" stroke-dasharray="6 3"/><rect x="52" y="52" width="24" height="24" rx="2" fill="#4dc3ff" opacity="0.2"/>'),
    "vibe_check": (COLORS["purple"], '<circle cx="64" cy="64" r="24"/><path d="M52 58 Q64 72 76 58" fill="none"/><circle cx="54" cy="56" r="3" fill="#b066ff"/><circle cx="74" cy="56" r="3" fill="#b066ff"/>'),
    "prompt_engineer": (COLORS["green"], '<rect x="40" y="36" width="48" height="56" rx="4"/><line x1="48" y1="50" x2="80" y2="50"/><line x1="48" y1="62" x2="72" y2="62"/><line x1="48" y1="74" x2="68" y2="74"/><path d="M76 78 L88 84 L76 84 Z" fill="#39ff88" opacity="0.3"/>'),
    "cloud_baron": (COLORS["blue"], '<path d="M32 68 C24 68 20 58 26 50 C28 44 36 40 44 42 C48 32 62 28 74 36 C84 42 88 54 82 64 C86 68 86 74 80 78 L36 78 C30 78 26 74 32 68 Z" fill="#4dc3ff" opacity="0.15"/><text x="64" y="68" font-size="18" fill="#4dc3ff" text-anchor="middle">$</text>'),
    "consultancy_mode": (COLORS["yellow"], '<rect x="36" y="48" width="56" height="36" rx="4"/><line x1="44" y1="60" x2="84" y2="60"/><line x1="44" y1="72" x2="68" y2="72"/><circle cx="76" cy="72" r="6" fill="#ffd54a" opacity="0.3"/>'),
    "ad_tech_goblin": (COLORS["green"], '<circle cx="54" cy="56" r="10"/><circle cx="74" cy="56" r="10"/><path d="M44 76 Q64 92 84 76" fill="none"/><path d="M48 44 L52 36 M80 44 L76 36" stroke-width="2"/>'),
}


def generate_perk_icons() -> None:
    print("Perk icons...")
    for name, (color, inner) in PERK_ICONS.items():
        stroke_group = f'<g stroke="{color}" stroke-width="3" fill="none" stroke-linecap="round" stroke-linejoin="round">{inner}</g>'
        make_icon(name, color, stroke_group, "perks")


def generate_panels() -> None:
    print("Panel assets...")
    card = (
        svg_header(256)
        + f'<rect width="256" height="256" rx="16" fill="{COLORS["bg_panel"]}" '
        f'stroke="{COLORS["stroke_dim"]}" stroke-width="2"/>'
        + f'<rect x="8" y="8" width="240" height="240" rx="12" fill="none" '
        f'stroke="{COLORS["blue"]}" stroke-width="1" opacity="0.2"/>'
        + svg_footer()
    )
    write_svg(OUT / "panels" / "card_bg.svg", card)

    card_highlight = (
        svg_header(256)
        + f'<rect width="256" height="256" rx="16" fill="{COLORS["bg_panel"]}" '
        f'stroke="{COLORS["green"]}" stroke-width="2"/>'
        + f'<rect x="4" y="4" width="248" height="248" rx="14" fill="none" '
        f'stroke="{COLORS["green"]}" stroke-width="1" opacity="0.4"/>'
        + svg_footer()
    )
    write_svg(OUT / "panels" / "card_bg_selected.svg", card_highlight)

    # 9-patch friendly progress bar pieces (256x32)
    for name, color in [
        ("progress_bg", COLORS["stroke_dim"]),
        ("progress_cyan", COLORS["blue"]),
        ("progress_green", COLORS["green"]),
        ("progress_orange", COLORS["orange"]),
        ("progress_yellow", COLORS["yellow"]),
        ("progress_red", COLORS["red"]),
    ]:
        bar = (
            '<svg xmlns="http://www.w3.org/2000/svg" width="256" height="32" viewBox="0 0 256 32">\n'
            f'<rect width="256" height="32" rx="8" fill="{COLORS["bg"]}" stroke="{COLORS["stroke_dim"]}" stroke-width="1"/>'
            f'<rect x="2" y="2" width="252" height="28" rx="7" fill="{color}" opacity="{"0.35" if "bg" in name else "0.85"}"/>'
            + svg_footer()
        )
        write_svg(OUT / "panels" / f"{name}.svg", bar)


def generate_chips() -> None:
    print("Rarity chips...")
    for rarity, color in RARITY_COLORS.items():
        chip = (
            '<svg xmlns="http://www.w3.org/2000/svg" width="128" height="40" viewBox="0 0 128 40">\n'
            f'<rect width="128" height="40" rx="20" fill="{COLORS["bg"]}" stroke="{color}" stroke-width="2"/>'
            f'<rect x="4" y="4" width="120" height="32" rx="16" fill="{color}" opacity="0.15"/>'
            + svg_footer()
        )
        write_svg(OUT / "chips" / f"chip_{rarity}.svg", chip)


def generate_buttons() -> None:
    print("Button assets...")
    buttons = {
        "btn_primary": COLORS["green"],
        "btn_secondary": COLORS["grey"],
        "btn_danger": COLORS["red"],
        "btn_boost": COLORS["blue"],
    }
    for name, color in buttons.items():
        btn = (
            '<svg xmlns="http://www.w3.org/2000/svg" width="320" height="80" viewBox="0 0 320 80">\n'
            f'<rect width="320" height="80" rx="12" fill="{COLORS["bg_panel"]}" stroke="{color}" stroke-width="2"/>'
            f'<rect x="2" y="2" width="316" height="76" rx="10" fill="{color}" opacity="0.08"/>'
            + svg_footer()
        )
        write_svg(OUT / "buttons" / f"{name}.svg", btn)


def generate_logo() -> None:
    print("Logo...")
    logo = (
        svg_header(512)
        + f'<rect width="512" height="512" fill="{COLORS["bg"]}"/>'
        + '<g transform="translate(256,256)">'
        + f'<rect x="-160" y="-80" width="320" height="160" rx="16" fill="{COLORS["bg_panel"]}" '
        f'stroke="{COLORS["red"]}" stroke-width="4"/>'
        + f'<text y="12" font-family="Arial Black,Arial,sans-serif" font-size="72" font-weight="900" '
        f'fill="{COLORS["red"]}" text-anchor="middle" letter-spacing="4">TOKEN</text>'
        + f'<text y="72" font-family="Arial Black,Arial,sans-serif" font-size="56" font-weight="900" '
        f'fill="{COLORS["white"]}" text-anchor="middle" letter-spacing="8">BURN</text>'
        + f'<rect x="-120" y="88" width="240" height="8" rx="4" fill="{COLORS["stroke_dim"]}"/>'
        + f'<rect x="-120" y="88" width="168" height="8" rx="4" fill="{COLORS["red"]}"/>'
        + "</g>"
        + svg_footer()
    )
    write_svg(OUT / "logo" / "token_burn_logo.svg", logo)

    # Compact header logo (wide)
    header = (
        '<svg xmlns="http://www.w3.org/2000/svg" width="480" height="96" viewBox="0 0 480 96">\n'
        + f'<rect width="480" height="96" fill="none"/>'
        + f'<text x="0" y="68" font-family="Arial Black,Arial,sans-serif" font-size="64" font-weight="900" '
        f'fill="{COLORS["red"]}" letter-spacing="2">TOKEN BURN</text>'
        + svg_footer()
    )
    write_svg(OUT / "logo" / "token_burn_header.svg", header)


def generate_catalog() -> None:
    print("Asset catalog...")
    catalog = {
        "version": 1,
        "palette": COLORS,
        "nav_icons": {k: f"res://presentation/ui/icons/nav/{k}.svg" for k in ["office", "jobs", "build", "market", "menu"]},
        "stat_icons": {k: f"res://presentation/ui/icons/stat/{k}.svg" for k in ["cash", "tokens", "heat", "power", "reputation", "quality", "deadline", "agents"]},
        "category_icons": {k: f"res://presentation/ui/icons/category/{k}.svg" for k in ["cloud", "local", "hybrid", "hardware", "perks"]},
        "status_icons": {k: f"res://presentation/ui/icons/status/{k}.svg" for k in ["warning", "event", "bug"]},
        "perk_icons": {k: f"res://presentation/ui/icons/perks/{k}.svg" for k in PERK_ICONS},
        "office_stages": {
            f"stage_{i:02d}": f"res://presentation/office/stage_{i:02d}.png"
            for i in range(1, 6)
        },
        "panels": {
            "card_bg": "res://presentation/ui/panels/card_bg.svg",
            "card_bg_selected": "res://presentation/ui/panels/card_bg_selected.svg",
            "progress": {
                "bg": "res://presentation/ui/panels/progress_bg.svg",
                "cyan": "res://presentation/ui/panels/progress_cyan.svg",
                "green": "res://presentation/ui/panels/progress_green.svg",
                "orange": "res://presentation/ui/panels/progress_orange.svg",
                "yellow": "res://presentation/ui/panels/progress_yellow.svg",
                "red": "res://presentation/ui/panels/progress_red.svg",
            },
        },
        "logo": {
            "full": "res://presentation/ui/logo/token_burn_logo.svg",
            "header": "res://presentation/ui/logo/token_burn_header.svg",
        },
        "event_art": {
            "event.power_cut": "res://presentation/events/event_power_surge.png",
            "event.cloud_bill_shock": "res://presentation/events/event_cloud_bill.png",
            "event.viral_bug": "res://presentation/events/event_viral_bug.png",
            "event.landlord_inspection": "res://presentation/events/event_landlord_inspection.png",
            "default": "res://presentation/events/event_power_surge.png",
        },
        "chips": {
            "common": "res://presentation/ui/chips/chip_common.svg",
            "rare": "res://presentation/ui/chips/chip_rare.svg",
            "epic": "res://presentation/ui/chips/chip_epic.svg",
            "legendary": "res://presentation/ui/chips/chip_legendary.svg",
        },
        "buttons": {
            "primary": "res://presentation/ui/buttons/btn_primary.svg",
            "secondary": "res://presentation/ui/buttons/btn_secondary.svg",
            "danger": "res://presentation/ui/buttons/btn_danger.svg",
            "boost": "res://presentation/ui/buttons/btn_boost.svg",
        },
    }
    import json

    catalog_path = ROOT / "presentation" / "asset_catalog.json"
    catalog_path.write_text(json.dumps(catalog, indent=2) + "\n", encoding="utf-8")
    print(f"  wrote {catalog_path.relative_to(ROOT)}")


def main() -> None:
    print(f"Generating UI assets under {OUT.relative_to(ROOT)}...")
    generate_nav_icons()
    generate_stat_icons()
    generate_category_icons()
    generate_status_icons()
    generate_perk_icons()
    generate_panels()
    generate_chips()
    generate_buttons()
    generate_logo()
    generate_catalog()
    print("Done.")


if __name__ == "__main__":
    main()
