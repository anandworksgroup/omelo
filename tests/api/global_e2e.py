"""Release 6: global employment & mobility, as real users.

    python tests/api/global_e2e.py setup   # accounts, a Berlin employer with jobs in Germany + remote, three nurses
    -- then, as Omelo, verify the probe company and enable talent search (setup prints the SQL)
    python tests/api/global_e2e.py run

A nurse in India who is open to relocating to Germany, a nurse already in Germany with a work permit,
and a nurse in India who keeps her work authorization private. A German hospital with a sponsored
job, a job without sponsorship, a time-zone-bound remote job and a remote job open to India.

Checks: currency conversion with its provenance, the official country guide (not legal advice),
the worker's mobility profile, eligibility before applying ("potentially eligible — missing: …",
never a silent rejection), the six discovery tabs, what the employer may and may not see about a
worker's authorization, global talent search, matcher v1.2, and the global employment record that
keeps its original currency. Attacks R6-001 .. R6-012. Creates five probe.* accounts.
"""
import json, os, sys, time
from omelo_api import *

STATE = os.path.join(os.path.dirname(__file__), ".global_state.json")
PW = "ProbePass2026!"
FAIL = []
def check(label, ok, detail=""):
    print(f"  {'PASS' if ok else 'FAIL'} | {label}" + (f" | {detail}" if detail and not ok else ""))
    if not ok: FAIL.append(label)
def blocked(label, s, d):
    check(f"blocked: {label}", s >= 400 or (isinstance(d, list) and len(d) == 0), f"HTTP {s} {msg(d)}")
def prof(slug):
    return get(f"/rest/v1/professions?select=id&slug=eq.{slug}")[1][0]["id"]
def city(name, cc):
    return get(f"/rest/v1/locations?select=id,latitude,longitude&kind=eq.city&name=eq.{name}&country_code=eq.{cc}")[1][0]
def texts(e):
    return " ".join(m.get("text", "") for m in (e or {}).get("missing", []))


