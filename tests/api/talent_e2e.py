"""Release 3: marketplace — funnel tracking, talent search with consent, invite to apply.

    python tests/api/talent_e2e.py setup     # accounts, company, jobs, identities
    -- then, as Omelo (SQL editor / admin portal), verify the probe company and
       enable talent search for it; the setup step prints the exact SQL
    python tests/api/talent_e2e.py run

Verifying a company and granting talent search are Omelo-only actions
(omelo_admin_set_company_verification / omelo_admin_set_entitlements), so a
test running as ordinary users cannot do them itself. Everything else runs as
real users through the publishable key. Creates six probe.* accounts; clean up
as described in hiring_loop_e2e.py.
"""
import json, os, sys, time
from omelo_api import *

STATE = os.path.join(os.path.dirname(__file__), ".talent_state.json")
FAIL = []
def check(label, ok, detail=""):
    print(f"  {'PASS' if ok else 'FAIL'} | {label}" + (f" | {detail}" if detail and not ok else ""))
    if not ok: FAIL.append(label)

def blocked(label, s, d):
    check(f"blocked: {label}", s >= 400 or (isinstance(d, list) and len(d) == 0), f"HTTP {s} {msg(d)}")

def prof(slug):
    return get(f"/rest/v1/professions?select=id&slug=eq.{slug}")[1][0]["id"]
def skill(name_like):
    return get(f"/rest/v1/skills?select=id,name&name=ilike.*{name_like}*&limit=1")[1][0]


