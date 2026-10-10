"""Release 10: one organization model, as real users.

    python tests/api/organization_e2e.py setup   # accounts, two organizations, a client, a job order
    -- then, as Omelo, verify the probe organization (setup prints the SQL)
    python tests/api/organization_e2e.py run

Omelo has two entry options: a Personal Profile and an Organization Workspace.
Every organization gets the same core — a page, jobs, candidates, interviews,
hiring, posts, a team — and what kind of business it is only sets which
optional modules start switched on.

Nothing tested that, because until R10 it was not true. This suite covers the
two directions that were impossible or untested:

A. A private company recruits for a client. It has to turn the module on
   first, and once it does, every consent rule that used to apply only to
   agencies applies to it — which is a tightening, not a loosening.
B. A recruitment agency hires for itself, with no consent in sight, because
   its own hiring is not client work.
C. The business type is a description. It buys no visibility, no verification
   and no access, and it cannot be changed by a bare PATCH.

Creates five probe.* accounts; clean up as in hiring_loop_e2e.py.
"""
import json, os, sys, time
from omelo_api import *

STATE = os.path.join(os.path.dirname(__file__), ".organization_state.json")
PW = "ProbePass2026!"
FAIL = []


def check(label, ok, detail=""):
    print(f"  {'PASS' if ok else 'FAIL'} | {label}" + (f" | {detail}" if detail and not ok else ""))
    if not ok:
        FAIL.append(label)


def blocked(label, s, d):
    check(f"blocked: {label}", s >= 400 or (isinstance(d, list) and len(d) == 0), f"HTTP {s} {msg(d)}")


def prof(slug):
    return get(f"/rest/v1/professions?select=id&slug=eq.{slug}")[1][0]["id"]


