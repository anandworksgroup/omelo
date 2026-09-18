"""Release 4: recruiters & agencies — consent-scoped representation, as real users.

    python tests/api/recruitment_e2e.py setup   # accounts, agency, team, client, job orders
    -- then, as Omelo, verify the probe agency and enable talent search for it;
       setup prints the exact SQL (employers and agencies cannot grant it)
    python tests/api/recruitment_e2e.py run

The whole R4 release definition runs here:
agency created -> recruiter joins -> client created and confirmed -> job order
-> search -> worker discoverable -> consent requested -> worker accepts ->
submitted -> client reviews -> shortlist -> Omelo Meet interview -> offer ->
hire -> placement. Every R4 invariant (R4-001 .. R4-014) is attacked as the
real user who would try it. Creates eight probe.* accounts; clean up as in
hiring_loop_e2e.py.
"""
import datetime as dt, json, os, sys, time
from omelo_api import *

STATE = os.path.join(os.path.dirname(__file__), ".recruitment_state.json")
PW = "ProbePass2026!"
FAIL = []
def check(label, ok, detail=""):
    print(f"  {'PASS' if ok else 'FAIL'} | {label}" + (f" | {detail}" if detail and not ok else ""))
    if not ok: FAIL.append(label)

def blocked(label, s, d):
    check(f"blocked: {label}", s >= 400 or (isinstance(d, list) and len(d) == 0), f"HTTP {s} {msg(d)}")

def prof(slug):
    return get(f"/rest/v1/professions?select=id&slug=eq.{slug}")[1][0]["id"]
def skill(*names):
    for n in names:
        s, d = get(f"/rest/v1/skills?select=id,name&name=ilike.*{n}*&limit=1")
        if s == 200 and d: return d[0]
    return get("/rest/v1/skills?select=id,name&limit=1")[1][0]


