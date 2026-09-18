"""Release 2: Universal Professional Identity, as real users.

    python tests/api/identity_e2e.py

Creates three probe.* accounts. Clean up as described in hiring_loop_e2e.py.
"""
import sys, time
from omelo_api import *

FAIL = []
def check(label, ok, detail=""):
    print(f"  {'PASS' if ok else 'FAIL'} | {label}" + (f" | {detail}" if detail and not ok else ""))
    if not ok: FAIL.append(label)

def blocked(label, s, d):
    check(f"blocked: {label}", s >= 400 or (isinstance(d, list) and len(d) == 0), f"HTTP {s} {msg(d)}")

stamp = str(int(time.time()))
PW = "ProbePass2026!"
wrk_tok, wrk_id = signup(f"probe.wrk.{stamp}@omelo.dev", PW, "Asha Multi", "worker")
emp_tok, emp_id = signup(f"probe.emp.{stamp}@omelo.dev", PW, "Kitchen Owner", "employer")
out_tok, out_id = signup(f"probe.out.{stamp}@omelo.dev", PW, "Outsider", "worker")

def prof(slug):
    return get(f"/rest/v1/professions?select=id&slug=eq.{slug}")[1][0]["id"]
def skill(slug_like):
    return get(f"/rest/v1/skills?select=id,name&name=ilike.*{slug_like}*&limit=1")[1][0]

print("\n1. MULTIPLE IDENTITIES")
s, primary = get(f"/rest/v1/work_identities?select=id,label,is_primary&person_id=eq.{wrk_id}", wrk_tok)
primary_id = primary[0]["id"]
s, cook = rpc("omelo_create_work_identity", {"p_label": "Cook", "p_profession_id": prof("cook")}, wrk_tok)
check("create a Cook identity", s == 200 and isinstance(cook, str), f"{s} {msg(cook)}")
s, eng = rpc("omelo_create_work_identity", {"p_label": "Software Engineer", "p_profession_id": prof("software-engineer")}, wrk_tok)
check("create a Software Engineer identity", s == 200, f"{s} {msg(eng)}")
s, d = rpc("omelo_create_work_identity", {"p_label": "cook"}, wrk_tok); blocked("a duplicate identity name", s, d)
s, drv = rpc("omelo_create_work_identity", {"p_label": "Delivery Driver", "p_profession_id": prof("delivery-executive")}, wrk_tok)
s, ele = rpc("omelo_create_work_identity", {"p_label": "Electrician", "p_profession_id": prof("electrician")}, wrk_tok)
check("up to five identities", s == 200, f"{s} {msg(ele)}")
s, d = rpc("omelo_create_work_identity", {"p_label": "Nurse", "p_profession_id": prof("nurse")}, wrk_tok); blocked("a sixth identity", s, d)
s, d = rpc("omelo_identity_profile", {"p_identity": cook}, out_tok); blocked("someone else reads my identity profile", s, d)

print("\n2. PER-IDENTITY SKILLS AND ADAPTIVE ANSWERS")
knife = skill("knife"); py = skill("python"); comm = skill("communication")
s, d = post("/rest/v1/person_skills", [
    {"person_id": wrk_id, "work_identity_id": cook, "skill_id": knife["id"], "proficiency": "advanced", "months_used": 30},
    {"person_id": wrk_id, "work_identity_id": cook, "skill_id": comm["id"], "proficiency": "intermediate", "months_used": None},
    {"person_id": wrk_id, "work_identity_id": eng, "skill_id": py["id"], "proficiency": "expert", "months_used": 60},
    {"person_id": wrk_id, "work_identity_id": eng, "skill_id": comm["id"], "proficiency": "advanced", "months_used": None}], wrk_tok)
check("the same skill can live on two identities", s == 201 and len(d) == 4, f"{s} {msg(d)}")
s, p = rpc("omelo_identity_profile", {"p_identity": cook}, wrk_tok)
slugs = {f["slug"] for f in p["fields"]} if s == 200 else set()
check("Cook profile asks kitchen questions (cuisines) and universal ones", "cuisines" in slugs and "has-smartphone" in slugs, sorted(slugs))
check("Cook profile does not ask engineering questions", "primary-stack" not in slugs and "seniority" not in slugs, sorted(slugs))
s, e = rpc("omelo_identity_profile", {"p_identity": eng}, wrk_tok)
check("Engineer profile asks technology questions", s == 200 and {"primary-stack", "seniority"} <= {f["slug"] for f in e["fields"]}, e)
before = p["completeness"]["score"]
s, r = rpc("omelo_save_identity_profile", {"p_identity": cook, "p_values": {
    "cuisines": ["North Indian", "Chinese"][:1] if False else ["North Indian"],
    "food-safety-cert": True, "has-smartphone": True, "primary-stack": ["Python"],
    "service-style": ["Not an option"]}}, wrk_tok)
