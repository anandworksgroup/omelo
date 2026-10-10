"""Release 8: enterprise organizations, approval workflows and RPO, as real users.

    python tests/api/enterprise_e2e.py

Acme (a client organization) has two business units, two departments and a recruiter scoped to
Engineering only. Its jobs need Hiring manager and Finance approval before they go live. An RPO
provider is engaged for Engineering alone: its recruiter works Acme's Engineering pipeline and
nothing else.

Chain proven end to end: organization → structure → roles → scoped permissions → approval workflow
→ recruiting → RPO engagement → RPO recruiter → client jobs → candidates → interview → offer.
Attacks R8-001 .. R8-008: organization isolation, department isolation, RPO isolation, RPO scope,
worker privacy and financial privacy. Creates seven probe.* accounts (single phase).
"""
import datetime as dt, json, sys, time
from omelo_api import *

PW = "ProbePass2026!"
FAIL = []
def check(label, ok, detail=""):
    print(f"  {'PASS' if ok else 'FAIL'} | {label}" + (f" | {detail}" if detail and not ok else ""))
    if not ok: FAIL.append(label)
def blocked(label, s, d):
    check(f"blocked: {label}", s >= 400 or (isinstance(d, list) and len(d) == 0), f"HTTP {s} {msg(d)}")
def prof(slug):
    return get(f"/rest/v1/professions?select=id&slug=eq.{slug}")[1][0]["id"]


