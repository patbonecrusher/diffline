#!/usr/bin/env -S uv run --quiet --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["pyjwt>=2.8", "cryptography>=42", "requests>=2.31"]
# ///
"""Fill in the App Store Connect listing for Diffline through the ASC REST API.

    Tools/asc.py status                 show app, version, builds, what's filled in
    Tools/asc.py metadata               description, keywords, URLs, category, age rating
    Tools/asc.py screenshots [files…]   replace the desktop screenshot set (default: Marketing/screenshot-*.png)
    Tools/asc.py build [1.0] [7]        attach a processed build to the version (latest if omitted)
    Tools/asc.py price                  set the app to free in all territories
    Tools/asc.py review-info            copy contact info into App Review details
    Tools/asc.py submit                 create the review submission and submit it
    Tools/asc.py all                    metadata + screenshots + build + price + review-info (no submit)

Auth: ASC_KEY_ID / ASC_ISSUER_ID env vars, key at ~/.appstoreconnect/private_keys/AuthKey_<id>.p8
"""
import hashlib
import json
import os
import sys
import time
from pathlib import Path

import jwt
import requests

BUNDLE_ID = "com.patlaplante.Diffline"
API = "https://api.appstoreconnect.apple.com/v1"
ROOT = Path(__file__).resolve().parent.parent

LISTING = {
    "description": (
        "Compare and merge files and folders, including three-way merges for git. One-time purchase, no subscription.\n\n"
        "Diffline shows two text files side by side with every changed line aligned, the exact words that "
        "differ highlighted, and long lines wrapped so nothing is hidden off screen. Step through the "
        "changes, take the left or right version of each one, and save. Compare two folders to see which "
        "files were added, removed or modified, then double-click any file to open it.\n\n"
        "• Side-by-side comparison with word-level highlighting\n"
        "• Syntax coloring for Swift, Python, JavaScript, Go, Rust, C, JSON, YAML, HTML, Markdown and more\n"
        "• Merge: take the left or right version of each change, with Undo\n"
        "• Three-way merge: base, yours and theirs with the result in the middle; only real conflicts need a decision\n"
        "• Works as git mergetool and git difftool through the included command-line tool\n"
        "• Folder comparison with recursive status for every file\n"
        "• Ignore whitespace, case or blank lines\n"
        "• Wrapped lines stay aligned on both sides\n"
        "• Export or copy a unified diff (.patch) for any comparison\n"
        "• Drag two items onto the window or Dock icon, or use Compare with Diffline in Finder\n"
        "• Handles files with tens of thousands of lines\n\n"
        "Everything runs on your Mac. No accounts, no tracking, no network access."
    ),
    "promotionalText": "A native diff and merge tool for the Mac. Buy it once.",
    "keywords": "diff,compare,merge,git,mergetool,folder,files,code,patch,conflict",
    "supportUrl": "https://github.com/patbonecrusher/diffline/issues",
    "marketingUrl": "https://patbonecrusher.github.io/diffline/",
    "whatsNew": None,          # not allowed on the first version
}
SUBTITLE = "Compare and merge files"
PRIVACY_URL = "https://patbonecrusher.github.io/diffline/privacy.html"
PRIMARY_CATEGORY = "DEVELOPER_TOOLS"
SECONDARY_CATEGORY = "UTILITIES"
COPYRIGHT = "2026 Patrick Laplante"