def setup():
    stamp = str(int(time.time()))
    PW = "ProbePass2026!"
    st = {"stamp": stamp}
    acc = {}
    for key, name, role in [("emp", "Talent Owner", "employer"), ("emp2", "Other Owner", "employer"),
                            ("w1", "Ravi Open", "worker"), ("w2", "Sita Private", "worker"),
                            ("w3", "Arun Closed", "worker"), ("w4", "Meena Matched", "worker")]:
        email = f"probe.t{key}.{stamp}@omelo.dev"
        tok, pid = signup(email, PW, name, role)
        acc[key] = {"email": email, "id": pid}
    st["acc"] = acc
    tok = {k: login(v["email"], PW)[0] for k, v in acc.items()}

    s, loc = get("/rest/v1/locations?select=id&latitude=not.is.null&country_code=eq.IN&limit=1")
    loc_id = loc[0]["id"]
    cook = prof("cook")
    knife = skill("knife")

    # Workers: a Cook identity each, near the job, with a skill.
    vis = {"w1": "discoverable", "w2": "private", "w3": "discoverable", "w4": "matched_only"}
    for k, level in vis.items():
        s, wid = rpc("omelo_create_work_identity", {"p_label": "Cook", "p_profession_id": cook}, tok[k])
        assert s == 200, (k, s, wid)
        patch(f"/rest/v1/work_identities?id=eq.{wid}",
              {"discoverability": level, "headline": "Tandoor and curry cook", "total_experience_months": 36,
               "allow_invitations": k != "w3"}, tok[k])
        post("/rest/v1/person_location_preferences", {"person_id": acc[k]["id"], "work_identity_id": wid,
             "kind": "city", "location_id": loc_id, "radius_km": 25}, tok[k])
        post("/rest/v1/person_skills", {"person_id": acc[k]["id"], "work_identity_id": wid, "skill_id": knife["id"],
             "proficiency": "advanced", "months_used": 36}, tok[k])
        acc[k]["identity"] = wid

    # Employer: company + two published jobs.
    s, slug = rpc("omelo_company_slug", {"p_name": f"Talent Kitchens {stamp}"}, tok["emp"])
    s, co = post("/rest/v1/companies", {"slug": slug, "display_name": f"Talent Kitchens {stamp}", "country_code": "IN",
                 "size_band": "11-50", "created_by": acc["emp"]["id"]}, tok["emp"])
    cid = co[0]["id"]
    jobs = []
    for title in ["Tandoor Cook", "Line Cook"]:
        s, job = post("/rest/v1/jobs", {"company_id": cid, "created_by": acc["emp"]["id"], "title": title,
                      "profession_id": cook, "location_id": loc_id, "workplace_type": "onsite", "work_type": "full_time",
                      "pay_min": 20000, "pay_max": 26000, "pay_period": "month", "pay_currency": "INR",
                      "accepts_no_experience": True, "status": "draft"}, tok["emp"])
        jid = job[0]["id"]
        post("/rest/v1/job_stages", [{"job_id": jid, "name": "New", "position": 1, "maps_to_state": "applied",
                                      "is_terminal": False}], tok["emp"])
        patch(f"/rest/v1/jobs?id=eq.{jid}", {"status": "published"}, tok["emp"])
        jobs.append(jid)
    st.update(company=cid, jobs=jobs, location=loc_id)

    print("\n0. BEFORE OMELO GRANTS TALENT SEARCH")
    s, d = rpc("omelo_search_talent", {"p_job_id": jobs[0]}, tok["emp"]); blocked("search by an unverified company", s, d)
    s, d = rpc("omelo_invite_to_apply", {"p_job_id": jobs[0], "p_identity": acc["w1"]["identity"]}, tok["emp"])
    blocked("invite by an unverified company", s, d)
    s, d = rpc("omelo_admin_set_entitlements", {"p_company": cid, "p_plan": "pro", "p_talent_search": True}, tok["emp"])
    blocked("an employer grants itself talent search", s, d)
    s, d = rpc("omelo_admin_set_company_verification", {"p_company": cid, "p_verified": True}, tok["emp"])
    blocked("an employer verifies itself", s, d)
    s, d = patch(f"/rest/v1/company_entitlements?company_id=eq.{cid}", {"talent_search_enabled": True}, tok["emp"])
    blocked("an employer edits its entitlements directly", s, d)

    json.dump(st, open(STATE, "w"))
    print(f"\nNow run as Omelo (test fixture for probe company {cid}):\n")
    print(f"  update companies set is_verified = true, verified_at = now(), verification_method = 'manual_admin' where id = '{cid}';")
    print(f"  update company_entitlements set talent_search_enabled = true, talent_search_quota_monthly = 6, "
          f"outreach_quota_daily = 10 where company_id = '{cid}';")
    print("\nthen: python tests/api/talent_e2e.py run")
    print(f"\n{'SETUP OK' if not FAIL else str(len(FAIL)) + ' FAILED: ' + '; '.join(FAIL)}")


