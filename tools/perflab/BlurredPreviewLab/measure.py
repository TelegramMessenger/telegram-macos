import argparse
import hashlib
import json
from pathlib import Path
import platform
import shutil
import statistics
import subprocess


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("package", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--repetitions", type=int, default=12)
    parser.add_argument("--iterations", type=int, default=100)
    args = parser.parse_args()
    package = args.package.resolve()
    binary = Path(subprocess.check_output(["swift", "build", "--package-path", str(package), "-c", "release", "--show-bin-path"]).decode().strip()) / "BlurBench"
    args.output.mkdir(parents=True, exist_ok=True)
    workloads = [(50, 50), (64, 64), (500, 500), (720, 720), (1280, 720), (1920, 1080)]
    runs = []
    with (args.output / "runs.jsonl").open("w") as raw:
        for repetition in range(args.repetitions):
            for width, height in workloads:
                for scale in [1, 2]:
                    pair = []
                    order = ["baseline", "current"] if repetition % 2 == 0 else ["current", "baseline"]
                    for index, variant in enumerate(order):
                        command = [str(binary), "--width", str(width), "--height", str(height), "--scale", str(scale), "--iterations", str(args.iterations), "--variant", variant, "--run", str(repetition)]
                        result = json.loads(subprocess.check_output(command))
                        assert result["physicalFootprintBefore"] > 0 and result["physicalFootprintAfter"] > 0 and result["maximumResidentSetBytes"] > 0
                        result["order"] = index
                        runs.append(result)
                        pair.append(result)
                        raw.write(json.dumps(result, sort_keys=True) + "\n")
                        raw.flush()
                    assert len({(result["outputWidth"], result["outputHeight"], result["outputChecksum"]) for result in pair}) == 1
    summary = []
    fields = ["cpuSeconds", "p50Microseconds", "p95Microseconds", "coldMicroseconds", "physicalFootprintBefore", "physicalFootprintAfter", "maximumResidentSetBytes"]
    for width, height in workloads:
        for scale in [1, 2]:
            item = {"width": width, "height": height, "scale": scale}
            for variant in ["baseline", "current"]:
                selected = [result for result in runs if (result["width"], result["height"], result["scale"], result["variant"]) == (width, height, scale, variant)]
                item[variant] = {field: {"median": statistics.median(result[field] for result in selected), "min": min(result[field] for result in selected), "max": max(result[field] for result in selected)} for field in fields}
            summary.append(item)
    snapshots = args.output / "inputs"
    snapshots.mkdir(exist_ok=True)
    for module in ["NativeBlur", "TrackedBlur", "BlurBench"]:
        shutil.copytree(package / "Sources" / module, snapshots / module, dirs_exist_ok=True)
    shutil.copytree(package / "Tests", snapshots / "Tests", dirs_exist_ok=True)
    metadata = {"platform": platform.platform(), "repetitions": args.repetitions, "iterations": args.iterations, "measurements": len(runs), "order": "Alternating baseline/current and current/baseline; a fresh process for each variant/workload/repetition.", "scope": "Real complete TGUIKit, native DrawingContext, FastBlur, CoreGraphics and the production CGImage extension. Opaque generated image fixtures, no camera capture, video decoding or Telegram account/UI.", "memory": "getrusage.ru_maxrss is the whole-process RSS high-water mark, including fixture creation and warmup; task_vm_info.phys_footprint is sampled after warmup and the measured loop. Native bitmap budget tests separately record DrawingContext.length.", "binary_sha256": hashlib.sha256(binary.read_bytes()).hexdigest(), "provenance": json.loads((package / "provenance.json").read_text()), "summary": summary}
    (args.output / "summary.json").write_text(json.dumps(metadata, indent=2) + "\n")
    for item in summary:
        print(json.dumps({"size": [item["width"], item["height"]], "scale": item["scale"], "cpu_ms": [round(item[v]["cpuSeconds"]["median"] * 1000, 3) for v in ["baseline", "current"]], "p95_us": [round(item[v]["p95Microseconds"]["median"], 3) for v in ["baseline", "current"]], "rss_mib": [round(item[v]["maximumResidentSetBytes"]["median"] / 1048576, 3) for v in ["baseline", "current"]]}))


if __name__ == "__main__":
    main()
