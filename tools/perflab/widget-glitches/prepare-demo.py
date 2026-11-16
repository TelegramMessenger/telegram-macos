import argparse
from pathlib import Path
import shutil


SOURCES = {
    "sprint": "01-design-crew/04-priya-bare.html",
    "weather": "06-trip-lisbon/05-tom-bare.html",
    "packing": "06-trip-lisbon/10-ana-bare.html",
    "phrasebook": "06-trip-lisbon/12-ana.html",
    "reviews": "07-shop/08-shop-bare.html",
    "retention-cohorts": "08-analytics/09-bot-bare.html",
    "shortcuts": "09-code-review/09-me.html",
    "type-specimen": "03-stress-test/01-fuzz.html",
    "sudoku": "10-game-night/09-sam-bare.html",
    "live-poll": "11-live-scripts/04-theo-bare.html",
    "tic-tac-toe": "11-live-scripts/06-nora-bare.html",
    "whack-a-mole": "11-live-scripts/07-theo-bare.html",
    "stopwatch": "11-live-scripts/10-pixel-bare.html",
    "dice": "11-live-scripts/11-nora-bare.html",
    "music-player": "12-motion-lab/05-mo-bare.html",
    "slots": "12-motion-lab/13-mo-bare.html",
}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--bundled", action="store_true")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[3]
    args.out.mkdir(parents=True, exist_ok=True)
    if args.bundled:
        sources = root / "packages/HTMLBubbles/Tests/HTMLBubblesTests/Fixtures/ported"
        files = [(sources / relative, f"{name}.html") for name, relative in SOURCES.items()]
    else:
        files = [(source, source.name) for source in Path(__file__).with_name("repaired").glob("*.html")]
    for source, name in files:
        shutil.copyfile(source, args.out / name)
    print(f"Prepared {len(files)} widgets in {args.out.resolve()}")


if __name__ == "__main__":
    main()