def setup():
    stamp = str(int(time.time()))
    acc = {}
    for key, name, role in [("emp", "Greta Hospital", "employer"), ("w1", "Anita Nurse", "worker"),
                            ("w2", "Jonas Nurse", "worker"), ("w3", "Priya Nurse", "worker"),
                            ("x", "Rogue Outsider", "employer")]:
        email = f"probe.g{key}.{stamp}@omelo.dev"
        _, pid = signup(email, PW, name, role)
        acc[key] = {"email": email, "id": pid}
    tok = {k: login(v["email"], PW)[0] for k, v in acc.items()}
    nurse = prof("nurse")
    berlin, munich = city("Berlin", "DE"), city("Munich", "DE")
    for k, vis in [("w1", "recruiters"), ("w2", "discoverable"), ("w3", "recruiters")]:
        s, wid = rpc("omelo_create_work_identity", {"p_label": "Registered Nurse", "p_profession_id": nurse}, tok[k])
        check(f"{k} creates a nurse identity", s == 200, f"{s} {msg(wid)}")
        patch(f"/rest/v1/work_identities?id=eq.{wid}", {"discoverability": vis}, tok[k])
        acc[k]["identity"] = wid
    # where the workers live
    patch(f"/rest/v1/persons?id=eq.{acc['w1']['id']}", {"country_code": "IN", "timezone": "Asia/Kolkata"}, tok["w1"])
    patch(f"/rest/v1/persons?id=eq.{acc['w2']['id']}", {"country_code": "DE", "timezone": "Europe/Berlin"}, tok["w2"])
    patch(f"/rest/v1/persons?id=eq.{acc['w3']['id']}", {"country_code": "IN", "timezone": "Asia/Kolkata"}, tok["w3"])

    s, slug = rpc("omelo_company_slug", {"p_name": f"Klinikum Probe {stamp}"}, tok["emp"])
    s, co = post("/rest/v1/companies", {"slug": slug, "display_name": f"Klinikum Probe {stamp}", "country_code": "DE",
                 "size_band": "201-500", "created_by": acc["emp"]["id"]}, tok["emp"])
    if s != 201: raise SystemExit(f"company: {s} {msg(co)}")
    company = co[0]["id"]
    s, le = post("/rest/v1/company_legal_entities", {"company_id": company, "country_code": "DE", "legal_name": "Klinikum Probe GmbH",
                 "currency": "EUR", "timezone": "Europe/Berlin", "is_default": True}, tok["emp"])
    check("the employer registers its German legal entity", s == 201, f"{s} {msg(le)}")
    legal = le[0]["id"] if s == 201 else None

    def job(title, loc, extra):
        body = {"company_id": company, "created_by": acc["emp"]["id"], "title": title, "profession_id": nurse,
                "work_type": "full_time", "pay_min": 3600, "pay_max": 3800, "pay_period": "month", "pay_currency": "EUR",
                "country_code": "DE", "status": "draft", "legal_entity_id": legal}
        if loc: body["location_id"] = loc
        body.update(extra)
        s, j = post("/rest/v1/jobs", body, tok["emp"])
        check(f"job created: {title}", s == 201, f"{s} {msg(j)}")
        jid = j[0]["id"]
        post("/rest/v1/job_stages", [{"job_id": jid, "name": "New", "position": 1, "maps_to_state": "applied", "is_terminal": False}], tok["emp"])
        return jid
    j1 = job("Registered Nurse (visa sponsored)", berlin["id"], {"workplace_type": "onsite", "sponsorship": "yes",
             "sponsorship_type": "EU Blue Card", "immigration_support": True, "relocation_support": True,
             "accommodation_assistance": True, "location_text": "Berlin"})
    j2 = job("Nurse (EU work permit required)", munich["id"], {"workplace_type": "onsite", "sponsorship": "no",
             "location_text": "Munich"})
    j3 = job("Remote Nurse Triage (CET team)", None, {"workplace_type": "remote", "remote_scope": "timezone",
             "remote_tz_min_offset": 0, "remote_tz_max_offset": 180})
    j4 = job("Remote Care Coordinator (India)", None, {"workplace_type": "remote", "remote_scope": "countries",
             "remote_countries": ["IN"], "pay_min": 90000, "pay_max": 110000, "pay_currency": "INR"})
    s, d = post("/rest/v1/job_languages", {"job_id": j1, "language_code": "deu", "min_proficiency": "professional",
                "requirement_level": "required"}, tok["emp"])
    check("the sponsored job needs professional German", s == 201, f"{s} {msg(d)}")
    for jid in (j1, j2, j3, j4):
        s, d = patch(f"/rest/v1/jobs?id=eq.{jid}", {"status": "published"}, tok["emp"])
        check("job published", s == 200 and d, f"{s} {msg(d)}")
    st = dict(acc=acc, company=company, legal=legal, jobs=[j1, j2, j3, j4], berlin=berlin)
    json.dump(st, open(STATE, "w"))
    print(f"\nNow run as Omelo (fixture: verify probe company {company}):\n")
    print(f"  update companies set is_verified = true, verified_at = now(), verification_method = 'manual_admin' where id = '{company}';")
    print(f"  update company_entitlements set talent_search_enabled = true where company_id = '{company}';")
    print("\nthen: python tests/api/global_e2e.py run")
    print(f"\n{'SETUP OK' if not FAIL else str(len(FAIL)) + ' FAILED: ' + '; '.join(FAIL)}")