def setup():
    stamp = str(int(time.time()))
    acc = {}
    for key, name, role in [("rec", "Rita Recruiter", "employer"), ("src", "Sam Sourcer", "employer"),
                            ("rec2", "Ravi Unassigned", "employer"), ("cli", "Clara Client", "employer"),
                            ("rogue", "Rogue Agent", "employer"), ("w1", "Ravi Kumar", "worker"),
                            ("w2", "Sita Employers Only", "worker"), ("w3", "Arun NoRecruiters", "worker")]:
        email = f"probe.r{key}.{stamp}@omelo.dev"
        _, pid = signup(email, PW, name, role)
        acc[key] = {"email": email, "id": pid}
    tok = {k: login(v["email"], PW)[0] for k, v in acc.items()}
    s, loc = get("/rest/v1/locations?select=id&latitude=not.is.null&country_code=eq.IN&limit=1")
    loc_id = loc[0]["id"]
    wh = prof("warehouse-worker")
    sk = skill("inventory", "forklift", "loading", "packing")

    print("\n0a. WORKERS")
    vis = {"w1": ("recruiters", True), "w2": ("discoverable", True), "w3": ("recruiters", False)}
    for k, (level, allow) in vis.items():
        s, wid = rpc("omelo_create_work_identity", {"p_label": "Warehouse Associate", "p_profession_id": wh}, tok[k])
        assert s == 200, (k, s, wid)
        patch(f"/rest/v1/work_identities?id=eq.{wid}", {"discoverability": level, "headline": "Night-shift warehouse associate",
              "total_experience_months": 60, "allow_recruiter_requests": allow}, tok[k])
        post("/rest/v1/person_location_preferences", {"person_id": acc[k]["id"], "work_identity_id": wid,
             "kind": "city", "location_id": loc_id, "radius_km": 30}, tok[k])
        post("/rest/v1/person_skills", {"person_id": acc[k]["id"], "work_identity_id": wid, "skill_id": sk["id"],
             "proficiency": "advanced", "months_used": 48}, tok[k])
        post("/rest/v1/experiences", {"person_id": acc[k]["id"], "work_identity_id": wid, "employer_name": "Metro Logistics",
             "title": "Warehouse associate", "started_on": "2021-01-01", "is_current": True}, tok[k])
        acc[k]["identity"] = wid
    check("worker identities set up", all("identity" in acc[k] for k in vis))

    print("\n0b. AGENCY AND TEAM")
    s, d = post("/rest/v1/companies", {"slug": f"fake-agency-{stamp}", "display_name": "Fake Agency", "country_code": "IN",
                "company_kind": "agency", "created_by": acc["rogue"]["id"]}, tok["rogue"])
    blocked("creating an agency by inserting a company row", s, d)
    s, agency = rpc("omelo_create_agency", {"p_name": f"Acme Staffing {stamp}"}, tok["rec"])
    check("create an agency", s == 200 and isinstance(agency, str), f"{s} {msg(agency)}")
    s, rogue_agency = rpc("omelo_create_agency", {"p_name": f"Rogue Talent {stamp}", "p_independent": True}, tok["rogue"])
    check("an independent recruiter creates their own agency", s == 200, f"{s} {msg(rogue_agency)}")
    s, d = post("/rest/v1/company_members", {"company_id": agency, "person_id": acc["w1"]["id"], "role": "recruiter"}, tok["rec"])
    blocked("adding someone to the agency without their consent", s, d)
    for k, role in [("src", "sourcer"), ("rec2", "recruiter")]:
        s, inv = rpc("omelo_invite_team_member", {"p_company": agency, "p_email": acc[k]["email"], "p_role": role}, tok["rec"])
        check(f"invite a {role}", s == 200, f"{s} {msg(inv)}")
        s, d = rpc("omelo_accept_team_invitation", {"p_invitation": inv}, tok["rogue"])
        blocked(f"someone else accepts the {role}'s invitation", s, d)
        s, mine = rpc("omelo_my_team_invitations", {}, tok[k])
        check(f"the {role} sees the invitation", s == 200 and any(x["id"] == inv for x in mine), mine)
        s, d = rpc("omelo_accept_team_invitation", {"p_invitation": inv}, tok[k])
        check(f"the {role} joins the agency", s == 200 and d == agency, f"{s} {msg(d)}")
    s, d = rpc("omelo_invite_team_member", {"p_company": agency, "p_email": "x@example.com", "p_role": "owner"}, tok["src"])
    blocked("a sourcer invites people", s, d)

    print("\n0c. CLIENT")
    s, slug = rpc("omelo_company_slug", {"p_name": f"ABC Logistics {stamp}"}, tok["cli"])
    s, co = post("/rest/v1/companies", {"slug": slug, "display_name": f"ABC Logistics {stamp}", "country_code": "IN",
                 "size_band": "51-200", "created_by": acc["cli"]["id"]}, tok["cli"])
    client_company = co[0]["id"]
    s, job = post("/rest/v1/jobs", {"company_id": client_company, "created_by": acc["cli"]["id"], "title": "Warehouse Associate (night)",
                  "profession_id": wh, "location_id": loc_id, "workplace_type": "onsite", "work_type": "full_time",
                  "pay_min": 22000, "pay_max": 22000, "pay_period": "month", "pay_currency": "INR",
                  "accepts_no_experience": True, "status": "draft"}, tok["cli"])
    client_job = job[0]["id"]
    post("/rest/v1/job_stages", [{"job_id": client_job, "name": n, "position": i + 1, "maps_to_state": st, "is_terminal": t}
         for i, (n, st, t) in enumerate([("New", "applied", False), ("Shortlist", "shortlisted", False),
                                         ("Interview", "interview", False), ("Offer", "offer", False),
                                         ("Hired", "hired", True), ("Rejected", "rejected", True)])], tok["cli"])
    s, cl = post("/rest/v1/agency_clients", {"agency_id": agency, "name": "ABC Logistics", "relationship_status": "active",
                 "locations": ["Delhi"], "departments": ["Operations"], "notes": "Peak season hiring"}, tok["rec"])
    check("create a client", s == 201, f"{s} {msg(cl)}")
    client_id = cl[0]["id"]
    s, d = post("/rest/v1/agency_client_contacts", {"client_id": client_id, "name": "Priya Ops", "title": "Ops Manager",
                "email": "priya@example.com", "is_primary": True}, tok["rec"])
    check("add a client contact", s == 201, f"{s} {msg(d)}")
    s, d = patch(f"/rest/v1/agency_clients?id=eq.{client_id}", {"client_company_id": client_company, "link_status": "confirmed"}, tok["rec"])
    blocked("an agency links itself to a company (impersonating the employer)", s, d)
    s, d = post("/rest/v1/agency_clients", {"agency_id": agency, "name": "Sneaky"}, tok["src"])
    blocked("a sourcer manages clients", s, d)
    s, d = rpc("omelo_request_client_link", {"p_client": client_id, "p_company": client_company}, tok["rec"])
    check("ask the client company to confirm", s in (200, 204), f"{s} {msg(d)}")
    s, d = rpc("omelo_respond_client_link", {"p_client": client_id, "p_accept": True}, tok["rec"])
    blocked("the agency confirms on the client's behalf", s, d)
    s, rel = rpc("omelo_my_agency_relationships", {}, tok["cli"])
    check("the client sees the pending agency", s == 200 and any(r["client_id"] == client_id and r["can_answer"] for r in rel), rel)
    s, d = rpc("omelo_respond_client_link", {"p_client": client_id, "p_accept": True}, tok["cli"])
    check("the client confirms the agency", s in (200, 204), f"{s} {msg(d)}")

    print("\n0d. JOB ORDERS")
    order = {"title": "Warehouse Associate", "profession_id": wh, "openings": 50, "location_id": loc_id,
             "location_text": "Delhi", "work_type": "full_time", "shift_types": ["night"], "pay_min": 22000,
             "pay_max": 22000, "pay_period": "month", "pay_currency": "INR", "min_experience_months": 12,
             "required_skill_ids": [sk["id"]], "hard_requirements": ["Can lift 25 kg"], "start_date": "2026-10-01",
             "closing_date": "2026-09-30", "priority": "urgent"}
    s, jo1 = rpc("omelo_create_job_order", {"p_client": client_id, "p_order": order}, tok["rec"])
    check("create job order (50 warehouse workers, Delhi, 22k, night)", s == 200 and isinstance(jo1, str), f"{s} {msg(jo1)}")
    s, d = rpc("omelo_create_job_order", {"p_client": client_id, "p_order": order}, tok["src"]); blocked("a sourcer creates job orders", s, d)
    s, d = post("/rest/v1/job_orders", {"agency_id": agency, "client_id": client_id, "reference": "X", "title": "x",
                "job_id": client_job}, tok["rec"])
    blocked("inserting a job order directly", s, d)
    s, jo2 = rpc("omelo_create_job_order", {"p_client": client_id, "p_order": {**order, "title": "Loader (off-platform)",
                 "openings": 2}}, tok["rec"])
    check("a second job order", s == 200, f"{s} {msg(jo2)}")
    s, cjo = rpc("omelo_client_job_orders", {}, tok["cli"])
    check("the client sees the agency's orders", s == 200 and any(x["id"] == jo1 for x in cjo), cjo)
    s, d = rpc("omelo_link_job_order", {"p_job_order": jo1, "p_job": client_job}, tok["rec"])
    blocked("the agency links the client's job itself", s, d)
    s, d = rpc("omelo_link_job_order", {"p_job_order": jo1, "p_job": client_job}, tok["cli"])
    check("the client connects its job to the order", s in (200, 204), f"{s} {msg(d)}")
    s, d = rpc("omelo_assign_job_order_recruiter", {"p_order": jo1, "p_person": acc["src"]["id"]}, tok["rec"])
    check("assign the sourcer to the order", s in (200, 204), f"{s} {msg(d)}")
    s, d = rpc("omelo_search_talent_for_order", {"p_job_order": jo1}, tok["rec"]); blocked("search before Omelo verifies the agency", s, d)

    st = {"stamp": stamp, "acc": acc, "agency": agency, "rogue_agency": rogue_agency, "client_id": client_id,
          "client_company": client_company, "client_job": client_job, "jo1": jo1, "jo2": jo2, "skill": sk["id"]}
    json.dump(st, open(STATE, "w"))
    print(f"\nNow run as Omelo (fixture: verify probe agency {agency} and enable talent search):\n")
    print(f"  update companies set is_verified = true, verified_at = now(), verification_method = 'manual_admin' where id = '{agency}';")
    print(f"  update company_entitlements set talent_search_enabled = true, talent_search_quota_monthly = 0, "
          f"outreach_quota_daily = 0 where company_id = '{agency}';")
    print("\nthen: python tests/api/recruitment_e2e.py run")
    print(f"\n{'SETUP OK' if not FAIL else str(len(FAIL)) + ' FAILED: ' + '; '.join(FAIL)}")