# ----------------------------------------------------------------------------- client
class ASC:
    def __init__(self):
        key_id = os.environ.get("ASC_KEY_ID") or die("set ASC_KEY_ID")
        issuer = os.environ.get("ASC_ISSUER_ID") or die("set ASC_ISSUER_ID")
        key_path = Path.home() / ".appstoreconnect/private_keys" / f"AuthKey_{key_id}.p8"
        self.key_id, self.issuer, self.key = key_id, issuer, key_path.read_text()
        self.session = requests.Session()
        self._token_exp = 0

    def _token(self):
        if time.time() > self._token_exp - 60:
            self._token_exp = int(time.time()) + 15 * 60
            self._jwt = jwt.encode(
                {"iss": self.issuer, "iat": int(time.time()), "exp": self._token_exp, "aud": "appstoreconnect-v1"},
                self.key, algorithm="ES256", headers={"kid": self.key_id},
            )
        return self._jwt

    def call(self, method, path, **kw):
        url = path if path.startswith("http") else API + path
        headers = {"Authorization": f"Bearer {self._token()}"}
        if "json" in kw:
            headers["Content-Type"] = "application/json"
        r = self.session.request(method, url, headers=headers, **kw)
        if r.status_code >= 400:
            try:
                errs = r.json().get("errors", [])
                msg = "; ".join(f"{e.get('title')}: {e.get('detail')}" for e in errs)
            except ValueError:
                msg = r.text
            raise RuntimeError(f"{method} {path} → {r.status_code}: {msg}")
        return r.json() if r.content else {}

    def get(self, path, **params):
        return self.call("GET", path, params=params)

    def all(self, path, **params):
        params.setdefault("limit", 200)
        data = []
        page = self.get(path, **params)
        while True:
            data += page["data"]
            nxt = page.get("links", {}).get("next")
            if not nxt:
                return data
            page = self.call("GET", nxt)

    def post(self, path, type_, attributes=None, relationships=None):
        body = {"data": {"type": type_}}
        if attributes:
            body["data"]["attributes"] = attributes
        if relationships:
            body["data"]["relationships"] = {
                k: {"data": v} for k, v in relationships.items()
            }
        return self.call("POST", path, json=body)["data"]

    def patch(self, path, type_, id_, attributes=None, relationships=None):
        body = {"data": {"type": type_, "id": id_}}
        if attributes:
            body["data"]["attributes"] = attributes
        if relationships:
            body["data"]["relationships"] = {k: {"data": v} for k, v in relationships.items()}
        return self.call("PATCH", path, json=body).get("data")


def die(msg):
    print("error:", msg, file=sys.stderr)
    sys.exit(1)


def ref(type_, id_):
    return {"type": type_, "id": id_}


# ----------------------------------------------------------------------------- lookups
def find_app(asc):
    apps = asc.get("/apps", **{"filter[bundleId]": BUNDLE_ID})["data"]
    if not apps:
        die(f"no app with bundle id {BUNDLE_ID} in App Store Connect")
    return apps[0]


def editable_version(asc, app_id, required=True):
    """The macOS version that can still be edited (Prepare for Submission / Rejected / …)."""
    versions = asc.get(f"/apps/{app_id}/appStoreVersions", **{"filter[platform]": "MAC_OS"})["data"]
    editable = {"PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED",
                "WAITING_FOR_REVIEW", "INVALID_BINARY"}
    for v in versions:
        if v["attributes"]["appStoreState"] in editable:
            return v
    if not required:
        return None
    die("no editable macOS version; create one in App Store Connect first (a released version is read-only — "
        "add a new version in App Store Connect to edit metadata or submit an update)")


def en_localization(asc, version_id):
    locs = asc.get(f"/appStoreVersions/{version_id}/appStoreVersionLocalizations")["data"]
    for loc in locs:
        if loc["attributes"]["locale"] == "en-US":
            return loc
    return asc.post("/appStoreVersionLocalizations", "appStoreVersionLocalizations",
                    {"locale": "en-US"}, {"appStoreVersion": ref("appStoreVersions", version_id)})