def run():
    st = json.load(open(STATE))
    PW = "ProbePass2026!"
    acc = st["acc"]
    tok = {k: login(v["email"], PW)[0] for k, v in acc.items()}
    cid, (j1, j2) = st["company"], st["jobs"]
    W = {k: acc[k]["identity"] for k in ("w1", "w2", "w3", "w4")}
    searches = 0

    print("\n1. TALENT SEARCH WITH CONSENT")
    s, r = rpc("omelo_search_talent", {"p_job_id": j1, "p_radius_km": 50}, tok["emp"]); searches += 1
    ids = [x["work_identity_id"] for x in r.get("results", [])] if s == 200 else []
    check("search runs for a verified, entitled company", s == 200, f"{s} {msg(r)}")
    check("a discoverable Cook is found", W["w1"] in ids, ids)
    check("a private identity is never found", W["w2"] not in ids, ids)
    card = next((x for x in r.get("results", []) if x["work_identity_id"] == W["w1"]), {})
    check("results carry a match score, strengths and gaps", isinstance(card.get("score"), int) and "strengths" in card, card)
    check("results never expose email or phone", not any(k in json.dumps(card) for k in (acc["w1"]["email"], '"phone"', '"email"')), card)
    check("names are shortened (first name + initial)", card.get("name", "").endswith("."), card.get("name"))
    s, r2 = rpc("omelo_search_talent", {"p_job_id": j1, "p_query": "tandoor"}, tok["emp"]); searches += 1
    check("text search matches the headline", s == 200 and W["w1"] in [x["work_identity_id"] for x in r2["results"]], msg(r2))
    s, r3 = rpc("omelo_search_talent", {"p_job_id": j1, "p_query": "zzz_no_such_%"}, tok["emp"]); searches += 1
    check("text search is literal (wildcards escaped)", s == 200 and r3["total"] == 0, msg(r3))
    s, d = rpc("omelo_search_talent", {"p_job_id": j1}, tok["emp2"]); blocked("another company searches for this job", s, d)
    s, d = rpc("omelo_search_talent", {"p_job_id": j1}, tok["w1"]); blocked("a worker runs talent search", s, d)

    print("\n2. PROFILES AND VIEWS")
    s, p = rpc("omelo_talent_profile", {"p_identity": W["w1"], "p_job_id": j1}, tok["emp"])
    check("open a visible candidate's profile", s == 200 and p["card"]["label"] == "Cook" and "evidence" in p, f"{s} {msg(p)}")
    s, d = rpc("omelo_talent_profile", {"p_identity": W["w2"], "p_job_id": j1}, tok["emp"]); blocked("open a private identity", s, d)
    s, v = rpc("omelo_my_profile_views", {}, tok["w1"])
    check("the worker sees which company viewed them", s == 200 and any(x["company_name"].startswith("Talent Kitchens") for x in v), v)
    s, d = post("/rest/v1/profile_views", {"person_id": acc["w2"]["id"], "viewer_company_id": cid}, tok["emp"])
    blocked("forging a profile view", s, d)

    print("\n3. INVITE TO APPLY")
    s, d = post("/rest/v1/candidate_invitations", {"company_id": cid, "job_id": j1, "person_id": acc["w2"]["id"]}, tok["emp"])
    blocked("inserting an invitation directly", s, d)
    s, inv1 = rpc("omelo_invite_to_apply", {"p_job_id": j1, "p_identity": W["w1"],
                                            "p_message": "Your tandoor experience fits our kitchen."}, tok["emp"])
    check("invite a visible candidate", s == 200 and isinstance(inv1, str), f"{s} {msg(inv1)}")
    s, d = rpc("omelo_invite_to_apply", {"p_job_id": j1, "p_identity": W["w1"]}, tok["emp"]); blocked("inviting twice to the same job", s, d)
    s, d = rpc("omelo_invite_to_apply", {"p_job_id": j1, "p_identity": W["w2"]}, tok["emp"]); blocked("inviting a private identity", s, d)
    s, d = rpc("omelo_invite_to_apply", {"p_job_id": j1, "p_identity": W["w3"]}, tok["emp"]); blocked("inviting someone who turned invitations off", s, d)
    s, d = rpc("omelo_invite_to_apply", {"p_job_id": j1, "p_identity": W["w1"]}, tok["emp2"]); blocked("another company invites to this job", s, d)
    s, mine = rpc("omelo_my_invitations", {}, tok["w1"])
    got = next((x for x in mine if x["id"] == inv1), {}) if s == 200 else {}
    check("the worker sees the invitation with job and company", got.get("status") == "pending" and got.get("job_title") == "Tandoor Cook", got)
    s, notes = get(f"/rest/v1/notifications?select=type,title&person_id=eq.{acc['w1']['id']}&type=eq.job_invitation", tok["w1"])
    check("the worker gets an in-app notification", s == 200 and len(notes) == 1, notes)
    s, d = rpc("omelo_my_invitations", {}, tok["w2"]); check("other workers do not see it", s == 200 and d == [], d)
    s, d = patch(f"/rest/v1/candidate_invitations?id=eq.{inv1}", {"response": "applied"}, tok["w1"]); blocked("rewriting an invitation directly", s, d)
    s, d = rpc("omelo_mark_invitation_viewed", {"p_invitation": inv1}, tok["w1"])
    check("mark the invitation seen", s in (200, 204), f"{s} {msg(d)}")

    print("\n4. APPLYING CLOSES THE LOOP")
    s, app = post("/rest/v1/applications", {"job_id": j1, "person_id": acc["w1"]["id"], "company_id": cid,
                  "work_identity_id": W["w1"], "identity_snapshot": {}}, tok["w1"])
    check("the invited worker applies", s == 201, f"{s} {msg(app)}")
    s, mine = rpc("omelo_my_invitations", {}, tok["w1"])
    got = next((x for x in mine if x["id"] == inv1), {})
    check("the invitation is now applied", got.get("status") == "applied" and got.get("application_id"), got)
    s, ji = rpc("omelo_job_invitations", {"p_job_id": j1}, tok["emp"])
    check("the employer sees the invitation accepted", s == 200 and ji and ji[0]["status"] == "applied" and ji[0]["viewed"], ji)
    s, d = rpc("omelo_withdraw_invitation", {"p_invitation": inv1}, tok["emp"]); blocked("withdrawing an answered invitation", s, d)

    s, inv2 = rpc("omelo_invite_to_apply", {"p_job_id": j2, "p_identity": W["w1"]}, tok["emp"])
    check("invite to a second job", s == 200, f"{s} {msg(inv2)}")
    s, d = rpc("omelo_respond_to_invitation", {"p_invitation": inv2, "p_reason": "I prefer day shifts"}, tok["w1"])
    check("the worker declines with a reason", s in (200, 204), f"{s} {msg(d)}")
    s, d = rpc("omelo_respond_to_invitation", {"p_invitation": inv2}, tok["w1"]); blocked("declining twice", s, d)
    s, d = rpc("omelo_respond_to_invitation", {"p_invitation": inv2}, tok["w2"]); blocked("declining someone else's invitation", s, d)
    s, ji2 = rpc("omelo_job_invitations", {"p_job_id": j2}, tok["emp"])
    check("the employer sees the decline reason", s == 200 and ji2[0]["status"] == "declined" and ji2[0]["decline_reason"], ji2)

    print("\n5. FUNNEL MEASUREMENT")
    ev = [{"job_id": j2, "event": "impression", "surface": "recommended", "rank": 1},
          {"job_id": j2, "event": "view", "surface": "recommended", "rank": 1},
          {"job_id": j2, "event": "hack", "surface": "recommended"},
          {"job_id": "not-a-uuid", "event": "view"}]
    s, n = rpc("omelo_track_job_events", {"p_events": ev}, tok["w2"])
    check("track an impression and a view (bad events skipped)", s == 200 and n == 2, f"{s} {n}")
    s, n = rpc("omelo_track_job_events", {"p_events": ev}, tok["w2"])
    check("repeats are de-duplicated", s == 200 and n == 0, f"{s} {n}")
    s, n = rpc("omelo_track_job_events", {"p_events": ev}, None)
    check("anonymous browsing is not tracked", s in (200, 401, 403) and n in (0, None) or s >= 400, f"{s} {n}")
    s, d = get("/rest/v1/match_events?select=id&limit=1", tok["emp"]); blocked("reading raw match events", s, d)
    s, d = post("/rest/v1/match_events", {"job_id": j2, "company_id": cid, "event": "apply", "surface": "other"}, tok["w2"])
    blocked("writing match events directly", s, d)
    s, job = get(f"/rest/v1/jobs?select=view_count&id=eq.{j2}")
    check("the job's view count is maintained", s == 200 and (job[0]["view_count"] or 0) >= 1, job)
    s, f = rpc("omelo_job_funnel", {"p_job_id": j1}, tok["emp"])
    check("funnel: 1 applied, invitations sent 1 / applied 1",
          s == 200 and f["applied"] == 1 and f["invitations"]["sent"] == 1 and f["invitations"]["applied"] == 1, f)
    check("funnel: the application is attributed to the invitation",
          any(x["surface"] == "invitation" and x["applications"] == 1 for x in f.get("by_surface", [])), f.get("by_surface"))
    check("funnel counts talent searches", f.get("talent_searches", 0) >= searches, f.get("talent_searches"))
    s, d = rpc("omelo_job_funnel", {"p_job_id": j1}, tok["emp2"]); blocked("another company reads the funnel", s, d)
    s, d = rpc("omelo_admin_matching_metrics", {}, tok["emp"]); blocked("an employer reads platform metrics", s, d)

    print("\n6. TALENT POOLS")
    s, pool = post("/rest/v1/talent_pools", {"company_id": cid, "name": "Tandoor specialists"}, tok["emp"])
    check("create a talent pool", s == 201, f"{s} {msg(pool)}")
    pid = pool[0]["id"]
    s, d = post("/rest/v1/talent_pool_members", {"pool_id": pid, "person_id": acc["w1"]["id"], "work_identity_id": W["w1"]}, tok["emp"])
    check("save a visible candidate to the pool", s == 201, f"{s} {msg(d)}")
    s, d = post("/rest/v1/talent_pool_members", {"pool_id": pid, "person_id": acc["w2"]["id"], "work_identity_id": W["w2"]}, tok["emp"])
    blocked("saving a private identity to a pool", s, d)
    s, d = post("/rest/v1/talent_pool_members", {"pool_id": pid, "person_id": acc["w2"]["id"], "work_identity_id": W["w1"]}, tok["emp"])
    blocked("saving someone under another person's identity", s, d)
    s, m = rpc("omelo_pool_members", {"p_pool": pid}, tok["emp"])
    check("pool lists the saved candidate", s == 200 and len(m) == 1 and m[0]["visible"], m)

    print("\n7. WITHDRAWING CONSENT")
    s, r = rpc("omelo_search_talent", {"p_job_id": j2}, tok["emp"]); searches += 1
    check("before: w3 (invitations off) is still findable", s == 200 and W["w3"] in [x["work_identity_id"] for x in r["results"]], msg(r))
    patch(f"/rest/v1/work_identities?id=eq.{W['w3']}", {"discoverability": "private"}, tok["w3"])
    s, me = get(f"/rest/v1/persons?select=discoverability&id=eq.{acc['w3']['id']}", tok["w3"])
    check("the person-level setting follows the identity", s == 200 and me[0]["discoverability"] == "private", me)
    s, r = rpc("omelo_search_talent", {"p_job_id": j2}, tok["emp"]); searches += 1
    check("after going private they disappear from search", s == 200 and W["w3"] not in [x["work_identity_id"] for x in r["results"]], msg(r))
    s, d = rpc("omelo_talent_profile", {"p_identity": W["w3"]}, tok["emp"]); blocked("opening them after they went private", s, d)
    s, me = get(f"/rest/v1/persons?select=discoverability&id=eq.{acc['w1']['id']}", tok["w1"])
    check("a discoverable identity makes the person discoverable", s == 200 and me[0]["discoverability"] == "discoverable", me)

    print("\n8. QUOTA")
    while searches < 6:
        rpc("omelo_search_talent", {"p_job_id": j2}, tok["emp"]); searches += 1
    s, d = rpc("omelo_search_talent", {"p_job_id": j2}, tok["emp"]); blocked("searching past the monthly quota", s, d)

    os.remove(STATE)
    print(f"\n{'ALL PASSED' if not FAIL else str(len(FAIL)) + ' FAILED: ' + '; '.join(FAIL)}")


if __name__ == "__main__":
    {"setup": setup, "run": run}.get(sys.argv[1] if len(sys.argv) > 1 else "", lambda: print(__doc__))()