def setup():
    stamp = str(int(time.time()))
    acc = {}
    print("\n0. ACCOUNTS")
    for key, name, role in [
        ("emp", "Priya Private Company", "employer"),
        ("emp2", "Dev Not An Admin", "employer"),
        ("cli", "Clara Client", "employer"),
        ("ag", "Asha Agency", "employer"),
        ("w1", "Ravi Worker", "worker"),
    ]:
        email = f"probe.o{key}.{stamp}@omelo.dev"
        _, pid = signup(email, PW, name, role)
        acc[key] = {"email": email, "id": pid}
    tok = {k: login(v["email"], PW)[0] for k, v in acc.items()}
    check("five accounts", all(v.get("id") for v in acc.values()))

    print("\n1. ONE SIGN-UP, WHATEVER THE BUSINESS")
    # The same function makes all of them. There is no agency sign-up any more.
    s, emp_co = rpc("omelo_create_organization",
                    {"p_name": f"Zippy Logistics {stamp}", "p_type": "employer"}, tok["emp"])
    check("a private company is created", s == 200 and isinstance(emp_co, str), f"{s} {msg(emp_co)}")
    s, cli_co = rpc("omelo_create_organization",
                    {"p_name": f"Fresh Foods {stamp}", "p_type": "employer"}, tok["cli"])
    check("a second company is created", s == 200, f"{s} {msg(cli_co)}")
    s, ag_co = rpc("omelo_create_organization",
                   {"p_name": f"Northline Recruiting {stamp}", "p_type": "recruitment_agency"}, tok["ag"])
    check("a recruitment firm is created through the same sign-up", s == 200, f"{s} {msg(ag_co)}")

    s, d = rpc("omelo_create_organization", {"p_name": "X", "p_type": "employer"}, tok["emp"])
    blocked("an organization name of one character", s, d)
    s, d = rpc("omelo_create_organization",
               {"p_name": f"Bogus {stamp}", "p_type": "pyramid_scheme"}, tok["emp"])
    blocked("an organization type Omelo does not have", s, d)

    s, d = get(f"/rest/v1/companies?select=organization_type,company_kind,is_verified&id=eq.{ag_co}", tok["ag"])
    check("declaring yourself a recruitment firm does not verify you",
          s == 200 and d and d[0]["organization_type"] == "recruitment_agency"
          and d[0]["is_verified"] is False, msg(d))

    print("\n2. THE TEAM VOCABULARY IS THE SAME EVERYWHERE")
    # 'sourcer' and 'coordinator' used to be refused outside an agency.
    for role in ("sourcer", "coordinator", "hiring_manager", "hr"):
        s, inv = rpc("omelo_invite_team_member",
                     {"p_company": emp_co, "p_email": acc["emp2"]["email"], "p_role": role}, tok["emp"])
        check(f"a private company may invite a {role.replace('_', ' ')}", s == 200, f"{s} {msg(inv)}")
    s, inv = rpc("omelo_invite_team_member",
                 {"p_company": emp_co, "p_email": acc["emp2"]["email"], "p_role": "sourcer"}, tok["emp"])
    rpc("omelo_accept_team_invitation", {"p_invitation": inv}, tok["emp2"])

    print("\n3. CLIENT RECRUITMENT IS OFF UNTIL YOU TURN IT ON")
    s, d = post("/rest/v1/agency_clients",
                {"agency_id": emp_co, "name": f"Fresh Foods {stamp}"}, tok["emp"])
    blocked("creating a client before the module is on", s, d)

    s, d = rpc("omelo_set_capability",
               {"p_company": emp_co, "p_capability": "client_recruitment", "p_enabled": True}, tok["emp2"])
    blocked("a sourcer turns on client recruitment", s, d)
    s, d = rpc("omelo_set_capability",
               {"p_company": emp_co, "p_capability": "world_domination", "p_enabled": True}, tok["emp"])
    blocked("a capability Omelo does not have", s, d)

    s, d = rpc("omelo_set_capability",
               {"p_company": emp_co, "p_capability": "client_recruitment", "p_enabled": True}, tok["emp"])
    check("the owner turns on client recruitment", s in (200, 204), f"{s} {msg(d)}")

    s, cl = post("/rest/v1/agency_clients", {"agency_id": emp_co, "name": f"Fresh Foods {stamp}"}, tok["emp"])
    check("now the private company can keep a client", s == 201, f"{s} {msg(cl)}")
    client_id = cl[0]["id"] if s == 201 else None

    print("\n4. THE CLIENT STILL HAS TO AGREE")
    s, d = rpc("omelo_request_client_link", {"p_client": client_id, "p_company": cli_co}, tok["emp"])
    check("ask the client company to confirm", s in (200, 204), f"{s} {msg(d)}")
    s, d = patch(f"/rest/v1/agency_clients?id=eq.{client_id}", {"link_status": "confirmed"}, tok["emp"])
    blocked("confirming on the client's behalf", s, d)
    s, d = rpc("omelo_respond_client_link", {"p_client": client_id, "p_accept": True}, tok["cli"])
    check("the client confirms", s in (200, 204), f"{s} {msg(d)}")

    print("\n5. A WORKER WHO CAN BE FOUND")
    s, wid = rpc("omelo_create_work_identity",
                 {"p_label": "Warehouse Associate", "p_profession_id": prof("warehouse-worker")}, tok["w1"])
    patch(f"/rest/v1/work_identities?id=eq.{wid}",
          {"discoverability": "discoverable", "headline": "Night-shift warehouse associate",
           "total_experience_months": 48, "allow_recruiter_requests": True}, tok["w1"])
    check("the worker makes one identity discoverable", s == 200, f"{s} {msg(wid)}")

    json.dump({"acc": acc, "emp_co": emp_co, "cli_co": cli_co, "ag_co": ag_co,
               "client_id": client_id, "identity": wid, "stamp": stamp},
              open(STATE, "w"))

    print(f"\nNow run as Omelo (fixture: verify probe organization {emp_co}):\n")
    print(f"  update companies set is_verified = true, verified_at = now(), "
          f"verification_method = 'manual_admin' where id in ('{emp_co}', '{ag_co}');")
    print(f"  update company_entitlements set talent_search_enabled = true "
          f"where company_id in ('{emp_co}', '{ag_co}');")
    print("\nthen: python tests/api/organization_e2e.py run")
    print(f"\n{'SETUP OK' if not FAIL else str(len(FAIL)) + ' FAILED: ' + '; '.join(FAIL)}")