# ----------------------------------------------------------------------------- commands
def cmd_status(asc):
    app = find_app(asc)
    print(f"App: {app['attributes']['name']}  ({app['id']})")
    for v in asc.get(f"/apps/{app['id']}/appStoreVersions")["data"]:
        a = v["attributes"]
        print(f"  version {a['versionString']} [{a['platform']}] {a['appStoreState']}")
    print("Builds:")
    for b in asc.get("/builds", **{"filter[app]": app["id"], "sort": "-uploadedDate", "limit": 10})["data"]:
        a = b["attributes"]
        print(f"  {a['version']}  {a['processingState']}  uploaded {a['uploadedDate']}")
    v = editable_version(asc, app["id"], required=False)
    if v is None:
        print("No editable version (the released version is read-only; add a new version to ship an update).")
        return
    loc = en_localization(asc, v["id"])
    filled = [k for k in ("description", "keywords", "supportUrl", "promotionalText") if loc["attributes"].get(k)]
    print(f"Editable version {v['attributes']['versionString']}: filled {filled or 'nothing'}")
    sets = asc.get(f"/appStoreVersionLocalizations/{loc['id']}/appScreenshotSets")["data"]
    for s in sets:
        shots = asc.get(f"/appScreenshotSets/{s['id']}/appScreenshots")["data"]
        print(f"  screenshots {s['attributes']['screenshotDisplayType']}: {len(shots)}")
    build = asc.get(f"/appStoreVersions/{v['id']}/build")["data"]
    print(f"  build attached: {build['attributes']['version'] if build else 'none'}")


def cmd_metadata(asc):
    app = find_app(asc)
    v = editable_version(asc, app["id"])
    loc = en_localization(asc, v["id"])
    attrs = {k: val for k, val in LISTING.items() if val is not None}
    asc.patch(f"/appStoreVersionLocalizations/{loc['id']}", "appStoreVersionLocalizations", loc["id"], attrs)
    asc.patch(f"/appStoreVersions/{v['id']}", "appStoreVersions", v["id"], {"copyright": COPYRIGHT})
    print("✓ description, keywords, URLs, copyright")
    asc.patch(f"/apps/{app['id']}", "apps", app["id"], {"contentRightsDeclaration": "DOES_NOT_USE_THIRD_PARTY_CONTENT"})
    print("✓ content rights: no third-party content")

    # App-level info: subtitle + categories live on the appInfo, not the version.
    infos = asc.get(f"/apps/{app['id']}/appInfos")["data"]
    info = next((i for i in infos if i["attributes"]["appStoreState"] in
                 ("PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED")), infos[0])
    for il in asc.get(f"/appInfos/{info['id']}/appInfoLocalizations")["data"]:
        if il["attributes"]["locale"] == "en-US":
            asc.patch(f"/appInfoLocalizations/{il['id']}", "appInfoLocalizations", il["id"],
                      {"subtitle": SUBTITLE, "privacyPolicyUrl": PRIVACY_URL})
    asc.patch(f"/appInfos/{info['id']}", "appInfos", info["id"], relationships={
        "primaryCategory": ref("appCategories", PRIMARY_CATEGORY),
        "secondaryCategory": ref("appCategories", SECONDARY_CATEGORY),
    })
    print("✓ subtitle, categories")

    # Age rating: nothing objectionable → 4+.
    decl = asc.get(f"/appInfos/{info['id']}/ageRatingDeclaration")["data"]
    levels = ["alcoholTobaccoOrDrugUseOrReferences", "contests", "gamblingSimulated", "horrorOrFearThemes",
              "matureOrSuggestiveThemes", "medicalOrTreatmentInformation", "profanityOrCrudeHumor",
              "sexualContentGraphicAndNudity", "sexualContentOrNudity", "violenceCartoonOrFantasy",
              "violenceRealistic", "violenceRealisticProlongedGraphicOrSadistic", "gunsOrOtherWeapons"]
    flags = ["gambling", "unrestrictedWebAccess", "lootBox", "messagingAndChat", "userGeneratedContent",
             "advertising", "parentalControls", "ageAssurance", "healthOrWellnessTopics"]
    attrs = {**{k: "NONE" for k in levels}, **{k: False for k in flags}}
    asc.patch(f"/ageRatingDeclarations/{decl['id']}", "ageRatingDeclarations", decl["id"], attrs)
    print("✓ age rating (4+)")

    print("! App Privacy has no public API: App Store Connect → App Privacy → Get Started → "
          "\"No, we do not collect data\" → Publish")


