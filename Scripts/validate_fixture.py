import json
import math
import sys
from pathlib import Path


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def main(path):
    payload = json.loads(Path(path).read_text(encoding="utf-8"))
    items = {int(item["type"]): item["value"] for item in payload["items"]}
    require(payload["metadata"]["sdkVersion"] == "2.37.1", "SDK version")
    require(items[1] == 84.2 and items[2] == 29.5, "basic values")
    require(items[3] == 26.5 and items[13] == 57.8 and items[112] == 35.0, "core values")
    require(items[15] == 75.1 and items[35] == 19.9 and items[36] == 8.7, "report values")
    require(items[7] != items[31], "type 7 and 31 must remain distinct")
    require([items[t] for t in range(101, 106)] == [3.5, 3.5, 27.1, 9.0, 8.9], "segment muscle order")
    require([items[t] for t in range(113, 118)] == [1.6, 1.5, 12.3, 3.2, 3.2], "segment fat order")
    ratio = items[8] / items[1] * 100
    require(math.isclose(ratio, 5.3444180523, rel_tol=1e-9), "bone mass percentage")
    require(items[111] == 5.3 and items[112] == 35.0, "type 111/112")
    require(999 in items, "unknown type retention")
    print(f"validated {len(items)} item types; boneMassPercentage={ratio:.6f}%")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "Tests/Fixtures/QNScaleMeasurementFixture.redacted.json")