def run():
    st = json.load(open(STATE))
    acc = st["acc"]
    tok = {k: login(v["email"], PW)[0] for k, v in acc.items()}
    agency, jo1, jo2 = st["agency"], st["jo1"], st["jo2"]
    W = {k: acc[k]["identity"] for k in ("w1", "w2", "w3")}

    print("\n1. RECRUITER TALENT SEARCH (consent-aware, visibility-respecting)")
    s, r = rpc("omelo_search_talent_for_order", {"p_job_order": jo1, "p_filters": {"radius_km": 100}}, tok["src"])
    ids = [x["work_identity_id"] for x in r.get("results", [])] if s == 200 else []
    check("a sourcer searches for the job order", s == 200, f"{s} {msg(r)}")
    check("a worker visible to recruiters is found", W["w1"] in ids, ids)
    check("R4-006 a worker visible to employers only is NOT found by an agency", W["w2"] not in ids, ids)
    card = next((x for x in r.get("results", []) if x["work_identity_id"] == W["w1"]), {})
    check("result shows match, availability/pay slots, evidence counts and consent status",
          isinstance(card.get("score"), int) and "verified_employers" in card and "consent" in card
          and card.get("accepts_recruiter_requests") is True, card)
    check("result never carries contact details", "email" not in json.dumps(card) and acc["w1"]["email"] not in json.dumps(card), card)
    s, r2 = rpc("omelo_search_talent_for_order", {"p_job_order": jo1, "p_filters": {"skill_ids": [st["skill"]],
                "consent_status": "none", "min_experience_months": 24}}, tok["rec"])
    check("filters: skill + experience + no consent yet", s == 200 and W["w1"] in [x["work_identity_id"] for x in r2["results"]], msg(r2))
    s, d = rpc("omelo_search_talent_for_order", {"p_job_order": jo1}, tok["rogue"]); blocked("another agency searches this order", s, d)
    s, d = rpc("omelo_search_talent_for_order", {"p_job_order": jo1}, tok["cli"]); blocked("the client searches the agency's order", s, d)

    print("\n2. TALENT POOLS (membership grants nothing)")
    s, pool = post("/rest/v1/talent_pools", {"company_id": agency, "name": "Delhi Warehouse — Available Immediately"}, tok["rec"])
    check("create an agency talent pool", s == 201, f"{s} {msg(pool)}")
    pool_id = pool[0]["id"]
    s, d = post("/rest/v1/talent_pool_members", {"pool_id": pool_id, "person_id": acc["w1"]["id"], "work_identity_id": W["w1"]}, tok["src"])
    check("a sourcer saves a visible worker to the pool", s == 201, f"{s} {msg(d)}")
    s, d = post("/rest/v1/talent_pool_members", {"pool_id": pool_id, "person_id": acc["w2"]["id"], "work_identity_id": W["w2"]}, tok["rec"])
    blocked("R4-006 saving a worker the agency cannot see", s, d)
    s, r3 = rpc("omelo_search_talent_for_order", {"p_job_order": jo1, "p_filters": {"pool_id": pool_id}}, tok["rec"])
    check("filter search by pool", s == 200 and [x["work_identity_id"] for x in r3["results"]] == [W["w1"]], msg(r3))
    s, d = post("/rest/v1/candidate_submissions", {"consent_id": None, "person_id": acc["w1"]["id"], "work_identity_id": W["w1"],
                "agency_id": agency, "client_id": st["client_id"], "job_order_id": jo1, "snapshot": {}}, tok["rec"])
    blocked("R4-001/R4-009 submitting a pooled worker directly, without consent", s, d)

    print("\n3. CONSENT REQUEST")
    scope = ["identity", "skills", "experience", "evidence"]          # no answers, no contact: a narrowed scope
    s, d = rpc("omelo_request_representation", {"p_job_order": jo1, "p_identity": W["w2"]}, tok["src"])
    blocked("R4-006 asking a worker the agency cannot see", s, d)
    s, d = rpc("omelo_request_representation", {"p_job_order": jo1, "p_identity": W["w3"]}, tok["src"])
    blocked("asking a worker who turned recruiter requests off", s, d)
    s, d = rpc("omelo_request_representation", {"p_job_order": jo1, "p_identity": W["w1"], "p_scope": ["skills"]}, tok["src"])
    blocked("a scope without the professional identity", s, d)
    s, c1 = rpc("omelo_request_representation", {"p_job_order": jo1, "p_identity": W["w1"], "p_scope": scope,
                "p_valid_days": 60, "p_message": "ABC Logistics is hiring 50 for the night shift."}, tok["src"])
    check("a sourcer asks the worker for consent", s == 200 and isinstance(c1, str), f"{s} {msg(c1)}")
    s, d = rpc("omelo_request_representation", {"p_job_order": jo1, "p_identity": W["w1"]}, tok["rec"])
    blocked("asking twice for the same order", s, d)
    s, d = post("/rest/v1/candidate_consents", {"person_id": acc["w1"]["id"], "work_identity_id": W["w1"], "agency_id": agency,
                "job_order_id": jo1, "client_id": st["client_id"], "information_scope": ["identity"], "terms": {},
                "status": "accepted"}, tok["rec"])
    blocked("R4-008 a recruiter manufactures a consent", s, d)
    s, d = patch(f"/rest/v1/candidate_consents?id=eq.{c1}", {"status": "accepted"}, tok["rec"])
    blocked("R4-008 a recruiter accepts on the worker's behalf (direct write)", s, d)
    s, d = rpc("omelo_respond_to_representation", {"p_consent": c1, "p_accept": True}, tok["rec"])
    blocked("R4-008 a recruiter accepts on the worker's behalf (function)", s, d)
    s, d = rpc("omelo_submit_candidate", {"p_consent": c1}, tok["rec"]); blocked("R4-001 submitting before the worker accepts", s, d)

    print("\n4. THE WORKER DECIDES")
    s, reps = rpc("omelo_my_representations", {}, tok["w1"])
    rep = next((x for x in reps if x["id"] == c1), {}) if s == 200 else {}
    t = rep.get("terms", {})
    check("the worker sees agency, recruiter, client, position, place, pay and what is shared",
          rep.get("status") == "requested" and t.get("client", {}).get("name", "").startswith("ABC Logistics")
          and t.get("position") == "Warehouse Associate" and t.get("pay", {}).get("min") == 22000
          and t.get("agency", {}).get("name", "").startswith("Acme Staffing") and rep.get("scope") == sorted(scope), rep)
    s, notes = get(f"/rest/v1/notifications?select=type&person_id=eq.{acc['w1']['id']}&type=eq.representation_request", tok["w1"])
    check("the worker was notified", s == 200 and len(notes) == 1, notes)
    s, d = rpc("omelo_my_representations", {}, tok["w2"]); check("other workers do not see it", s == 200 and d == [], d)
    s, d = rpc("omelo_respond_to_representation", {"p_consent": c1, "p_accept": True}, tok["w1"])
    check("the worker accepts", s in (200, 204), f"{s} {msg(d)}")
    s, ev = get(f"/rest/v1/candidate_consent_events?select=from_status,to_status,actor_type&consent_id=eq.{c1}&order=id", tok["w1"])
    check("R4-012 every consent transition is recorded (requested -> accepted, by the candidate)",
          s == 200 and [(e["from_status"], e["to_status"], e["actor_type"]) for e in ev]
          == [(None, "requested", "recruiter"), ("requested", "accepted", "candidate")], ev)

    print("\n5. SUBMISSION")
    s, d = rpc("omelo_submit_candidate", {"p_consent": c1}, tok["src"]); blocked("R4-010 a sourcer submits", s, d)
    s, d = rpc("omelo_submit_candidate", {"p_consent": c1}, tok["rec2"]); blocked("R4-005 a recruiter not assigned to the order submits", s, d)
    s, d = rpc("omelo_submit_candidate", {"p_consent": c1}, tok["rogue"]); blocked("R4-005 another agency uses this consent", s, d)
    s, sub1 = rpc("omelo_submit_candidate", {"p_consent": c1, "p_note": "5 years night shift, forklift-ready."}, tok["rec"])
    check("the assigned recruiter submits", s == 200 and isinstance(sub1, str), f"{s} {msg(sub1)}")
    s, d = rpc("omelo_submit_candidate", {"p_consent": c1}, tok["rec"]); blocked("R4-001 reusing a consent for a second submission", s, d)
    s, subs = rpc("omelo_agency_submissions", {"p_agency": agency}, tok["rec"])
    s1 = next((x for x in subs if x["id"] == sub1), {}) if s == 200 else {}
    check("the submission went into the client's pipeline", s1.get("on_omelo") and s1.get("application_state") == "applied"
          and s1.get("consent_status") == "active", s1)
    s, sv = get(f"/rest/v1/candidate_submissions?select=snapshot&id=eq.{sub1}", tok["rec"])
    snap = sv[0]["snapshot"] if s == 200 and sv else {}
    check("R4-014 the snapshot holds only the consented scope (no answers, no contact)",
          "skills" in snap and "experience" in snap and "answers" not in snap and "contact" not in snap, list(snap))

    print("\n6. THE CLIENT REVIEWS (existing hiring engine)")
    s, cs = rpc("omelo_client_submissions", {}, tok["cli"])
    c_row = next((x for x in cs if x["submission_id"] == sub1), {}) if s == 200 else {}
    check("the client sees candidate, applied-as, match, recruiter, agency, consent, stage",
          c_row.get("applied_as") == "Warehouse Associate" and c_row.get("agency", {}).get("name", "").startswith("Acme")
          and c_row.get("recruiter") and c_row.get("consent_status") == "active" and c_row.get("stage") == "applied", c_row)
    app_id = c_row.get("application_id")
    s, live = get(f"/rest/v1/person_skills?select=id&work_identity_id=eq.{W['w1']}", tok["cli"])
    check("R4-014 a narrowed scope keeps the client on the snapshot (no live profile rows)", s == 200 and live == [], live)
    s, d = post("/rest/v1/candidate_submissions", {"consent_id": c1, "person_id": acc["w1"]["id"], "work_identity_id": W["w1"],
                "agency_id": agency, "client_id": st["client_id"], "job_order_id": jo1, "snapshot": {}}, tok["cli"])
    blocked("R4-007 the client manufactures a recruiter submission", s, d)
    s, d = patch(f"/rest/v1/candidate_submissions?id=eq.{sub1}", {"status": "hired"}, tok["rec"])
    blocked("the recruiter moves the submission status directly", s, d)
    rpc("omelo_mark_application_viewed", {"p_application_id": app_id}, tok["cli"])
    s, d = rpc("omelo_move_application", {"p_application_id": app_id, "p_state": "shortlisted"}, tok["cli"])
    check("the client shortlists", s == 200, f"{s} {msg(d)}")
    s, d = rpc("omelo_move_application", {"p_application_id": app_id, "p_state": "shortlisted"}, tok["rec"])
    blocked("the agency moves the client's pipeline", s, d)
    when = (dt.datetime.utcnow() + dt.timedelta(days=2)).replace(microsecond=0).isoformat() + "Z"
    s, iid = rpc("omelo_schedule_interview", {"p_application_id": app_id, "p_meeting_mode": "omelo_meet", "p_scheduled_at": when,
                 "p_duration_minutes": 30}, tok["cli"])
    check("the client schedules an Omelo Meet interview", s == 200 and isinstance(iid, str), f"{s} {msg(iid)}")
    rpc("omelo_confirm_interview", {"p_interview_id": iid}, tok["w1"])
    s, d = rpc("omelo_complete_interview", {"p_interview_id": iid, "p_outcome": "completed", "p_rating": 5,
               "p_recommendation": "strong_hire"}, tok["cli"])
    check("the interview is completed", s in (200, 204), f"{s} {msg(d)}")
    s, subs = rpc("omelo_agency_submissions", {"p_agency": agency}, tok["rec"])
    check("the agency sees the stage mirrored from the client's pipeline",
          next((x["status"] for x in subs if x["id"] == sub1), None) == "interview", subs)
    s, d = rpc("omelo_revoke_representation", {"p_consent": c1}, tok["w1"])
    blocked("revoking after the employer is considering the worker (withdraw the application instead)", s, d)
    start = (dt.date.today() + dt.timedelta(days=10)).isoformat()
    s, oid = rpc("omelo_send_offer", {"p_application_id": app_id, "p_pay_amount": 22000, "p_pay_period": "month",
                 "p_start_date": start}, tok["cli"])
    check("the client sends an offer", s == 200, f"{s} {msg(oid)}")
    s, res = rpc("omelo_respond_to_offer", {"p_offer_id": oid, "p_accept": True}, tok["w1"])
    check("the worker accepts the offer -> hired", s == 200 and res.get("status") == "accepted", f"{s} {msg(res)}")

    print("\n7. PLACEMENT")
    s, subs = rpc("omelo_agency_submissions", {"p_agency": agency}, tok["rec"])
    s1 = next((x for x in subs if x["id"] == sub1), {})
    pl = s1.get("placement") or {}
    check("a placement is created on hire", s1.get("status") == "hired" and pl.get("status") == "pending_start"
          and pl.get("start_date") == start, s1)
    s, d = rpc("omelo_update_placement", {"p_placement": pl.get("id"), "p_changes": {"status": "active", "fee_amount": 8000,
               "fee_currency": "INR"}}, tok["rec"])
    check("the recruiter starts the placement and records the fee", s in (200, 204), f"{s} {msg(d)}")
    s, d = rpc("omelo_update_placement", {"p_placement": pl.get("id"), "p_changes": {"status": "pending_start"}}, tok["rec"])
    blocked("moving a placement backwards", s, d)
    s, d = rpc("omelo_update_placement", {"p_placement": pl.get("id"), "p_changes": {"notes": "x"}}, tok["src"])
    blocked("a sourcer manages placements", s, d)
    s, ev = get(f"/rest/v1/candidate_submission_events?select=to_status&submission_id=eq.{sub1}&order=id", tok["rec"])
    check("R4-013 every submission transition is recorded",
          s == 200 and [e["to_status"] for e in ev][:1] == ["submitted"] and "hired" in [e["to_status"] for e in ev], ev)
    s, reps = rpc("omelo_my_representations", {}, tok["w1"])
    rep = next((x for x in reps if x["id"] == c1), {})
    check("the worker sees where they were submitted, and the placement",
          rep.get("status") == "active" and rep.get("submission", {}).get("status") == "hired" and rep.get("placement"), rep)

    print("\n8. REVOCATION, SCOPE AND OWNERSHIP")
    s, c2 = rpc("omelo_request_representation", {"p_job_order": jo2, "p_identity": W["w1"], "p_scope": ["identity", "skills"],
                "p_valid_days": 14}, tok["rec"])
    check("a second, narrower request (off-platform client)", s == 200, f"{s} {msg(c2)}")
    rpc("omelo_respond_to_representation", {"p_consent": c2, "p_accept": True}, tok["w1"])
    s, prof = rpc("omelo_consent_candidate", {"p_consent": c2}, tok["rec"])
    check("the recruiter sees only what was consented (identity + skills)", s == 200 and "skills" in prof
          and "experience" not in prof and "contact" not in prof, list(prof) if isinstance(prof, dict) else prof)
    s, d = rpc("omelo_consent_candidate", {"p_consent": c2}, tok["rogue"]); blocked("another agency reads the consented profile", s, d)
    s, d = rpc("omelo_revoke_representation", {"p_consent": c2, "p_reason": "Found work myself"}, tok["w1"])
    check("the worker revokes before any submission", s in (200, 204), f"{s} {msg(d)}")
    s, d = rpc("omelo_submit_candidate", {"p_consent": c2}, tok["rec"]); blocked("R4-004 submitting with a revoked consent", s, d)
    s, d = rpc("omelo_consent_candidate", {"p_consent": c2}, tok["rec"]); blocked("R4-011 reading the profile after revocation", s, d)
    s, d = rpc("omelo_request_representation", {"p_job_order": jo2, "p_identity": W["w1"]}, tok["rec"])
    check("the agency may ask again later (consent is per request, never ownership)", s == 200, f"{s} {msg(d)}")
    s, d = rpc("omelo_respond_to_representation", {"p_consent": d, "p_accept": False, "p_reason": "Not now"}, tok["w1"])
    check("the worker declines", s in (200, 204), f"{s} {msg(d)}")
    s, d = rpc("omelo_agency_candidates", {"p_agency": agency}, tok["rogue"]); blocked("another agency lists this agency's candidates", s, d)
    s, d = get(f"/rest/v1/candidate_consents?select=id&agency_id=eq.{agency}", tok["rogue"])
    check("R4-010 another agency reads none of the consents", s == 200 and d == [], d)
    s, d = get(f"/rest/v1/candidate_submissions?select=id&agency_id=eq.{agency}", tok["w2"])
    check("other workers read none of the submissions", s == 200 and d == [], d)
    s, d = patch(f"/rest/v1/work_identities?id=eq.{W['w1']}", {"headline": "hacked"}, tok["rec"])
    blocked("a recruiter edits the worker's identity", s, d)
    s, d = patch(f"/rest/v1/person_skills?work_identity_id=eq.{W['w1']}", {"is_verified": True}, tok["rec"])
    blocked("a recruiter verifies the worker's skills", s, d)

    print("\n9. DASHBOARD")
    s, dash = rpc("omelo_agency_dashboard", {"p_agency": agency}, tok["src"])
    check("dashboard: orders, requests, accepted, submissions, interviews, offers, placements",
          s == 200 and dash["active_job_orders"] >= 1 and dash["consent_requests"] >= 3 and dash["submissions"] == 1
          and dash["interviews"] == 1 and dash["offers"] == 1 and dash["placements"] == 1, dash)
    s, d = rpc("omelo_agency_dashboard", {"p_agency": agency}, tok["cli"]); blocked("the client reads the agency dashboard", s, d)

    os.remove(STATE)
    print(f"\n{'ALL PASSED' if not FAIL else str(len(FAIL)) + ' FAILED: ' + '; '.join(FAIL)}")


if __name__ == "__main__":
    {"setup": setup, "run": run}.get(sys.argv[1] if len(sys.argv) > 1 else "", lambda: print(__doc__))()
