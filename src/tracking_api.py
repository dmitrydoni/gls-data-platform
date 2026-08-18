"""A minimal paginated tracking API over the generated parcel data.

Stands in for the internal tracking service GLS/NXT would expose. It exists so
the ingestion path is a real HTTP pagination loop rather than a file read - the
proposal claims dlt handles REST sources, and this makes that claim executable.

Deliberately stdlib only: the prototype should not need a web framework to prove
a pagination contract.
"""

import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import ClassVar
from urllib.parse import parse_qs, urlparse

HOST = "127.0.0.1"
PORT = 8420
DEFAULT_PAGE_SIZE = 1000
RAW_DIR = Path("data/raw")

COLLECTIONS = {
    "/v1/scan-events": ("scan_events.json", "events"),
    "/v1/parcels": ("parcels.json", "parcels"),
    "/v1/locations": ("locations.json", "locations"),
}


def _load(filename: str) -> list[dict]:
    path = RAW_DIR / filename
    if not path.exists():
        raise FileNotFoundError(f"{path} not found - run the generator first")
    return json.loads(path.read_text(encoding="utf-8"))


class TrackingHandler(BaseHTTPRequestHandler):
    # Shared across requests: the dataset is read once and reused, so paging
    # does not re-read the file for every page.
    cache: ClassVar[dict[str, list[dict]]] = {}

    def do_GET(self) -> None:
        parsed = urlparse(self.path)
        if parsed.path == "/health":
            self._json(200, {"status": "ok"})
            return

        collection = COLLECTIONS.get(parsed.path)
        if collection is None:
            self._json(404, {"error": "unknown collection"})
            return

        filename, envelope_key = collection
        if filename not in self.cache:
            self.cache[filename] = _load(filename)
        records = self.cache[filename]

        query = parse_qs(parsed.query)
        page = int(query.get("page", ["1"])[0])
        per_page = int(query.get("per_page", [str(DEFAULT_PAGE_SIZE)])[0])

        # Incremental reads ask for everything accepted after a watermark, and
        # the watermark is the feed's own sequence number. Both obvious payload
        # columns are wrong here. `eventTime` is when the scan happened, so a
        # handheld that buffered for two days would have its backlog filtered
        # out on arrival. `recordTime` is when the service accepted it - the
        # right clock, the wrong owner: it is a column the contract can find
        # missing, and a row the feed cannot position is a row it must either
        # re-serve on every request or drop from the feed permanently.
        #
        # The boundary is exclusive because the sequence strictly increases, so
        # a re-run neither repeats a row nor steps over one.
        since_offset = int(query.get("since_offset", ["0"])[0])
        if since_offset:
            records = [r for r in records if r["feedOffset"] > since_offset]

        start = (page - 1) * per_page
        window = records[start : start + per_page]
        total_pages = max(1, -(-len(records) // per_page))

        self._json(
            200,
            {
                envelope_key: window,
                "page": page,
                "per_page": per_page,
                "total_pages": total_pages,
                "total_count": len(records),
            },
        )

    def log_message(self, *args) -> None:
        """Silence per-request logging; the ingestion run is the interesting output."""

    def _json(self, status: int, payload: dict) -> None:
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def main() -> None:
    server = ThreadingHTTPServer((HOST, PORT), TrackingHandler)
    print(f"tracking API on http://{HOST}:{PORT} (ctrl-c to stop)")
    server.serve_forever()


if __name__ == "__main__":
    main()