def main():
    stamp = str(int(time.time()))
    acc, tok = {}, {}
    for key, name, role in [("own", "Ayesha Owner", "employer"), ("hm", "Hari Manager", "employer"),
                            ("fin", "Farah Finance", "employer"), ("rec", "Raj Recruiter", "employer"),
                            ("rpo", "Rita RPO", "employer"), ("rrec", "Rohan RPO Recruiter", "employer"),
                            ("w1", "Wasim Worker", "worker")]:
        email = f"probe.e{key}.{stamp}@omelo.dev"
        tok[key], pid = signup(email, PW, name, role)
        acc[key] = {"email": email, "id": pid}
    eng_prof, wh_prof = prof("electrical-engineer"), prof("warehouse-worker")

    print("\n1. ENTERPRISE STRUCTURE")
    s, slug = rpc("omelo_company_slug", {"p_name": f"Acme Corporation {stamp}"}, tok["own"])
    s, co = post("/rest/v1/companies", {"slug": slug, "display_name": f"Acme Corporation {stamp}", "country_code": "IN",
                 "size_band": "1001-5000", "created_by": acc["own"]["id"]}, tok["own"])
    if s != 201: raise SystemExit(f"company: {s} {msg(co)}")
    acme = co[0]["id"]
    s, d = get(f"/rest/v1/companies?select=organization_type,company_kind&id=eq.{acme}", tok["own"])
    check("an organization is created as an employer", d and d[0]["organization_type"] == "employer"
          and d[0]["company_kind"] == "employer", d)
    s, bu = post("/rest/v1/business_units", [{"company_id": acme, "name": "Technology"},
                 {"company_id": acme, "name": "Operations"}], tok["own"])
    check("business units created", s == 201 and len(bu) == 2, f"{s} {msg(bu)}")
    tech = next(b["id"] for b in bu if b["name"] == "Technology")
    ops = next(b["id"] for b in bu if b["name"] == "Operations")
    s, dep = post("/rest/v1/departments", [{"company_id": acme, "name": "Engineering", "business_unit_id": tech},
                  {"company_id": acme, "name": "Warehouse", "business_unit_id": ops}], tok["own"])
    check("departments sit under their business unit", s == 201 and len(dep) == 2, f"{s} {msg(dep)}")
    engineering = next(x["id"] for x in dep if x["name"] == "Engineering")
    warehouse = next(x["id"] for x in dep if x["name"] == "Warehouse")
    s, loc = get("/rest/v1/locations?select=id&latitude=not.is.null&country_code=eq.IN&kind=eq.city&limit=2")
    s, cl = post("/rest/v1/company_locations", [{"company_id": acme, "location_id": loc[0]["id"], "name": "Delhi site"}], tok["own"])
    check("a company location is added", s == 201, f"{s} {msg(cl)}")
    s, tm = post("/rest/v1/teams", {"company_id": acme, "name": "Engineering hiring", "business_unit_id": tech,
                 "department_id": engineering, "purpose": "hiring", "lead_person_id": acc["own"]["id"]}, tok["own"])
    check("a hiring team is created", s == 201, f"{s} {msg(tm)}")
    s, d = post("/rest/v1/business_units", {"company_id": acme, "name": "Sneaky unit"}, tok["w1"])
    blocked("an outsider adds a business unit", s, d)
    s, d = get(f"/rest/v1/business_units?select=id&company_id=eq.{acme}", tok["w1"])
    blocked("R8-007 an outsider reads the structure", s, d)

    print("\n2. ROLES AND SCOPE (WHO / WHAT / WHERE)")
    for key, role in (("hm", "hiring_manager"), ("fin", "finance"), ("rec", "recruiter")):
        s, inv = rpc("omelo_invite_team_member", {"p_company": acme, "p_email": acc[key]["email"], "p_role": role}, tok["own"])
        s2, d = rpc("omelo_accept_team_invitation", {"p_invitation": inv}, tok[key])
        check(f"{role} joins the organization", s == 200 and s2 in (200, 204), f"{s}/{s2} {msg(d)}")
    s, d = patch(f"/rest/v1/company_members?company_id=eq.{acme}&person_id=eq.{acc['rec']['id']}",
                 {"scope_mode": "scoped"}, tok["own"])
    check("the recruiter is marked as scoped", s == 200 and d and d[0]["scope_mode"] == "scoped", f"{s} {msg(d)}")
    s, g = post("/rest/v1/company_role_grants", {"company_id": acme, "person_id": acc["rec"]["id"], "role": "recruiter",
                "scope_type": "department", "scope_id": engineering, "granted_by": acc["own"]["id"]}, tok["own"])
    check("…and granted Recruiter for Engineering only", s == 201, f"{s} {msg(g)}")
    s, d = post("/rest/v1/company_role_grants", {"company_id": acme, "person_id": acc["w1"]["id"], "role": "recruiter",
                "scope_type": "department", "scope_id": engineering}, tok["own"])
    blocked("granting a role to someone who is not on the team", s, d)
    s, d = post("/rest/v1/company_role_grants", {"company_id": acme, "person_id": acc["rec"]["id"], "role": "owner",
                "scope_type": "organization"}, tok["rec"])
    blocked("a recruiter grants themselves organization-wide ownership", s, d)

    def make_job(title, department, profession, token, status="draft"):
        return post("/rest/v1/jobs", {"company_id": acme, "created_by": acc["own"]["id"], "title": title,
                    "profession_id": profession, "department_id": department, "location_id": loc[0]["id"],
                    "workplace_type": "onsite", "work_type": "full_time", "country_code": "IN",
                    "pay_min": 60000, "pay_max": 80000, "pay_period": "month", "pay_currency": "INR",
                    "status": status}, token)
    s, j = make_job("Electrical Engineer (Engineering)", engineering, eng_prof, tok["rec"])
    check("R8-002 the scoped recruiter creates a job in their department", s == 201, f"{s} {msg(j)}")
    eng_job = j[0]["id"] if s == 201 else None
    post("/rest/v1/job_stages", [{"job_id": eng_job, "name": "New", "position": 1, "maps_to_state": "applied", "is_terminal": False}], tok["own"])
    s, d = make_job("Warehouse Associate (Operations)", warehouse, wh_prof, tok["rec"])
    blocked("R8-002 the same recruiter creates a job in another department", s, d)
    s, j2 = make_job("Warehouse Associate (Operations)", warehouse, wh_prof, tok["own"])
    check("the owner creates the Warehouse job (organization-wide)", s == 201, f"{s} {msg(j2)}")
    wh_job = j2[0]["id"] if s == 201 else None
    post("/rest/v1/job_stages", [{"job_id": wh_job, "name": "New", "position": 1, "maps_to_state": "applied", "is_terminal": False}], tok["own"])
    s, d = patch(f"/rest/v1/jobs?id=eq.{wh_job}", {"title": "Hijacked"}, tok["rec"])
    blocked("R8-002 the Engineering recruiter edits a Warehouse job", s, d)

    print("\n3. APPROVAL WORKFLOW")
    s, wf = rpc("omelo_save_approval_workflow", {"p": {"company_id": acme, "entity_type": "job", "name": "Hiring approval",
                "steps": [{"name": "Department approval", "approver_role": "hiring_manager", "approver_scope": "department"},
                          {"name": "Finance approval", "approver_role": "finance"}]}}, tok["own"])
    check("the organization defines its own approval chain", s == 200 and wf.get("id"), f"{s} {msg(wf)}")
    s, d = rpc("omelo_save_approval_workflow", {"p": {"company_id": acme, "entity_type": "job", "name": "Rogue",
               "steps": [{"name": "Me", "approver_role": "recruiter"}]}}, tok["rec"])
    blocked("a recruiter rewrites the approval chain", s, d)
    s, d = patch(f"/rest/v1/jobs?id=eq.{eng_job}", {"status": "published"}, tok["rec"])
    blocked("R8-004 publishing before approval", s, d)
    s, req = rpc("omelo_submit_for_approval", {"p_entity_type": "job", "p_entity_id": eng_job,
                 "p_note": "Backfill for the controls team"}, tok["rec"])
    check("the recruiter submits the job for approval", s == 200 and req.get("status") == "pending", f"{s} {msg(req)}")
    request_id = req.get("id") if s == 200 else None
    s, d = rpc("omelo_decide_approval", {"p_request": request_id, "p_approve": True}, tok["rec"])
    blocked("R8-003 approving your own request", s, d)
    s, d = rpc("omelo_decide_approval", {"p_request": request_id, "p_approve": True}, tok["fin"])
    blocked("R8-003 the wrong role approving the first step", s, d)
    s, d = rpc("omelo_decide_approval", {"p_request": request_id, "p_approve": True}, tok["w1"])
    blocked("an outsider approving", s, d)
    s, mine = rpc("omelo_my_approvals", {"p_company": acme}, tok["hm"])
    check("the hiring manager sees it waiting", s == 200 and any(x["request_id"] == request_id for x in mine), f"{s} {msg(mine)}")
    s, d = rpc("omelo_decide_approval", {"p_request": request_id, "p_approve": True, "p_note": "Needed"}, tok["hm"])
    check("step 1 approved; it moves to Finance", s == 200 and d.get("status") == "pending" and d.get("position") == 2, f"{s} {msg(d)}")
    s, d = patch(f"/rest/v1/jobs?id=eq.{eng_job}", {"status": "published"}, tok["rec"])
    blocked("publishing while Finance has not approved", s, d)
    s, d = rpc("omelo_decide_approval", {"p_request": request_id, "p_approve": True}, tok["fin"])
    check("Finance approves; the request is approved", s == 200 and d.get("status") == "approved", f"{s} {msg(d)}")
    s, d = patch(f"/rest/v1/jobs?id=eq.{eng_job}", {"status": "published"}, tok["rec"])
    check("now the job publishes", s == 200 and d and d[0]["status"] == "published", f"{s} {msg(d)}")
    s, st = rpc("omelo_approval_status", {"p_entity_type": "job", "p_entity_id": eng_job}, tok["own"])
    check("the trail shows both decisions", s == 200 and st["required"] is True
          and len(st["request"]["decisions"]) == 2, f"{s} {msg(st)}")
    s, d = post("/rest/v1/approval_decisions", {"request_id": request_id, "position": 1, "decided_by": acc["rec"]["id"],
                "decision": "approved"}, tok["rec"])
    blocked("R8-003 writing a decision directly", s, d)

    print("\n4. RPO ENGAGEMENT")
    # R10: one organization sign-up for every business. The suite used to insert
    # the company row with organization_type set, which slipped past the guard
    # that was meant to stop it (migration 79 closed that, and removed the
    # refusal deliberately, since the type grants nothing). It goes through the
    # supported sign-up now.
    s, provider = rpc("omelo_create_organization",
                      {"p_name": f"TalentWorks RPO {stamp}", "p_type": "rpo_provider"}, tok["rpo"])
    check("an RPO provider organization is created through the one sign-up",
          s == 200 and isinstance(provider, str), f"{s} {msg(provider)}")
    s, rco = get(f"/rest/v1/companies?select=organization_type,is_verified&id=eq.{provider}", tok["rpo"])
    check("it is an rpo_provider, and unverified like any new organization",
          s == 200 and rco and rco[0]["organization_type"] == "rpo_provider"
          and rco[0]["is_verified"] is False, msg(rco))
    s, inv = rpc("omelo_invite_team_member", {"p_company": provider, "p_email": acc["rrec"]["email"], "p_role": "recruiter"}, tok["rpo"])
    rpc("omelo_accept_team_invitation", {"p_invitation": inv}, tok["rrec"])
    s, eng = rpc("omelo_create_rpo_engagement", {"p": {"provider_id": provider, "client_company_id": acme,
                 "title": "Engineering hiring 2026", "permissions": ["view_jobs", "view_candidates", "move_candidates",
                 "schedule_interviews"]}}, tok["rpo"])
    check("the provider drafts an engagement with the client", s == 200 and eng.get("status") == "draft", f"{s} {msg(eng)}")
    engagement = eng.get("id") if s == 200 else None
    s, d = rpc("omelo_create_rpo_engagement", {"p": {"provider_id": provider, "client_company_id": acme, "title": "x",
               "permissions": ["own_everything"]}}, tok["rpo"]); blocked("an unknown permission", s, d)
    s, d = rpc("omelo_set_rpo_scope", {"p_engagement": engagement, "p_scope_type": "department", "p_scope_id": engineering}, tok["rpo"])
    check("scope: Engineering only", s == 200 and any(x["scope_id"] == engineering for x in d), f"{s} {msg(d)}")
    s, d = rpc("omelo_set_rpo_scope", {"p_engagement": engagement, "p_scope_type": "department", "p_scope_id": warehouse}, tok["rrec"])
    blocked("an RPO recruiter widening their own scope", s, d)
    s, d = rpc("omelo_assign_rpo_recruiter", {"p_engagement": engagement, "p_person": acc["rrec"]["id"]}, tok["rpo"])
    check("the provider assigns its recruiter", s == 200, f"{s} {msg(d)}")
    s, d = rpc("omelo_assign_rpo_recruiter", {"p_engagement": engagement, "p_person": acc["w1"]["id"]}, tok["rpo"])
    blocked("assigning someone who is not on the provider's team", s, d)
    s, d = rpc("omelo_rpo_my_work", {}, tok["rrec"])
    check("before the client confirms, the recruiter has no work", s == 200 and d == [], f"{s} {msg(d)}")
    s, d = rpc("omelo_propose_rpo_engagement", {"p_engagement": engagement}, tok["rpo"])
    check("the provider proposes it", s == 200 and d.get("status") == "pending_approval", f"{s} {msg(d)}")
    s, d = rpc("omelo_respond_rpo_engagement", {"p_engagement": engagement, "p_accept": True}, tok["rpo"])
    blocked("the provider accepting on the client's behalf", s, d)
    s, d = rpc("omelo_respond_rpo_engagement", {"p_engagement": engagement, "p_accept": True}, tok["own"])
    check("R8-005 the client confirms; the engagement is active", s == 200 and d.get("status") == "active", f"{s} {msg(d)}")

    print("\n5. RPO RECRUITER SEES ONLY WHAT THE ENGAGEMENT AUTHORIZES")
    s, wid = rpc("omelo_create_work_identity", {"p_label": "Electrical Engineer", "p_profession_id": eng_prof}, tok["w1"])
    s, app = post("/rest/v1/applications", {"job_id": eng_job, "person_id": acc["w1"]["id"], "company_id": acme,
                  "work_identity_id": wid, "identity_snapshot": {}}, tok["w1"])
    check("a worker applies to the Engineering job", s == 201, f"{s} {msg(app)}")
    app_id = app[0]["id"] if s == 201 else None
    s, work = rpc("omelo_rpo_my_work", {}, tok["rrec"])
    ids = {x["job_id"] for x in work} if s == 200 else set()
    check("the RPO recruiter sees the Engineering job", s == 200 and eng_job in ids, f"{s} {msg(work)}")
    check("R8-006 …and not the Warehouse job", wh_job not in ids, list(ids))
    s, d = get(f"/rest/v1/applications?select=id,state&job_id=eq.{eng_job}", tok["rrec"])
    check("…can work the candidates of that job", s == 200 and d and d[0]["id"] == app_id, f"{s} {msg(d)}")
    s, d = get(f"/rest/v1/applications?select=id&job_id=eq.{wh_job}", tok["rrec"])
    blocked("R8-006 candidates of a job outside the scope", s, d)
    s, d = rpc("omelo_move_application", {"p_application_id": app_id, "p_state": "shortlisted"}, tok["rrec"])
    check("…and moves the candidate in the client's pipeline", s in (200, 204), f"{s} {msg(d)}")
    s, d = get(f"/rest/v1/applications?select=id&job_id=eq.{eng_job}", tok["rpo"])
    blocked("R8-006 a provider owner who is not assigned to the engagement", s, d)
    s, d = get(f"/rest/v1/rpo_engagements?select=id&id=eq.{engagement}", tok["w1"])
    blocked("an outsider reads the engagement", s, d)
    s, d = get(f"/rest/v1/departments?select=id&company_id=eq.{acme}", tok["rrec"])
    blocked("R8-007 the RPO recruiter browses the client's internal structure", s, d)
    s, d = get(f"/rest/v1/company_members?select=id&company_id=eq.{acme}", tok["rrec"])
    blocked("R8-007 …or the client's team list", s, d)

    print("\n6. WORKER AND MONEY PRIVACY UNDER RPO")
    s, d = get(f"/rest/v1/mobility_profiles?select=*&person_id=eq.{acc['w1']['id']}", tok["rrec"])
    blocked("the RPO recruiter reads the worker's mobility profile", s, d)
    s, d = get(f"/rest/v1/work_authorizations?select=*&person_id=eq.{acc['w1']['id']}", tok["rrec"])
    blocked("…the worker's authorization records", s, d)
    s, d = get(f"/rest/v1/documents?select=id&person_id=eq.{acc['w1']['id']}", tok["rrec"])
    blocked("…the worker's documents", s, d)
    s, d = get("/rest/v1/earnings?select=id&limit=1", tok["rrec"])
    blocked("R8-008 …worker pay", s, d)
    s, d = get("/rest/v1/assignment_billing?select=id&limit=1", tok["rrec"])
    blocked("R8-008 …agency or client billing", s, d)
    s, d = get("/rest/v1/earnings?select=id&limit=1"); blocked("R8-008 the public reads pay", s, d)

    print("\n7. INTERVIEW AND OFFER THROUGH THE RPO RECRUITER")
    when = (dt.datetime.now(dt.timezone.utc) + dt.timedelta(days=3)).replace(microsecond=0).isoformat().replace("+00:00", "Z")
    s, d = rpc("omelo_schedule_interview", {"p_application_id": app_id, "p_scheduled_at": when,
               "p_duration_minutes": 30, "p_meeting_mode": "in_person", "p_location_text": "Delhi site, gate 2",
               "p_interviewer_ids": [acc["rrec"]["id"]]}, tok["rrec"])
    blocked("the RPO recruiter puts themselves on the client's interview panel", s, d)
    s, iv = rpc("omelo_schedule_interview", {"p_application_id": app_id, "p_scheduled_at": when,
                "p_duration_minutes": 30, "p_meeting_mode": "in_person",
                "p_location_text": "Delhi site, gate 2", "p_interviewer_ids": [acc["hm"]["id"]]}, tok["rrec"])
    check("the RPO recruiter schedules the interview with the client's own interviewer", s == 200, f"{s} {msg(iv)}")
    start = (dt.date.today() + dt.timedelta(days=30)).isoformat()
    s, oid = rpc("omelo_send_offer", {"p_application_id": app_id, "p_pay_amount": 70000, "p_pay_period": "month",
                 "p_start_date": start}, tok["rec"])
    check("the client's own recruiter sends the offer", s == 200, f"{s} {msg(oid)}")
    s, res = rpc("omelo_respond_to_offer", {"p_offer_id": oid, "p_accept": True}, tok["w1"])
    check("the worker accepts: hired through the RPO-run pipeline", s == 200 and res.get("employment_id"), f"{s} {msg(res)}")

    print("\n8. ENGAGEMENT LIFECYCLE")
    s, d = rpc("omelo_set_rpo_status", {"p_engagement": engagement, "p_status": "paused"}, tok["own"])
    check("the client pauses the engagement", s == 200 and d.get("status") == "paused", f"{s} {msg(d)}")
    s, d = rpc("omelo_rpo_my_work", {}, tok["rrec"])
    check("…the recruiter's access stops at once", s == 200 and d == [], f"{s} {msg(d)}")
    s, d = get(f"/rest/v1/applications?select=id&job_id=eq.{eng_job}", tok["rrec"])
    blocked("…including the candidates", s, d)
    s, d = rpc("omelo_set_rpo_status", {"p_engagement": engagement, "p_status": "active"}, tok["rpo"])
    check("either side can resume it", s == 200 and d.get("status") == "active", f"{s} {msg(d)}")
    s, d = rpc("omelo_set_rpo_status", {"p_engagement": engagement, "p_status": "terminated"}, tok["own"])
    check("the client ends it", s == 200 and d.get("status") == "terminated", f"{s} {msg(d)}")
    s, d = get(f"/rest/v1/applications?select=id&job_id=eq.{eng_job}", tok["rrec"])
    blocked("after it ends, no access remains", s, d)
    s, d = rpc("omelo_set_rpo_status", {"p_engagement": engagement, "p_status": "active"}, tok["own"])
    blocked("reviving a terminated engagement", s, d)
    s, mine = rpc("omelo_rpo_engagements", {"p_company": provider}, tok["rpo"])
    check("the provider sees its engagement with scope and recruiters",
          s == 200 and mine and mine[0]["side"] == "provider" and mine[0]["scopes"] and mine[0]["recruiters"], f"{s} {msg(mine)}")
    s, d = rpc("omelo_rpo_engagements", {"p_company": acme}, tok["w1"])
    blocked("an outsider lists a company's engagements", s, d)

    print(f"\n{'ALL PASSED' if not FAIL else str(len(FAIL)) + ' FAILED: ' + '; '.join(FAIL)}")
    sys.exit(1 if FAIL else 0)


if __name__ == "__main__":
    main()
