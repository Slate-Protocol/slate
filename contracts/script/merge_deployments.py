"""Folds deployments/<chainId>.json (written by Deploy.s.sol) into deployments/deployments.json."""
import json, pathlib

root = pathlib.Path(__file__).resolve().parents[2] / "deployments"
manifest_path = root / "deployments.json"
manifest = json.loads(manifest_path.read_text())

for run in sorted(root.glob("[0-9]*.json")):
    chain_id = run.stem
    data = json.loads(run.read_text())
    manifest["networks"][chain_id]["contracts"] = data["contracts"]
    manifest["feeds"] = [f for f in manifest["feeds"] if str(f["chainId"]) != chain_id]
    for symbol, f in data["feeds"].items():
        manifest["feeds"].append({"symbol": symbol, "chainId": int(chain_id), "token": f["token"], "feed": f["feed"]})

manifest["feeds"].sort(key=lambda f: (f["chainId"], f["symbol"]))
manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
print(f"{len(manifest['feeds'])} feeds across {sum(1 for n in manifest['networks'].values() if n['contracts'])} networks")