def cmd_screenshots(asc, files):
    files = [Path(f) for f in files] or sorted(ROOT.glob("Marketing/screenshot-*.png"))
    app = find_app(asc)
    v = editable_version(asc, app["id"])
    loc = en_localization(asc, v["id"])
    sets = asc.get(f"/appStoreVersionLocalizations/{loc['id']}/appScreenshotSets")["data"]
    sset = next((s for s in sets if s["attributes"]["screenshotDisplayType"] == "APP_DESKTOP"), None)
    if sset:
        for old in asc.get(f"/appScreenshotSets/{sset['id']}/appScreenshots")["data"]:
            asc.call("DELETE", f"/appScreenshots/{old['id']}")
    else:
        sset = asc.post("/appScreenshotSets", "appScreenshotSets", {"screenshotDisplayType": "APP_DESKTOP"},
                        {"appStoreVersionLocalization": ref("appStoreVersionLocalizations", loc["id"])})
    for f in files:
        data = f.read_bytes()
        shot = asc.post("/appScreenshots", "appScreenshots", {"fileName": f.name, "fileSize": len(data)},
                        {"appScreenshotSet": ref("appScreenshotSets", sset["id"])})
        for op in shot["attributes"]["uploadOperations"]:
            chunk = data[op["offset"]: op["offset"] + op["length"]]
            headers = {h["name"]: h["value"] for h in op["requestHeaders"]}
            r = requests.request(op["method"], op["url"], headers=headers, data=chunk)
            r.raise_for_status()
        asc.patch(f"/appScreenshots/{shot['id']}", "appScreenshots", shot["id"],
                  {"uploaded": True, "sourceFileChecksum": hashlib.md5(data).hexdigest()})
        print(f"✓ uploaded {f.name}")
    # Wait for Apple to accept them.
    for _ in range(30):
        states = [s["attributes"]["assetDeliveryState"]["state"]
                  for s in asc.get(f"/appScreenshotSets/{sset['id']}/appScreenshots")["data"]]
        if all(s == "COMPLETE" for s in states):
            print("✓ screenshots processed")
            return
        if any(s == "FAILED" for s in states):
            die(f"screenshot processing failed: {states}")
        time.sleep(4)
    print("screenshots still processing; check later with `status`")


def cmd_build(asc, version=None, build_number=None):
    app = find_app(asc)
    v = editable_version(asc, app["id"])
    params = {"filter[app]": app["id"], "sort": "-uploadedDate", "filter[processingState]": "VALID"}
    if version:
        params["filter[preReleaseVersion.version]"] = version
    builds = asc.get("/builds", **params)["data"]
    if build_number:
        builds = [b for b in builds if b["attributes"]["version"] == str(build_number)]
    if not builds:
        pending = asc.get("/builds", **{"filter[app]": app["id"], "sort": "-uploadedDate", "limit": 3})["data"]
        states = [f"{b['attributes']['version']}:{b['attributes']['processingState']}" for b in pending]
        die(f"no processed build yet (recent: {states}). Try again in a few minutes.")
    build = builds[0]
    asc.patch(f"/appStoreVersions/{v['id']}", "appStoreVersions", v["id"],
              relationships={"build": ref("builds", build["id"])})
    print(f"✓ attached build {build['attributes']['version']} to {v['attributes']['versionString']}")


def cmd_price(asc):
    app = find_app(asc)
    points = asc.get(f"/apps/{app['id']}/appPricePoints", **{"filter[territory]": "USA", "limit": 5})["data"]
    free = next((p for p in points if float(p["attributes"]["customerPrice"]) == 0), None)
    if not free:
        die("could not find the free price point")
    body = {
        "data": {"type": "appPriceSchedules",
                 "relationships": {"app": {"data": ref("apps", app["id"])},
                                   "baseTerritory": {"data": ref("territories", "USA")},
                                   "manualPrices": {"data": [ref("appPrices", "${price-free}")]}}},
        "included": [{"type": "appPrices", "id": "${price-free}",
                      "attributes": {"startDate": None},
                      "relationships": {"appPricePoint": {"data": ref("appPricePoints", free["id"])}}}],
    }
    try:
        asc.call("POST", "/appPriceSchedules", json=body)
        print("✓ price: free")
    except RuntimeError as e:
        if "already" not in str(e).lower():
            raise
        print("✓ price already set")
    # Availability: every territory.
    territories = [ref("territories", t["id"]) for t in asc.all("/territories")]
    body = {"data": {"type": "appAvailabilities",
                     "attributes": {"availableInNewTerritories": True},
                     "relationships": {"app": {"data": ref("apps", app["id"])},
                                       "territoryAvailabilities": {"data": [ref("territoryAvailabilities", "${" + t["id"] + "}") for t in territories]}}},
            "included": [{"type": "territoryAvailabilities", "id": "${" + t["id"] + "}",
                          "attributes": {"available": True},
                          "relationships": {"territory": {"data": t}}} for t in territories]}
    asc.call("POST", "https://api.appstoreconnect.apple.com/v2/appAvailabilities", json=body)
    print(f"✓ available in {len(territories)} territories")