check("valid answers save", s == 200 and r["saved"] >= 2, f"{s} {r}")
check("an engineering question on the Cook identity is refused per field", s == 200 and "primary-stack" in r["errors"], r)
check("an invalid option is refused per field", s == 200 and "service-style" in r["errors"], r)
cuisines_opts = next((f["options"] for f in p["fields"] if f["slug"] == "cuisines"), [])
if "North Indian" not in cuisines_opts:
    rpc("omelo_save_identity_profile", {"p_identity": cook, "p_values": {"cuisines": cuisines_opts[:1]}}, wrk_tok)
s, attrs = get(f"/rest/v1/person_attributes?select=work_identity_id,profile_attributes(slug)&person_id=eq.{wrk_id}", wrk_tok)
shared = {a["work_identity_id"] for a in attrs if a["profile_attributes"]["slug"] == "has-smartphone"}
check("universal answers are written to every identity", {cook, eng, primary_id, drv, ele} <= shared, attrs)
s, d = post("/rest/v1/person_attributes", {"person_id": wrk_id, "work_identity_id": eng,
            "attribute_id": get("/rest/v1/profile_attributes?select=id&slug=eq.seniority")[1][0]["id"], "value_text": "Wizard"}, wrk_tok)
blocked("a direct insert with an invalid option", s, d)
s, d = patch(f"/rest/v1/work_identities?id=eq.{cook}", {"completeness_score": 100, "headline": "Tandoor cook, 3 years"}, wrk_tok)
check("completeness cannot be set by the client (edit still saves)", s == 200 and d and d[0]["completeness_score"] != 100 and d[0]["headline"].startswith("Tandoor"), d)
s, p2 = rpc("omelo_identity_profile", {"p_identity": cook}, wrk_tok)
check("completeness is recomputed by the server as the profile fills (headline added)",
      p2["completeness"]["score"] > before and "headline" not in p2["completeness"]["missing"], f"{before} -> {p2['completeness']}")

print("\n3. VISIBILITY")
for level in ["matched_only", "discoverable", "recruiters", "public", "private"]:
    s, d = patch(f"/rest/v1/work_identities?id=eq.{eng}", {"discoverability": level}, wrk_tok)
    check(f"set visibility to {level}", s == 200 and d and d[0]["discoverability"] == level, f"{s} {msg(d)}")

print("\n4. EMPLOYERS SEE ONLY THE IDENTITY THAT APPLIED")
s, slug = rpc("omelo_company_slug", {"p_name": f"Identity Kitchens {stamp}"}, emp_tok)
s, co = post("/rest/v1/companies", {"slug": slug, "display_name": f"Identity Kitchens {stamp}", "country_code": "IN",
             "size_band": "11-50", "created_by": emp_id}, emp_tok); cid = co[0]["id"]
s, d = post("/rest/v1/companies", {"slug": slug + "-x", "display_name": "Fake Agency", "country_code": "IN",
            "size_band": "11-50", "created_by": emp_id, "company_kind": "agency"}, emp_tok)
blocked("self-registering as a recruitment agency", s, d)
s, loc = get("/rest/v1/locations?select=id&latitude=not.is.null&country_code=eq.IN&limit=1")
s, job = post("/rest/v1/jobs", {"company_id": cid, "created_by": emp_id, "title": "Tandoor Cook", "profession_id": prof("cook"),
              "location_id": loc[0]["id"], "workplace_type": "onsite", "work_type": "full_time", "pay_min": 20000, "pay_max": 25000,
              "pay_period": "month", "pay_currency": "INR", "accepts_no_experience": True, "status": "draft"}, emp_tok)
jid = job[0]["id"]
post("/rest/v1/job_stages", [{"job_id": jid, "name": "New", "position": 1, "maps_to_state": "applied", "is_terminal": False}], emp_tok)
patch(f"/rest/v1/jobs?id=eq.{jid}", {"status": "published"}, emp_tok)
s, app = post("/rest/v1/applications", {"job_id": jid, "person_id": wrk_id, "company_id": cid, "work_identity_id": cook,
              "identity_snapshot": {}}, wrk_tok)
check("apply as the Cook", s == 201, f"{s} {msg(app)}")
s, ids = get(f"/rest/v1/work_identities?select=id,label&person_id=eq.{wrk_id}", emp_tok)
check("employer sees only the Cook identity", s == 200 and [x["label"] for x in ids] == ["Cook"], ids)
s, sk = get(f"/rest/v1/person_skills?select=work_identity_id,skills(name)&person_id=eq.{wrk_id}", emp_tok)
check("employer sees the Cook's skills and not the Engineer's",
      s == 200 and all(x["work_identity_id"] in (cook, None) for x in sk) and len(sk) == 2, sk)
s, at = get(f"/rest/v1/person_attributes?select=work_identity_id&person_id=eq.{wrk_id}", emp_tok)
check("employer sees Cook answers + shared answers only", s == 200 and all(x["work_identity_id"] in (cook, None) for x in at), at)
s, ev = rpc("omelo_identity_evidence", {"p_identity": cook}, emp_tok)
check("employer reads evidence for the Cook identity", s == 200 and len(ev["skills"]) == 2, f"{s} {msg(ev)}")
knife_ev = next((x for x in ev.get("skills", []) if x["skill_id"] == knife["id"]), {})
check("evidence lists experience and self-declaration", {e["type"] for e in knife_ev.get("evidence", [])} >= {"experience", "self_declared"}, knife_ev)
s, d = rpc("omelo_identity_evidence", {"p_identity": eng}, emp_tok); blocked("employer reads the Engineer identity's evidence", s, d)
s, d = rpc("omelo_identity_evidence", {"p_identity": cook}, out_tok); blocked("outsider reads evidence", s, d)