def run():
    st = json.load(open(STATE))
    acc, stamp = st["acc"], st["stamp"]
    tok = {k: login(v["email"], PW)[0] for k, v in acc.items()}
    emp_co, ag_co, wid = st["emp_co"], st["ag_co"], st["identity"]
    cli_co, client_id = st["cli_co"], st["client_id"]

    print("\nA. A PRIVATE COMPANY RECRUITS FOR A CLIENT")
    _, loc = get("/rest/v1/locations?select=id&latitude=not.is.null&country_code=eq.IN&limit=1")
    order = {"title": "Night warehouse picker", "profession_id": prof("warehouse-worker"),
             "openings": 4, "location_id": loc[0]["id"], "location_text": "Delhi",
             "work_type": "full_time", "pay_min": 22000, "pay_max": 22000,
             "pay_period": "month", "pay_currency": "INR"}
    s, jo = rpc("omelo_create_job_order", {"p_client": client_id, "p_order": order}, tok["emp"])
    check("a private company opens a job order for its client",
          s == 200 and isinstance(jo, str), f"{s} {msg(jo)}")

    s, r = rpc("omelo_search_talent_for_order", {"p_job_order": jo, "p_filters": {"radius_km": 200}}, tok["emp"])
    ids = [x["work_identity_id"] for x in r.get("results", [])] if s == 200 else []
    check("it searches for its client's order", s == 200, f"{s} {msg(r)}")
    check("a discoverable worker is found — the same rule an agency gets", wid in ids, ids)

    s, c1 = rpc("omelo_request_representation", {"p_job_order": jo, "p_identity": wid}, tok["emp"])
    check("it asks the worker for consent", s == 200 and isinstance(c1, str), f"{s} {msg(c1)}")
    s, d = rpc("omelo_submit_candidate", {"p_consent": c1}, tok["emp"])
    blocked("R4-001 submitting before the worker accepts", s, d)
    s, d = rpc("omelo_respond_to_representation", {"p_consent": c1, "p_accept": True}, tok["emp"])
    blocked("R4-008 the company accepts on the worker's behalf", s, d)

    s, d = rpc("omelo_respond_to_representation", {"p_consent": c1, "p_accept": True}, tok["w1"])
    check("the worker accepts", s in (200, 204), f"{s} {msg(d)}")
    s, sub = rpc("omelo_submit_candidate", {"p_consent": c1}, tok["emp"])
    check("the private company submits its candidate to the client", s == 200, f"{s} {msg(sub)}")

    print("\nB. CONSENT BINDS WHOEVER DOES CLIENT WORK")
    # R5-002 used to read `company_kind = 'agency'`, so this company would have
    # walked straight past it. It asks about the client now.
    s, req = rpc("omelo_create_requirement",
                 {"p_company": emp_co, "p_fields": {"job_order_id": jo}}, tok["emp"])
    check("a requirement for the client's order", s == 200 and isinstance(req, str), f"{s} {msg(req)}")
    s, d = rpc("omelo_offer_assignment", {"p_requirement": req, "p_identity": wid}, tok["emp"])
    check("the represented worker can be assigned", s == 200, f"{s} {msg(d)}")

    print("\nC. AN AGENCY HIRES FOR ITSELF")
    s, loc = get("/rest/v1/locations?select=id&latitude=not.is.null&country_code=eq.IN&limit=1")
    s, job = post("/rest/v1/jobs",
                  {"company_id": ag_co, "created_by": acc["ag"]["id"], "title": f"Recruiter {stamp}",
                   "profession_id": prof("warehouse-worker"), "location_id": loc[0]["id"],
                   "workplace_type": "onsite", "work_type": "full_time", "pay_min": 40000,
                   "pay_max": 60000, "pay_period": "month", "pay_currency": "INR",
                   "accepts_no_experience": True, "status": "draft"}, tok["ag"])
    check("a recruitment firm posts its own job", s == 201, f"{s} {msg(job)}")
    if s == 201:
        s, d = patch(f"/rest/v1/jobs?id=eq.{job[0]['id']}", {"status": "published"}, tok["ag"])
        check("and publishes it, with no job order in sight", s == 200, f"{s} {msg(d)}")

    print("\nD. THE TYPE IS A DESCRIPTION, NOT A KEY")
    s, d = patch(f"/rest/v1/companies?id=eq.{emp_co}", {"organization_type": "rpo_provider"}, tok["emp"])
    blocked("reclassifying the organization with a bare PATCH", s, d)
    s, d = patch(f"/rest/v1/companies?id=eq.{cli_co}", {"company_kind": "agency"}, tok["cli"])
    blocked("setting company_kind directly", s, d)
    s, d = patch(f"/rest/v1/companies?id=eq.{cli_co}", {"is_verified": True}, tok["cli"])
    blocked("self-verifying an unverified organization", s, d)
    s, d = rpc("omelo_set_organization_type", {"p_company": emp_co, "p_type": "recruitment_agency"}, tok["emp2"])
    blocked("a sourcer changes the organization type", s, d)
    s, d = rpc("omelo_set_organization_type", {"p_company": emp_co, "p_type": "recruitment_agency"}, tok["emp"])
    check("the owner reclassifies the business", s in (200, 204), f"{s} {msg(d)}")
    s, d = get(f"/rest/v1/companies?select=organization_type,is_verified&id=eq.{emp_co}", tok["emp"])
    check("the type changed and the verification did not",
          s == 200 and d and d[0]["organization_type"] == "recruitment_agency"
          and d[0]["is_verified"] is True, msg(d))

    print("\nE. THE RETIRED VISIBILITY LEVEL")
    s, d = patch(f"/rest/v1/work_identities?id=eq.{wid}", {"discoverability": "recruiters"}, tok["w1"])
    blocked("R10-005 setting the retired 'recruiters' visibility", s, d)

    print(f"\n{'ALL PASSED' if not FAIL else str(len(FAIL)) + ' FAILED: ' + '; '.join(FAIL)}")


{"setup": setup, "run": run}.get(sys.argv[1] if len(sys.argv) > 1 else "", lambda: print(__doc__))()