def cmd_review_info(asc):
    app = find_app(asc)
    v = editable_version(asc, app["id"])
    # Reuse the contact details from another of the account's apps when possible.
    contact = None
    for other in asc.get("/apps")["data"]:
        if other["id"] == app["id"]:
            continue
        for ov in asc.get(f"/apps/{other['id']}/appStoreVersions", limit=5)["data"]:
            try:
                d = asc.get(f"/appStoreVersions/{ov['id']}/appStoreReviewDetail")["data"]
            except RuntimeError:
                continue
            if d and d["attributes"].get("contactEmail"):
                contact = {k: d["attributes"][k] for k in ("contactFirstName", "contactLastName", "contactPhone", "contactEmail")}
                break
        if contact:
            break
    if not contact:
        die("no existing App Review contact info found; set REVIEW_PHONE and I'll use it")
    notes = (ROOT / "Marketing/review-notes.md").read_text() if (ROOT / "Marketing/review-notes.md").exists() \
        else "Diff tool. Choose any two text files or two folders to compare."
    attrs = {**contact, "demoAccountRequired": False, "notes": notes[:4000]}
    existing = asc.get(f"/appStoreVersions/{v['id']}/appStoreReviewDetail")["data"]
    if existing:
        asc.patch(f"/appStoreReviewDetails/{existing['id']}", "appStoreReviewDetails", existing["id"], attrs)
    else:
        asc.post("/appStoreReviewDetails", "appStoreReviewDetails", attrs, {"appStoreVersion": ref("appStoreVersions", v["id"])})
    print(f"✓ review contact: {contact['contactFirstName']} {contact['contactLastName']} <{contact['contactEmail']}>")


def cmd_submit(asc):
    app = find_app(asc)
    v = editable_version(asc, app["id"])
    open_subs = asc.get("/reviewSubmissions", **{"filter[app]": app["id"], "filter[state]": "READY_FOR_REVIEW,UNRESOLVED_ISSUES"})["data"]
    sub = open_subs[0] if open_subs else asc.post("/reviewSubmissions", "reviewSubmissions", {"platform": "MAC_OS"}, {"app": ref("apps", app["id"])})
    asc.post("/reviewSubmissionItems", "reviewSubmissionItems", relationships={
        "reviewSubmission": ref("reviewSubmissions", sub["id"]),
        "appStoreVersion": ref("appStoreVersions", v["id"]),
    })
    asc.patch(f"/reviewSubmissions/{sub['id']}", "reviewSubmissions", sub["id"], {"submitted": True})
    print(f"✓ submitted {v['attributes']['versionString']} for review")


def main():
    args = sys.argv[1:] or ["status"]
    asc = ASC()
    cmd, rest = args[0], args[1:]
    if cmd == "status":
        cmd_status(asc)
    elif cmd == "metadata":
        cmd_metadata(asc)
    elif cmd == "screenshots":
        cmd_screenshots(asc, rest)
    elif cmd == "build":
        cmd_build(asc, *rest)
    elif cmd == "price":
        cmd_price(asc)
    elif cmd == "review-info":
        cmd_review_info(asc)
    elif cmd == "submit":
        cmd_submit(asc)
    elif cmd == "all":
        cmd_metadata(asc)
        cmd_screenshots(asc, [])
        cmd_price(asc)
        cmd_review_info(asc)
        cmd_build(asc)
    else:
        die(__doc__)


if __name__ == "__main__":
    main()