print("\n4b. OPEN LISTS AND CATEGORY")
s, d = patch(f"/rest/v1/work_identities?id=eq.{drv}", {"profession_id": prof("taxi-driver")}, wrk_tok)
check("change an identity's profession", s in (200, 204), f"{s} {msg(d)}")
s, dp = rpc("omelo_identity_profile", {"p_identity": drv}, wrk_tok)
check("Driver profile asks which routes they know", s == 200 and "routes-known" in {f["slug"] for f in dp["fields"]}, dp)
s, r = rpc("omelo_save_identity_profile", {"p_identity": drv, "p_values": {"routes-known": ["Andheri - Bandra", "Airport road"]}}, wrk_tok)
check("an open list accepts free-text items", s == 200 and r["errors"] == {}, f"{s} {msg(r)}")
s, r = rpc("omelo_save_identity_profile", {"p_identity": drv, "p_values": {"routes-known": ["Airport road", "airport road "]}}, wrk_tok)
check("an open list refuses repeated items", s == 200 and "routes-known" in r["errors"], r)
s, r = rpc("omelo_save_identity_profile", {"p_identity": drv, "p_values": {"routes-known": ["x" * 81]}}, wrk_tok)
check("an open list refuses overlong items", s == 200 and "routes-known" in r["errors"], r)
tcat = get("/rest/v1/professions?select=category_id&slug=eq.delivery-executive")[1][0]["category_id"]
ccat = get("/rest/v1/professions?select=category_id&slug=eq.cook")[1][0]["category_id"]
patch(f"/rest/v1/work_identities?id=eq.{cook}", {"category_id": tcat}, wrk_tok)
s, c = get(f"/rest/v1/work_identities?select=category_id&id=eq.{cook}", wrk_tok)
check("category always follows the profession", s == 200 and c[0]["category_id"] == ccat, c)

print("\n5. PRIMARY, ARCHIVE, DELETE, COPY")
s, d = rpc("omelo_set_primary_identity", {"p_identity": cook}, wrk_tok); check("make Cook the main identity", s in (200, 204), f"{s} {msg(d)}")
s, d = patch(f"/rest/v1/work_identities?id=eq.{cook}", {"is_primary": False}, wrk_tok); blocked("un-setting the main identity directly", s, d)
s, d = patch(f"/rest/v1/work_identities?id=eq.{eng}", {"status": "archived"}, wrk_tok); blocked("archiving by direct update", s, d)
s, d = rpc("omelo_archive_work_identity", {"p_identity": eng}, wrk_tok); check("archive the Engineer identity", s in (200, 204), f"{s} {msg(d)}")
s, d = post("/rest/v1/applications", {"job_id": jid, "person_id": wrk_id, "company_id": cid, "work_identity_id": eng,
            "identity_snapshot": {}}, wrk_tok)
blocked("applying with an archived identity", s, d)
s, d = rpc("omelo_delete_work_identity", {"p_identity": cook}, wrk_tok); blocked("deleting an identity that has applications", s, d)
s, d = rpc("omelo_delete_work_identity", {"p_identity": drv}, wrk_tok); check("delete an unused identity", s in (200, 204), f"{s} {msg(d)}")
s, cp = rpc("omelo_create_work_identity", {"p_label": "Kitchen Supervisor", "p_profession_id": prof("chef"), "p_copy_from": cook}, wrk_tok)
check("create an identity starting from another", s == 200, f"{s} {msg(cp)}")
s, csk = get(f"/rest/v1/person_skills?select=skill_id,is_verified,evidence_type&work_identity_id=eq.{cp}", wrk_tok)
check("skills are copied, never as verified", s == 200 and len(csk) == 2 and not any(x["is_verified"] for x in csk), csk)
s, d = rpc("omelo_delete_work_identity", {"p_identity": cp}, wrk_tok)
s, gone = get(f"/rest/v1/person_skills?select=id&work_identity_id=eq.{cp}", wrk_tok)
check("deleting an identity removes its skills (no leak into shared)", s == 200 and gone == [], gone)
s, shared_sk = get(f"/rest/v1/person_skills?select=id&person_id=eq.{wrk_id}&work_identity_id=is.null", wrk_tok)
check("no orphaned shared skills appeared", s == 200 and shared_sk == [], shared_sk)
for i in [primary_id, ele]:
    rpc("omelo_archive_work_identity", {"p_identity": i}, wrk_tok)
s, d = rpc("omelo_archive_work_identity", {"p_identity": cook}, wrk_tok); blocked("archiving the last active identity", s, d)

print(f"\n{'ALL PASSED' if not FAIL else str(len(FAIL)) + ' FAILED: ' + '; '.join(FAIL)}")
print(f"stamp={stamp}")
sys.exit(1 if FAIL else 0)
