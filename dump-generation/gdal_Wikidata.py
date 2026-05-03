# gdal: DRIVER_NAME = "Wikidata"
# gdal: DRIVER_SUPPORTED_API_VERSION = [1]
# gdal: DRIVER_DCAP_VECTOR = "YES"
# gdal: DRIVER_DMD_LONGNAME = "Wikidata simplified NDJSON (wikibase-dump-filter)"
# gdal: DRIVER_DMD_EXTENSIONS = "ndjson json"

from gdal_python_driver import BaseDriver, BaseDataset, BaseLayer  # type: ignore[import-not-found]
from osgeo import gdal
import json
import os
import re

print("GDAL driver imported")

def _safe_layer_name(path):
    stem = os.path.splitext(os.path.basename(path))[0]
    return re.sub(r"[^A-Za-z0-9_]", "_", stem) or "wikidata"


def _looks_like_wikidata(first_bytes):
    if not first_bytes:
        return None
    text = first_bytes.decode("utf-8", errors="replace")
    nl = text.find("\n")
    if nl != -1:
        text = text[:nl]
    text = text.lstrip()
    if not text.startswith("{"):
        return None if text.startswith("[") else False
    has_item = '"type":"item"' in text or '"type": "item"' in text
    has_qid = '"id":"Q' in text or '"id": "Q' in text
    if has_item and has_qid:
        return True
    return None


def _read_lang(open_options):
    if not open_options:
        return None
    raw = open_options.get("LANG") or open_options.get("lang")
    if not raw:
        return None
    code = raw.strip().lower()
    if not code or code == "en":
        return None
    return code


class Layer(BaseLayer):
    def __init__(self, path, extra_lang):
        self._path = path
        self._extra_lang = extra_lang
        self.name = _safe_layer_name(path)
        fields = [
            {"name": "id", "type": "String"},
            {"name": "modified", "type": "DateTime"},
            {"name": "label_en", "type": "String"},
            {"name": "description_en", "type": "String"},
        ]
        if extra_lang:
            fields.append({"name": f"label_{extra_lang}", "type": "String"})
            fields.append({"name": f"description_{extra_lang}", "type": "String"})
        self.fields = fields
        self.geometry_fields = [
            {"name": "", "type": "Point", "srs": "EPSG:4326"}
        ]

    def __iter__(self):
        fid = 0
        with open(self._path, "r", encoding="utf-8", errors="replace") as f:
            for lineno, line in enumerate(f, start=1):
                line = line.strip()
                if not line or line in ("[", "]", ","):
                    continue
                if line.endswith(","):
                    line = line[:-1]
                try:
                    item = json.loads(line)
                except json.JSONDecodeError:
                    gdal.Debug("Wikidata", "line %d: invalid JSON, skipping" % lineno)
                    continue

                coords = (item.get("claims") or {}).get("P625") or []
                if not coords:
                    continue

                labels = item.get("labels") or {}
                descs = item.get("descriptions") or {}
                base = {
                    "id": item.get("id"),
                    "modified": item.get("modified"),
                    "label_en": labels.get("en"),
                    "description_en": descs.get("en"),
                }
                if self._extra_lang:
                    base["label_" + self._extra_lang] = labels.get(self._extra_lang)
                    base["description_" + self._extra_lang] = descs.get(self._extra_lang)

                for pair in coords:
                    if not (isinstance(pair, (list, tuple)) and len(pair) == 2):
                        continue
                    lat, lon = pair[0], pair[1]
                    if isinstance(lat, bool) or isinstance(lon, bool):
                        continue
                    if not (isinstance(lat, (int, float)) and isinstance(lon, (int, float))):
                        continue
                    yield {
                        "id": fid,
                        "type": "OGRFeature",
                        "fields": dict(base),
                        "geometry_fields": {"": "POINT(%r %r)" % (lon, lat)},
                    }
                    fid += 1


class Dataset(BaseDataset):
    def __init__(self, path, extra_lang):
        self._path = path
        self._extra_lang = extra_lang
        self.layers = [Layer(path, extra_lang)]


class Driver(BaseDriver):
    def identify(self, filename, first_bytes, open_flags, open_options=None):
        verdict = _looks_like_wikidata(first_bytes)
        if verdict is True:
            return True
        if verdict is None:
            return -1
        return False

    def open(self, filename, first_bytes, open_flags, open_options=None):
        if open_flags & gdal.OF_UPDATE:
            return None
        if self.identify(filename, first_bytes, open_flags, open_options) is not True:
            return None
        return Dataset(filename, _read_lang(open_options))