def run():
    st = json.load(open(STATE)); acc = st["acc"]
    tok = {k: login(v["email"], PW)[0] for k, v in acc.items()}
    j1, j2, j3, j4 = st["jobs"]; company = st["company"]
    W = {k: acc[k]["identity"] for k in ("w1", "w2", "w3")}

    print("\n1. CURRENCY (R6-001, R6-002, R6-011)")
    s, c = rpc("omelo_convert_currency", {"p_amount": 3800, "p_from": "EUR", "p_to": "INR"})
    check("anyone converts EUR -> INR and sees rate, effective time and source",
          s == 200 and c.get("converted") and c.get("rate") and c.get("effective_at") and c.get("source"), c)
    s, d = rpc("omelo_convert_currency", {"p_amount": 1, "p_from": "EUR", "p_to": "XXX"}); blocked("an unknown currency", s, d)
    s, n = rpc("omelo_normalized_pay", {"p_amount": 25, "p_period": "hour", "p_currency": "EUR", "p_target": "INR"})
    check("normalised pay: hourly / monthly / yearly, original and target currency",
          s == 200 and n.get("currency") == "EUR" and n.get("monthly") and (n.get("target") or {}).get("currency") == "INR", n)
    s, d = post("/rest/v1/exchange_rates", {"base": "USD", "quote": "INR", "rate": 1, "effective_at": "2026-09-19T00:00:00Z",
                "source": "rogue"}, tok["x"]); blocked("a user inserts an exchange rate", s, d)
    s, d = patch("/rest/v1/exchange_rates?base=eq.USD&quote=eq.INR", {"rate": 1}, tok["x"]); blocked("a user rewrites a rate", s, d)
    s, d = rpc("omelo_admin_add_exchange_rate", {"p_base": "USD", "p_quote": "INR", "p_rate": 1,
               "p_effective_at": "2026-09-19T00:00:00Z", "p_source": "rogue"}, tok["x"]); blocked("a non-admin adds a rate", s, d)
    s, d = post("/rest/v1/currencies", {"code": "ZZZ", "name": "Fake", "symbol": "z"}, tok["x"]); blocked("a user invents a currency", s, d)
    s, d = patch(f"/rest/v1/jobs?id=eq.{j2}", {"pay_currency": "ZZZ"}, tok["emp"]); blocked("R6-001 a job paid in an unknown currency", s, d)

    print("\n2. COUNTRY GUIDE (official sources, not legal advice)")
    s, g = rpc("omelo_country_guide", {"p_country": "DE"})
    info = g.get("information", []) if s == 200 and g else []
    check("signed out, the Germany guide lists official https sources with review dates",
          len(info) >= 2 and all(i["url"].startswith("https://") and i["reviewed_at"] for i in info), g)
    check("the guide says it is not legal advice", "Not legal" in (g or {}).get("disclaimer", ""), g)
    check("the guide shows nursing recognition as a requirement in Germany",
          any("nurse" in (l.get("name", "") + l.get("profession", "")).lower() for l in (g or {}).get("licence_requirements", [])), g)
    s, lr = rpc("omelo_license_requirements", {"p_profession": prof("nurse")})
    check("licensing by country for a profession (DE, CA, GB)", s == 200 and {x["country"] for x in lr} >= {"DE", "CA", "GB"}, lr)
    s, d = post("/rest/v1/country_employment_info", {"country_code": "DE", "topic": "hiring", "title": "x", "summary": "x",
                "official_url": "https://evil.example", "source_name": "x", "reviewed_at": "2026-01-01"}, tok["x"])
    blocked("R6-009 a user adds 'official' guidance", s, d)
    s, d = patch("/rest/v1/country_policies?country_code=eq.DE", {"default_currency": "USD"}, tok["x"]); blocked("a user edits a country", s, d)

    print("\n3. MOBILITY PROFILES (R6-007)")
    s, m = rpc("omelo_save_mobility", {"p": {"current_country": "IN", "citizenships": ["IN"], "timezone": "Asia/Kolkata",
               "open_to_relocation": True, "preferred_countries": ["DE", "IE"], "relocation_assistance_required": True,
               "earliest_relocation_date": "2026-11-01", "remote_preference": "any"}}, tok["w1"])
    check("worker 1 (India) is open to relocating to Germany or Ireland", s == 200 and m.get("authorization_visibility") == "eligibility_only", f"{s} {msg(m)}")
    s, m = rpc("omelo_save_mobility", {"p": {"current_country": "DE", "citizenships": ["PL"], "timezone": "Europe/Berlin",
               "authorization_visibility": "details_with_applications"}}, tok["w2"])
    check("worker 2 (in Germany) shares authorization details with jobs she applies to", s == 200, f"{s} {msg(m)}")
    s, m = rpc("omelo_save_mobility", {"p": {"current_country": "IN", "citizenships": ["IN"], "timezone": "Asia/Kolkata",
               "open_to_relocation": False, "authorization_visibility": "private"}}, tok["w3"])
    check("worker 3 keeps her authorization private", s == 200, f"{s} {msg(m)}")
    s, d = rpc("omelo_save_mobility", {"p": {"current_country": "ZZ"}}, tok["w1"]); blocked("an unknown country", s, d)
    s, d = rpc("omelo_save_mobility", {"p": {"timezone": "Mars/Olympus"}}, tok["w1"]); blocked("an unknown time zone", s, d)
    s, d = rpc("omelo_save_mobility", {"p": {"authorization_visibility": "everyone"}}, tok["w1"]); blocked("an unknown visibility", s, d)
    s, d = get(f"/rest/v1/mobility_profiles?select=*&person_id=eq.{acc['w1']['id']}", tok["emp"]); blocked("an employer reads a mobility profile", s, d)
    s, d = get(f"/rest/v1/mobility_profiles?select=*&person_id=eq.{acc['w1']['id']}", tok["w2"]); blocked("another worker reads it", s, d)
    s, d = post("/rest/v1/mobility_profiles", {"person_id": acc["w1"]["id"], "open_to_relocation": False}, tok["w2"])
    blocked("another worker writes it", s, d)
    s, mm = rpc("omelo_my_mobility", {}, tok["w1"])
    check("the worker reads her own mobility profile", s == 200 and mm["mobility"]["preferred_countries"] == ["DE", "IE"], mm)

    # authorization records
    s, d = post("/rest/v1/work_authorizations", {"person_id": acc["w2"]["id"], "country_code": "DE", "status": "work_permit",
                "valid_from": "2025-01-01", "expires_on": "2029-01-31", "work_restrictions": "Healthcare only"}, tok["w2"])
    check("worker 2 records her German work permit", s == 201, f"{s} {msg(d)}")
    s, d = post("/rest/v1/work_authorizations", {"person_id": acc["w2"]["id"], "country_code": "DE", "status": "work_permit",
                "valid_from": "2027-01-01", "expires_on": "2026-01-01"}, tok["w2"]); blocked("an authorization that ends before it starts", s, d)
    s, d = post("/rest/v1/work_authorizations", {"person_id": acc["w2"]["id"], "country_code": "DE", "status": "work_permit",
                "is_verified": True}, tok["w2"]); blocked("a worker marks her own authorization verified", s, d)
    s, d = post("/rest/v1/work_authorizations", {"person_id": acc["w3"]["id"], "country_code": "DE", "status": "requires_sponsorship"}, tok["w3"])
    check("worker 3 records that she needs sponsorship for Germany", s == 201, f"{s} {msg(d)}")
    s, d = post("/rest/v1/person_licenses", {"person_id": acc["w2"]["id"], "name": "Pflegefachfrau (recognised)", "country_code": "DE",
                "issuing_body": "Landesamt"}, tok["w2"])
    check("worker 2 lists her German nursing recognition", s == 201, f"{s} {msg(d)}")
    s, d = post("/rest/v1/person_languages", {"person_id": acc["w2"]["id"], "language_code": "deu", "proficiency": "fluent"}, tok["w2"])
    check("worker 2 speaks German", s == 201, f"{s} {msg(d)}")
    s, d = post("/rest/v1/person_languages", {"person_id": acc["w1"]["id"], "language_code": "deu", "proficiency": "basic"}, tok["w1"])
    check("worker 1 is learning German", s == 201, f"{s} {msg(d)}")

    print("\n4. ELIGIBILITY BEFORE APPLYING (R6-004: explained, never a silent rejection)")
    s, e11 = rpc("omelo_job_eligibility", {"p_job": j1}, tok["w1"])
    check("worker 1 on the sponsored job: potentially eligible", s == 200 and e11.get("status") == "potentially_eligible", e11)
    check("…missing: work authorization (employer sponsors), recognition, professional German",
          "sponsors" in texts(e11) and "Recognition" in texts(e11) and "German" in texts(e11), texts(e11))
    check("…with the official sources and the licence requirement for Germany",
          len(e11.get("official_sources", [])) >= 2 and e11.get("licence_requirements"), e11)
    check("…and the pay in her currency, with the rate's source",
          ((e11.get("pay") or {}).get("target") or {}).get("currency") == "INR" and (e11["pay"]["target"]).get("source"), e11.get("pay"))
    s, e12 = rpc("omelo_job_eligibility", {"p_job": j2}, tok["w1"])
    check("worker 1 on the no-sponsorship job: not currently eligible, and told why",
          s == 200 and e12.get("status") == "not_eligible" and "does not offer sponsorship" in texts(e12), e12)
    s, e21 = rpc("omelo_job_eligibility", {"p_job": j1}, tok["w2"])
    check("worker 2 (permit + recognition + German) is eligible", s == 200 and e21.get("status") == "eligible", e21)
    check("…and her own view shows the permit's restriction", any("Healthcare only" in n for n in e21.get("notes", [])), e21.get("notes"))
    s, e13 = rpc("omelo_job_eligibility", {"p_job": j3}, tok["w1"])
    check("remote CET team: India's time zone is outside the range -> potentially eligible, explained",
          s == 200 and e13.get("status") == "potentially_eligible" and "time zone" in texts(e13), e13)
    s, e23 = rpc("omelo_job_eligibility", {"p_job": j3}, tok["w2"])
    check("remote CET team: Berlin is inside the range", s == 200 and e23.get("status") == "eligible", e23)
    s, e14 = rpc("omelo_job_eligibility", {"p_job": j4}, tok["w1"])
    check("remote job open to India: eligible from India", s == 200 and e14.get("status") == "eligible", e14)
    s, e24 = rpc("omelo_job_eligibility", {"p_job": j4}, tok["w2"])
    check("remote job open to India: not from Germany (hard location rule)", s == 200 and e24.get("status") == "not_eligible", e24)
    s, d = rpc("omelo_job_eligibility", {"p_job": j1, "p_identity": W["w2"]}, tok["w1"]); blocked("checking someone else's identity", s, d)
    s, d = rpc("omelo_job_eligibility", {"p_job": j1}); blocked("signed out", s, d)

    print("\n5. GLOBAL DISCOVERY TABS")
    def tab(t, k="w1", f=None):
        s, r = rpc("omelo_global_jobs", {"p_tab": t, "p_filters": f or {}}, tok[k])
        return s, r, {x["job_id"] for x in (r or {}).get("results", [])} if s == 200 else set()
    s, r, ids = tab("visa_sponsorship"); check("visa sponsorship: the sponsored job, not the other", j1 in ids and j2 not in ids, f"{s} {msg(r)}")
    s, r, ids = tab("international"); check("international (from India): both German jobs", {j1, j2} <= ids, f"{s} {msg(r)}")
    s, r, ids = tab("work_abroad"); check("work abroad: sponsored German job in a preferred country", j1 in ids and j2 not in ids, f"{s} {msg(r)}")
    s, r, ids = tab("relocation"); check("relocation support", j1 in ids and j2 not in ids, f"{s} {msg(r)}")
    s, r, ids = tab("remote"); check("remote from India: the India-open job, not the CET team", j4 in ids and j3 not in ids, f"{s} {msg(r)}")
    s, r, ids = tab("remote", "w2"); check("remote from Berlin: the CET team, not the India-only job", j3 in ids and j4 not in ids, f"{s} {msg(r)}")
    b = st["berlin"]
    s, r, ids = tab("near_me", "w2", {"lat": b["latitude"], "lng": b["longitude"], "radius_km": 30})
    check("near me (Berlin, 30 km): the Berlin job, not Munich", j1 in ids and j2 not in ids, f"{s} {msg(r)}")
    s, r, ids = tab("international", "w1", {"country": "DE", "query": "sponsored"})
    card = next((x for x in r.get("results", []) if x["job_id"] == j1), {}) if s == 200 else {}
    check("each card: sponsorship, support, pay in EUR and in INR, eligibility for me",
          card.get("sponsorship") == "yes" and card["support"]["immigration"] and card["pay"]["currency"] == "EUR"
          and card["pay"]["normalized"]["target"]["currency"] == "INR" and card["eligibility"]["status"] == "potentially_eligible", card)
    s, d = rpc("omelo_global_jobs", {"p_tab": "everything"}, tok["w1"]); blocked("an unknown tab", s, d)
    s, d = rpc("omelo_global_jobs", {"p_tab": "remote"}); blocked("signed out", s, d)

    print("\n6. WHAT THE EMPLOYER SEES (R6-005, R6-006)")
    s, d = get(f"/rest/v1/work_authorizations?select=*&person_id=eq.{acc['w3']['id']}", tok["emp"]); blocked("R6-005 employer reads a private authorization", s, d)
    s, d = get(f"/rest/v1/work_authorizations?select=*&person_id=eq.{acc['w2']['id']}", tok["emp"])
    blocked("employer reads worker 2's permit before she applies", s, d)
    s, app = post("/rest/v1/applications", {"job_id": j1, "person_id": acc["w2"]["id"], "company_id": company,
                  "work_identity_id": W["w2"], "identity_snapshot": {}}, tok["w2"])
    check("worker 2 applies to the sponsored job", s == 201, f"{s} {msg(app)}")
    app_id = app[0]["id"] if s == 201 else None
    s, d = get(f"/rest/v1/work_authorizations?select=country_code,status,expires_on&person_id=eq.{acc['w2']['id']}", tok["emp"])
    check("after applying, her chosen visibility lets the employer read the permit", s == 200 and len(d) == 1, f"{s} {d}")
    s, d = get(f"/rest/v1/work_authorizations?select=*&person_id=eq.{acc['w2']['id']}", tok["x"]); blocked("an outsider reads it", s, d)
    s, ce = rpc("omelo_candidate_eligibility", {"p_job": j1, "p_identity": W["w2"]}, tok["emp"])
    check("candidate eligibility for the applicant: eligible, with the details she shares",
          s == 200 and ce.get("status") == "eligible" and ce.get("authorizations"), ce)
    s, ce3 = rpc("omelo_candidate_eligibility", {"p_job": j2, "p_identity": W["w3"]}, tok["emp"])
    check("a private worker: 'not shared', never 'not eligible', and no details",
          s == 200 and ce3.get("status") == "potentially_eligible" and "not shared" in texts(ce3) and not ce3.get("authorizations"), ce3)
    s, ce1 = rpc("omelo_candidate_eligibility", {"p_job": j1, "p_identity": W["w1"]}, tok["emp"])
    check("eligibility-only worker: the result without authorization records",
          s == 200 and ce1.get("status") == "potentially_eligible" and ce1.get("authorizations") is None, ce1)
    s, d = rpc("omelo_candidate_eligibility", {"p_job": j1, "p_identity": W["w1"]}, tok["x"]); blocked("an outsider checks a candidate", s, d)
    s, d = rpc("omelo_candidate_eligibility", {"p_job": j1, "p_identity": W["w1"]}, tok["w2"]); blocked("a worker checks another worker", s, d)
    s, d = get(f"/rest/v1/documents?select=id&person_id=eq.{acc['w2']['id']}", tok["emp"]); blocked("R6-006 documents without an explicit share", s, d)

    print("\n7. GLOBAL TALENT SEARCH")
    s, r = rpc("omelo_search_talent", {"p_job_id": j1, "p_radius_km": 25}, tok["emp"])
    found = {x["work_identity_id"] if "work_identity_id" in x else x.get("identity_id"): x for x in (r or {}).get("results", [])} if s == 200 else {}
    if s == 200 and not found:
        found = {x.get("id"): x for x in r.get("results", [])}
    w1card = found.get(W["w1"], {})
    check("a relocating nurse in India is found for a Berlin job despite a 25 km radius", bool(w1card), f"{s} {msg(r)}")
    check("…her card shows 'potentially eligible' and what is missing, no dates or visa types",
          (w1card.get("eligibility") or {}).get("status") == "potentially_eligible"
          and "expires" not in json.dumps(w1card.get("eligibility")) and w1card.get("open_to_relocation") is True, w1card.get("eligibility"))
    check("a nurse in India not open to relocation is not in a Berlin search", W["w3"] not in found, list(found))
    s, r = rpc("omelo_search_talent", {"p_job_id": j1, "p_radius_km": 25, "p_filters": {"eligibility": "eligible"}}, tok["emp"])
    ids = {x.get("work_identity_id") or x.get("identity_id") or x.get("id") for x in (r or {}).get("results", [])}
    check("filter 'eligible now' leaves out the potentially eligible", s == 200 and W["w1"] not in ids, f"{s} {msg(r)}")
    s, r = rpc("omelo_search_talent", {"p_job_id": j1, "p_radius_km": 25, "p_filters": {"open_to_relocation": True, "language": "deu",
               "current_country": "IN"}}, tok["emp"])
    ids = {x.get("work_identity_id") or x.get("identity_id") or x.get("id") for x in (r or {}).get("results", [])}
    check("filters: open to relocation + speaks German + lives in India", s == 200 and W["w1"] in ids, f"{s} {msg(r)}")
    s, d = rpc("omelo_search_talent", {"p_job_id": j1, "p_filters": {"eligibility": "maybe"}}, tok["emp"]); blocked("an unknown filter value", s, d)
    s, d = rpc("omelo_search_talent", {"p_job_id": j1, "p_filters": {"work_auth_country": "DE"}}, tok["x"]); blocked("an outsider searches", s, d)

    print("\n8. MATCHER v1.2")
    s, m1 = rpc("omelo_my_match", {"p_job_id": j1}, tok["w1"])
    check("worker 1 / sponsored job: v1.2, passes the gate, eligibility 'potentially eligible'",
          s == 200 and m1.get("engine_version") == "v1.2" and m1.get("eligible") is True
          and (m1.get("eligibility") or {}).get("status") == "potentially_eligible", {k: m1.get(k) for k in ("engine_version", "eligible", "gate_failures")} if s == 200 else m1)
    check("…mobility counts: open to relocating to Germany", (m1.get("factors", {}).get("mobility_fit") or {}).get("status") == "strong", m1.get("factors", {}).get("mobility_fit"))
    check("…eligibility explained in the gaps", any(g["factor"] == "eligibility_fit" for g in m1.get("gaps", [])), m1.get("gaps"))
    s, m2 = rpc("omelo_my_match", {"p_job_id": j2}, tok["w1"])
    check("worker 1 / no-sponsorship job: the only hard blocker fails the gate", s == 200 and m2.get("eligible") is False
          and "work_authorization" in m2.get("gate_failures", []), m2.get("gate_failures") if s == 200 else m2)
    s, m3 = rpc("omelo_my_match", {"p_job_id": j3}, tok["w1"])
    check("worker 1 / CET remote job: time-zone distance scored, not rejected",
          s == 200 and m3.get("eligible") is True and (m3.get("factors", {}).get("mobility_fit") or {}).get("status") in ("partial", "gap"), m3.get("factors", {}).get("mobility_fit") if s == 200 else m3)

    print("\n9. GLOBAL EMPLOYMENT RECORD (R6-012)")
    s, d = rpc("omelo_move_application", {"p_application_id": app_id, "p_state": "shortlisted"}, tok["emp"])
    start = (time.strftime("%Y-%m-%d", time.gmtime(time.time() + 30 * 86400)))
    s, oid = rpc("omelo_send_offer", {"p_application_id": app_id, "p_pay_amount": 3900, "p_pay_period": "month",
                 "p_start_date": start}, tok["emp"])
    check("the employer offers EUR 3,900 a month", s == 200, f"{s} {msg(oid)}")
    s, res = rpc("omelo_respond_to_offer", {"p_offer_id": oid, "p_accept": True}, tok["w2"])
    check("worker 2 accepts", s == 200 and res.get("employment_id"), f"{s} {msg(res)}")
    emp_id = (res or {}).get("employment_id") if s == 200 else None
    s, e = get(f"/rest/v1/employments?select=country_code,pay_amount,pay_period,pay_currency&id=eq.{emp_id}", tok["w2"])
    check("the employment keeps country DE and EUR 3,900 a month", s == 200 and e and e[0]["country_code"] == "DE"
          and e[0]["pay_currency"] == "EUR" and float(e[0]["pay_amount"]) == 3900, e)
    s, x = get(f"/rest/v1/experiences?select=country_code,pay_currency,is_verified&verified_employment_id=eq.{emp_id}", tok["w2"])
    check("the verified experience carries the country and original currency", s == 200 and x and x[0]["country_code"] == "DE"
          and x[0]["pay_currency"] == "EUR" and x[0]["is_verified"], x)
    s, d = patch(f"/rest/v1/employments?id=eq.{emp_id}", {"pay_currency": "INR"}, tok["emp"]); blocked("R6-012 the employer changes the pay currency", s, d)
    s, d = patch(f"/rest/v1/employments?id=eq.{emp_id}", {"pay_amount": 100}, tok["emp"]); blocked("the employer rewrites the pay", s, d)
    s, d = patch(f"/rest/v1/employments?id=eq.{emp_id}", {"country_code": "IN"}, tok["emp"]); blocked("the employer moves the employment", s, d)

    print("\n10. MULTI-COUNTRY EMPLOYER AND JOB RULES (R6-003, R6-010)")
    s, d = post("/rest/v1/company_legal_entities", {"company_id": company, "country_code": "IE", "legal_name": "Klinikum Probe Ireland Ltd",
                "currency": "EUR", "timezone": "Europe/Dublin"}, tok["emp"])
    check("the employer adds an Irish entity", s == 201, f"{s} {msg(d)}")
    s, d = post("/rest/v1/company_legal_entities", {"company_id": company, "country_code": "IE", "legal_name": "Hijack Ltd",
                "currency": "EUR", "timezone": "Europe/Dublin"}, tok["x"]); blocked("an outsider adds an entity to the company", s, d)
    s, d = post("/rest/v1/company_legal_entities", {"company_id": company, "country_code": "XX", "legal_name": "Nowhere Ltd",
                "currency": "EUR", "timezone": "Europe/Dublin"}, tok["emp"]); blocked("R6-003 an entity in an unknown country", s, d)
    s, d = post("/rest/v1/company_legal_entities", {"company_id": company, "country_code": "IE", "legal_name": "Bad TZ Ltd",
                "currency": "EUR", "timezone": "Europe/Atlantis"}, tok["emp"]); blocked("an entity in an unknown time zone", s, d)
    s, d = get(f"/rest/v1/company_legal_entities?select=id&company_id=eq.{company}", tok["x"]); blocked("an outsider lists the entities", s, d)
    s, d = patch(f"/rest/v1/jobs?id=eq.{j3}", {"remote_tz_min_offset": 200}, tok["emp"]); blocked("R6-010 an inverted time-zone range", s, d)
    s, d = patch(f"/rest/v1/jobs?id=eq.{j4}", {"remote_countries": ["QQ"]}, tok["emp"]); blocked("a remote job open to an unknown country", s, d)
    s, d = patch(f"/rest/v1/jobs?id=eq.{j2}", {"sponsorship": "case_by_case"}, tok["emp"])
    s, v = get(f"/rest/v1/jobs?select=sponsorship,visa_sponsorship&id=eq.{j2}", tok["emp"])
    check("sponsorship 'case by case' keeps the matcher's flag in step", v and v[0]["visa_sponsorship"] is True, v)
    s, e12b = rpc("omelo_job_eligibility", {"p_job": j2}, tok["w1"])
    check("…and worker 1 becomes potentially eligible for it (case by case)", e12b.get("status") == "potentially_eligible", e12b)

    print(f"\n{'ALL PASSED' if not FAIL else str(len(FAIL)) + ' FAILED: ' + '; '.join(FAIL)}")
    sys.exit(1 if FAIL else 0)


if __name__ == "__main__":
    {"setup": setup, "run": run}.get(sys.argv[1] if len(sys.argv) > 1 else "", lambda: print(__doc__))()
