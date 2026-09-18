"""Release 5: staffing & workforce engine, as real users.

    python tests/api/staffing_e2e.py setup   # accounts, agency, confirmed client, job order, employer + job
    -- then, as Omelo, verify the probe agency and enable talent search (setup prints the SQL)
    python tests/api/staffing_e2e.py run     # needs ~2 minutes: waits for the scheduler to run a bulk job

A. Agency staffing lifecycle: consent -> requirement -> assignment offer ->
   worker accepts -> shifts -> check-in (late) / check-out -> client reviews
   attendance (reject one, supervisor records another) -> timesheet ->
   client approves -> earnings (base + overtime policy + night allowance) ->
   agency approves -> payment (within the approved amount) -> billing to the
   client; the worker never sees the bill rate, the client never sees pay.
B. Direct employer workforce: applicant -> requirement -> assignment -> shifts
   -> conflict detection -> cancelled shift -> completion -> verified experience.
C. Attacks R5-001 .. R5-016 as the users who would try them; bulk operation
   re-checks authority per item. Creates six probe.* accounts.
"""
import datetime as dt, json, os, sys, time
from omelo_api import *

STATE = os.path.join(os.path.dirname(__file__), ".staffing_state.json")
PW = "ProbePass2026!"
FAIL = []
def check(label, ok, detail=""):
    print(f"  {'PASS' if ok else 'FAIL'} | {label}" + (f" | {detail}" if detail and not ok else ""))
    if not ok: FAIL.append(label)
def blocked(label, s, d):
    check(f"blocked: {label}", s >= 400 or (isinstance(d, list) and len(d) == 0), f"HTTP {s} {msg(d)}")
def prof(slug):
    return get(f"/rest/v1/professions?select=id&slug=eq.{slug}")[1][0]["id"]
def iso(t):
    return t.replace(microsecond=0).isoformat().replace("+00:00", "Z")
UTC = dt.timezone.utc


def setup():
    stamp = str(int(time.time()))
    acc = {}
    for key, name, role in [("rec", "Asha Staffing", "employer"), ("cli", "Carl Client", "employer"),
                            ("emp", "Esha Employer", "employer"), ("w1", "Ravi Worker", "worker"),
                            ("w2", "Meena Worker", "worker"), ("x", "Rogue Outsider", "employer")]:
        email = f"probe.s{key}.{stamp}@omelo.dev"
        _, pid = signup(email, PW, name, role)
        acc[key] = {"email": email, "id": pid}
    tok = {k: login(v["email"], PW)[0] for k, v in acc.items()}
    s, loc = get("/rest/v1/locations?select=id&latitude=not.is.null&country_code=eq.IN&limit=1")
    loc_id = loc[0]["id"]; wh = prof("warehouse-worker")
    for k, vis in [("w1", "recruiters"), ("w2", "discoverable")]:
        s, wid = rpc("omelo_create_work_identity", {"p_label": "Warehouse Associate", "p_profession_id": wh}, tok[k])
        patch(f"/rest/v1/work_identities?id=eq.{wid}", {"discoverability": vis}, tok[k])
        acc[k]["identity"] = wid
    s, agency = rpc("omelo_create_agency", {"p_name": f"Shift Staffing {stamp}"}, tok["rec"])
    s, slug = rpc("omelo_company_slug", {"p_name": f"ABC Warehousing {stamp}"}, tok["cli"])
    s, co = post("/rest/v1/companies", {"slug": slug, "display_name": f"ABC Warehousing {stamp}", "country_code": "IN",
                 "size_band": "51-200", "created_by": acc["cli"]["id"]}, tok["cli"]); client_company = co[0]["id"]
    s, cl = post("/rest/v1/agency_clients", {"agency_id": agency, "name": "ABC Warehousing", "relationship_status": "active"}, tok["rec"])
    client_id = cl[0]["id"]
    rpc("omelo_request_client_link", {"p_client": client_id, "p_company": client_company}, tok["rec"])
    rpc("omelo_respond_client_link", {"p_client": client_id, "p_accept": True}, tok["cli"])
    s, jo = rpc("omelo_create_job_order", {"p_client": client_id, "p_order": {"title": "Night Warehouse Associate",
                "profession_id": wh, "openings": 150, "location_id": loc_id, "location_text": "Delhi NCR",
                "pay_min": 150, "pay_max": 150, "pay_period": "hour", "pay_currency": "INR", "shift_types": ["night"]}}, tok["rec"])
    check("agency, confirmed client and job order set up", s == 200, f"{s} {msg(jo)}")
    # direct employer
    s, slug = rpc("omelo_company_slug", {"p_name": f"Direct Foods {stamp}"}, tok["emp"])
    s, co = post("/rest/v1/companies", {"slug": slug, "display_name": f"Direct Foods {stamp}", "country_code": "IN",
                 "size_band": "11-50", "created_by": acc["emp"]["id"]}, tok["emp"]); emp_company = co[0]["id"]
    s, job = post("/rest/v1/jobs", {"company_id": emp_company, "created_by": acc["emp"]["id"], "title": "Packer (daily wage)",
                  "profession_id": prof("packer"), "location_id": loc_id, "workplace_type": "onsite", "work_type": "daily_wage",
                  "pay_min": 800, "pay_max": 800, "pay_period": "day", "pay_currency": "INR", "accepts_no_experience": True,
                  "status": "draft"}, tok["emp"])
    job_id = job[0]["id"]
    post("/rest/v1/job_stages", [{"job_id": job_id, "name": "New", "position": 1, "maps_to_state": "applied", "is_terminal": False}], tok["emp"])
    patch(f"/rest/v1/jobs?id=eq.{job_id}", {"status": "published"}, tok["emp"])
    s, app = post("/rest/v1/applications", {"job_id": job_id, "person_id": acc["w2"]["id"], "company_id": emp_company,
                  "work_identity_id": acc["w2"]["identity"], "identity_snapshot": {}}, tok["w2"])
    check("a worker applies to the direct employer", s == 201, f"{s} {msg(app)}")
    st = dict(acc=acc, agency=agency, client_company=client_company, client_id=client_id, job_order=jo,
              emp_company=emp_company, job_id=job_id, loc=loc_id)
    json.dump(st, open(STATE, "w"))
    print(f"\nNow run as Omelo (fixture: verify probe agency {agency}):\n")
    print(f"  update companies set is_verified = true, verified_at = now(), verification_method = 'manual_admin' where id = '{agency}';")
    print(f"  update company_entitlements set talent_search_enabled = true where company_id = '{agency}';")
    print("\nthen: python tests/api/staffing_e2e.py run")
    print(f"\n{'SETUP OK' if not FAIL else str(len(FAIL)) + ' FAILED: ' + '; '.join(FAIL)}")


def run():
    st = json.load(open(STATE)); acc = st["acc"]
    tok = {k: login(v["email"], PW)[0] for k, v in acc.items()}
    agency, jo = st["agency"], st["job_order"]
    now = dt.datetime.now(UTC); start_day = (now - dt.timedelta(days=2)).date().isoformat()
    end_day = (now + dt.timedelta(days=90)).date().isoformat()

    print("\nA1. REQUIREMENT AND ASSIGNMENT (agency)")
    s, c1 = rpc("omelo_request_representation", {"p_job_order": jo, "p_identity": acc["w1"]["identity"]}, tok["rec"])
    rpc("omelo_respond_to_representation", {"p_consent": c1, "p_accept": True}, tok["w1"])
    s, pol = post("/rest/v1/overtime_policies", {"company_id": agency, "name": "Delhi warehouse OT", "country_code": "IN",
                  "daily_threshold_minutes": 420, "multiplier": 1.5}, tok["rec"])
    check("the agency configures its own overtime policy (no legal default assumed)", s == 201, f"{s} {msg(pol)}")
    s, req = rpc("omelo_create_requirement", {"p_company": agency, "p_fields": {"job_order_id": jo, "openings": 150,
                 "start_date": start_day, "end_date": end_day, "employment_type": "temporary", "pay_frequency": "weekly",
                 "hours_per_week": 48, "overtime_policy_id": pol[0]["id"], "late_grace_minutes": 10}}, tok["rec"])
    check("a workforce requirement for 150 workers from the job order", s == 200, f"{s} {msg(req)}")
    s, d = rpc("omelo_save_pay_component", {"p_requirement": req, "p_assignment": None, "p_kind": "allowance",
               "p_name": "Night allowance", "p_amount": 150, "p_basis": "per_shift", "p_shift_types": ["night"]}, tok["rec"])
    check("a night allowance per night shift", s == 200, f"{s} {msg(d)}")
    s, d = rpc("omelo_offer_assignment", {"p_requirement": req, "p_identity": acc["w2"]["identity"]}, tok["rec"])
    blocked("R5-002 the agency assigns a worker it does not represent", s, d)
    s, d = rpc("omelo_offer_assignment", {"p_requirement": req, "p_identity": acc["w1"]["identity"]}, tok["x"])
    blocked("R5-002 an outsider offers work on the agency's requirement", s, d)
    s, a1 = rpc("omelo_offer_assignment", {"p_requirement": req, "p_identity": acc["w1"]["identity"],
                "p_fields": {"bill_rate": 180, "bill_period": "hour"}}, tok["rec"])
    check("the agency offers the represented worker an assignment (with a separate bill rate)", s == 200, f"{s} {msg(a1)}")
    s, mine = rpc("omelo_my_assignments", {}, tok["w1"])
    got = next((x for x in mine if x["id"] == a1), {}) if s == 200 else {}
    check("the worker sees the offer: employer, client, dates, pay, shifts, overtime",
          got.get("status") == "offered" and got.get("client", "").startswith("ABC Warehousing")
          and got.get("pay", {}).get("rate") == 150 and "overtime" in got.get("agreement", {}), got)
    check("the worker never sees the bill rate", "180" not in json.dumps(got) and "bill" not in json.dumps(got), got)
    s, d = get(f"/rest/v1/assignment_billing?select=bill_rate&assignment_id=eq.{a1}", tok["w1"]); blocked("the worker reads the bill rate", s, d)
    s, d = get(f"/rest/v1/assignments?select=id&id=eq.{a1}", tok["w2"]); blocked("worker B reads worker A's assignment", s, d)
    s, d = get(f"/rest/v1/assignments?select=id&company_id=eq.{agency}", tok["x"]); blocked("R5-011 an outsider reads the agency's assignments", s, d)
    s, d = post("/rest/v1/assignments", {"requirement_id": req, "company_id": agency, "person_id": acc["w2"]["id"],
                "work_identity_id": acc["w2"]["identity"], "title": "x", "timezone": "UTC", "start_date": start_day,
                "employment_type": "temporary", "work_type": "full_time", "pay_rate": 1, "pay_period": "hour",
                "pay_frequency": "weekly", "currency": "INR", "source": "direct"}, tok["rec"])
    blocked("inserting an assignment directly", s, d)
    s, r = rpc("omelo_respond_to_assignment", {"p_assignment": a1, "p_accept": True}, tok["w1"])
    check("the worker accepts; the assignment is active (start date passed)", s == 200 and r == "active", f"{s} {msg(r)}")

    print("\nA2. SHIFTS, CHECK-IN, ATTENDANCE")
    s, tpl = rpc("omelo_save_shift_template", {"p_requirement": req, "p_template": {"name": "Night shift",
                 "days_of_week": [1, 2, 3, 4, 5, 6], "start_time": "22:00", "end_time": "06:00", "break_minutes": 30,
                 "required_workers": 50, "shift_type": "night"}}, tok["rec"])
    check("a recurring night-shift template (Mon-Sat 22:00-06:00)", s == 200, f"{s} {msg(tpl)}")
    s, n = rpc("omelo_generate_shifts", {"p_template": tpl, "p_from": (now + dt.timedelta(days=10)).date().isoformat(),
               "p_to": (now + dt.timedelta(days=40)).date().isoformat()}, tok["rec"])
    check("generate a month of individual shifts from it", s == 200 and 20 <= n <= 28, f"{s} {n}")
    s, n2 = rpc("omelo_generate_shifts", {"p_template": tpl, "p_from": (now + dt.timedelta(days=10)).date().isoformat(),
                "p_to": (now + dt.timedelta(days=40)).date().isoformat()}, tok["rec"])
    check("generating again creates no duplicates", s == 200 and n2 == 0, f"{s} {n2}")
    s1_start, s1_end = now - dt.timedelta(minutes=40), now + dt.timedelta(minutes=5)
    s2_start, s2_end = now - dt.timedelta(hours=10), now - dt.timedelta(hours=2)
    s, sh1 = rpc("omelo_create_shift", {"p_requirement": req, "p_shift": {"starts_at": iso(s1_start), "ends_at": iso(s1_end),
                 "break_minutes": 0, "required_workers": 5, "shift_type": "night", "kind": "emergency",
                 "instructions": "Report to gate 3"}}, tok["rec"])
    s, sh2 = rpc("omelo_create_shift", {"p_requirement": req, "p_shift": {"starts_at": iso(s2_start), "ends_at": iso(s2_end),
                 "break_minutes": 30, "required_workers": 5, "shift_type": "night"}}, tok["rec"])
    check("create an emergency shift and a regular night shift", isinstance(sh1, str) and isinstance(sh2, str), f"{msg(sh1)} {msg(sh2)}")
    s, r = rpc("omelo_assign_shift", {"p_shift": sh1, "p_assignments": [a1]}, tok["rec"])
    s2, r2 = rpc("omelo_assign_shift", {"p_shift": sh2, "p_assignments": [a1]}, tok["rec"])
    check("assign the worker to both shifts", s == 200 and r["assigned"] == 1 and s2 == 200 and r2["assigned"] == 1, f"{r} {r2}")
    s, d = rpc("omelo_update_shift", {"p_shift": sh1, "p_changes": {"instructions": "hacked"}}, tok["x"])
    blocked("employer A changes employer B's shift", s, d)
    s, work = rpc("omelo_my_work", {"p_from": (now - dt.timedelta(days=1)).date().isoformat(),
                  "p_to": (now + dt.timedelta(days=1)).date().isoformat()}, tok["w1"])
    w_sh1 = next((x for x in work if x["shift_id"] == sh1), {}); w_sh2 = next((x for x in work if x["shift_id"] == sh2), {})
    check("My Work shows today's shift with employer, client, supervisor slot, pay, instructions",
          w_sh1.get("title") and w_sh1.get("client", "").startswith("ABC") and w_sh1.get("instructions") == "Report to gate 3"
          and w_sh1.get("pay", {}).get("rate") == 150, w_sh1)
    s, d = rpc("omelo_check_out", {"p_shift_worker": w_sh1["shift_worker_id"]}, tok["w1"])
    blocked("R5-006 check-out before check-in", s, d)
    s, d = rpc("omelo_check_in", {"p_shift_worker": w_sh1["shift_worker_id"]}, tok["w2"])
    blocked("R5-005 worker B checks in to worker A's shift", s, d)
    s, att1 = rpc("omelo_check_in", {"p_shift_worker": w_sh1["shift_worker_id"], "p_lat": 28.6, "p_lng": 77.2}, tok["w1"])
    check("the worker checks in (40 minutes late)", s == 200 and isinstance(att1, str), f"{s} {msg(att1)}")
    s, ex = get(f"/rest/v1/attendance_exceptions?select=kind,minutes,status&attendance_id=eq.{att1}", tok["w1"])
    check("a late-arrival exception is created for review — not a penalty",
          s == 200 and ex and ex[0]["kind"] == "late" and ex[0]["minutes"] >= 39 and ex[0]["status"] == "pending", ex)
    s, d = rpc("omelo_check_in", {"p_shift_worker": w_sh1["shift_worker_id"]}, tok["w1"]); blocked("checking in twice", s, d)
    s, d = patch(f"/rest/v1/attendance_records?id=eq.{att1}", {"check_in_at": iso(s1_start)}, tok["w1"])
    blocked("forged attendance: the worker rewrites the check-in time", s, d)
    s, d = post("/rest/v1/attendance_records", {"shift_worker_id": w_sh2["shift_worker_id"], "shift_id": sh2, "assignment_id": a1,
                "person_id": acc["w1"]["id"], "scheduled_start": iso(s2_start), "scheduled_end": iso(s2_end),
                "check_in_at": iso(s2_start), "check_out_at": iso(s2_end), "status": "present"}, tok["w1"])
    blocked("forged attendance: inserting a full shift directly", s, d)
    s, out = rpc("omelo_check_out", {"p_shift_worker": w_sh1["shift_worker_id"]}, tok["w1"])
    check("the worker checks out; the record waits for review", s == 200 and out.get("needs_review") is True, f"{s} {msg(out)}")
    s, d = rpc("omelo_review_attendance", {"p_attendance": att1, "p_decision": "approve"}, tok["rec"])
    blocked("the agency reviews attendance at a client that reviews its own site", s, d)
    s, d = rpc("omelo_review_attendance", {"p_attendance": att1, "p_decision": "reject",
               "p_note": "Worked only a few minutes"}, tok["cli"])
    check("the client (workplace) reviews and rejects that short attendance", s in (200, 204), f"{s} {msg(d)}")
    s, d = rpc("omelo_review_attendance", {"p_attendance": att1, "p_decision": "approve"}, tok["cli"])
    blocked("R5-007 re-reviewing (silently changing) reviewed attendance", s, d)
    s, att2 = rpc("omelo_record_attendance", {"p_shift_worker": w_sh2["shift_worker_id"], "p_check_in": iso(s2_start),
                  "p_check_out": iso(s2_end), "p_note": "Supervisor sign-in sheet"}, tok["cli"])
    check("the client's supervisor records the full night shift (employer confirmation)", s == 200, f"{s} {msg(att2)}")
    s, ro = rpc("omelo_shift_roster", {"p_shift": sh2}, tok["cli"])
    check("the client sees the shift roster and its check-in code, without pay",
          s == 200 and ro.get("code") and len(ro.get("workers", [])) == 1 and "pay_rate" not in json.dumps(ro), msg(ro))
    s, d = rpc("omelo_shift_roster", {"p_shift": sh2}, tok["x"]); blocked("an outsider reads the roster", s, d)

    print("\nA3. TIMESHEET, EARNINGS, PAYMENT, BILLING")
    s, ts = rpc("omelo_build_timesheet", {"p_assignment": a1, "p_period_start": (now - dt.timedelta(days=1)).date().isoformat(),
                "p_period_end": (now + dt.timedelta(days=1)).date().isoformat()}, tok["w1"])
    check("the worker builds the timesheet from attendance", s == 200, f"{s} {msg(ts)}")
    s, t = get(f"/rest/v1/timesheets?select=total_minutes,regular_minutes,overtime_minutes,status&id=eq.{ts}", tok["w1"])
    check("7.5 h payable: 7 h regular + 30 min overtime (daily threshold 7 h)",
          s == 200 and t and t[0]["total_minutes"] == 450 and t[0]["overtime_minutes"] == 30, t)
    s, d = patch(f"/rest/v1/timesheets?id=eq.{ts}", {"status": "approved"}, tok["w1"]); blocked("forged timesheet: the worker approves it", s, d)
    s, d = post("/rest/v1/timesheet_entries", {"timesheet_id": ts, "work_date": now.date().isoformat(), "minutes": 600,
                "kind": "manual", "note": "extra"}, tok["w1"])
    blocked("forged timesheet: inserting hours directly", s, d)
    s, d = rpc("omelo_submit_timesheet", {"p_timesheet": ts}, tok["w1"]); check("the worker submits", s in (200, 204), f"{s} {msg(d)}")
    s, d = rpc("omelo_review_timesheet", {"p_timesheet": ts, "p_approve": True}, tok["w1"]); blocked("the worker approves their own timesheet", s, d)
    s, d = rpc("omelo_add_timesheet_entry", {"p_timesheet": ts, "p_work_date": now.date().isoformat(), "p_minutes": 60,
               "p_note": "after submit"}, tok["w1"])
    blocked("R5-008 editing a submitted timesheet", s, d)
    s, ap = rpc("omelo_workforce_approvals", {"p_company": st["client_company"]}, tok["cli"])
    check("the client's approvals list shows the timesheet", s == 200 and any(x["timesheet_id"] == ts for x in ap["timesheets"]), msg(ap))
    s, rv = rpc("omelo_review_timesheet", {"p_timesheet": ts, "p_approve": True}, tok["cli"])
    check("the client approves the timesheet; earnings are calculated", s == 200 and rv.get("earning_id"), f"{s} {msg(rv)}")
    earning = rv.get("earning_id")
    s, e = get(f"/rest/v1/earnings?select=base_amount,overtime_amount,allowance_amount,gross_amount,status,currency&id=eq.{earning}", tok["w1"])
    e0 = e[0] if s == 200 and e else {}
    check("earnings: 7 h x 150 = 1050 base, 0.5 h x 150 x 1.5 = 112.50 overtime, 150 night allowance, gross 1312.50 INR",
          float(e0.get("base_amount", 0)) == 1050 and float(e0.get("overtime_amount", 0)) == 112.5
          and float(e0.get("allowance_amount", 0)) == 150 and float(e0.get("gross_amount", 0)) == 1312.5
          and e0.get("currency") == "INR", e0)
    s, d = get(f"/rest/v1/earnings?select=id&id=eq.{earning}", tok["cli"]); blocked("the client reads the worker's pay", s, d)
    s, b = get(f"/rest/v1/billing_records?select=quantity,bill_rate,amount,status&timesheet_id=eq.{ts}", tok["cli"])
    check("the client sees its bill: 7.5 h x 180 = 1350 (agency margin kept apart)",
          s == 200 and b and float(b[0]["amount"]) == 1350, b)
    s, d = get(f"/rest/v1/billing_records?select=id&timesheet_id=eq.{ts}", tok["w1"]); blocked("the worker reads the bill", s, d)
    s, d = rpc("omelo_record_payment", {"p_earning": earning, "p_amount": 100}, tok["rec"])
    blocked("R5-010 paying earnings that are not approved", s, d)
    s, d = rpc("omelo_approve_earnings", {"p_earning": earning}, tok["w1"]); blocked("the worker approves their own earnings", s, d)
    s, d = rpc("omelo_approve_earnings", {"p_earning": earning}, tok["rec"]); check("the agency approves the earnings", s in (200, 204), f"{s} {msg(d)}")
    s, t = get(f"/rest/v1/timesheets?select=status&id=eq.{ts}", tok["w1"])
    check("R5-008 the timesheet is now locked", t and t[0]["status"] == "locked", t)
    s, d = rpc("omelo_record_payment", {"p_earning": earning, "p_amount": 2000}, tok["rec"])
    blocked("R5-010 a payment above the approved earnings", s, d)
    s, d = post("/rest/v1/payment_records", {"earning_id": earning, "person_id": acc["w1"]["id"], "company_id": agency,
                "amount": 1312.5, "currency": "INR", "status": "paid"}, tok["w1"])
    blocked("forged payment: the worker inserts a paid record", s, d)
    s, p1 = rpc("omelo_record_payment", {"p_earning": earning, "p_amount": 1312.5, "p_status": "scheduled",
                "p_provider": "manual", "p_scheduled_for": (now + dt.timedelta(days=3)).date().isoformat()}, tok["rec"])
    check("schedule the payment", s == 200, f"{s} {msg(p1)}")
    s, d = rpc("omelo_update_payment", {"p_payment": p1, "p_status": "paid", "p_reference": "UTR-TEST-1"}, tok["rec"])
    check("mark it paid", s in (200, 204), f"{s} {msg(d)}")
    s, me = rpc("omelo_my_earnings", {}, tok["w1"])
    m0 = next((x for x in me if x["id"] == earning), {}) if s == 200 else {}
    check("the worker sees base, overtime, allowance, gross and payment: paid",
          m0.get("status") == "paid" and len(m0.get("lines") or []) >= 3 and (m0.get("payments") or [{}])[0].get("status") == "paid", m0)
    s, d = rpc("omelo_reopen_timesheet", {"p_timesheet": ts, "p_reason": "wrong hours"}, tok["rec"])
    blocked("reopening a timesheet that has been paid", s, d)

    print("\nB. DIRECT EMPLOYER WORKFORCE")
    s, req2 = rpc("omelo_create_requirement", {"p_company": st["emp_company"], "p_fields": {"job_id": st["job_id"],
                  "openings": 10, "start_date": start_day, "end_date": end_day, "employment_type": "temporary",
                  "pay_frequency": "weekly"}}, tok["emp"])
    check("the employer creates a requirement from its job (800/day)", s == 200, f"{s} {msg(req2)}")
    s, a2 = rpc("omelo_offer_assignment", {"p_requirement": req2, "p_identity": acc["w2"]["identity"]}, tok["emp"])
    check("offer the applicant an assignment", s == 200, f"{s} {msg(a2)}")
    s, d = rpc("omelo_offer_assignment", {"p_requirement": req2, "p_identity": acc["w1"]["identity"]}, tok["emp"])
    blocked("offering work to someone with no relationship to the employer", s, d)
    rpc("omelo_respond_to_assignment", {"p_assignment": a2, "p_accept": True}, tok["w2"])
    f_start = (now + dt.timedelta(days=3)).replace(hour=9, minute=0, second=0, microsecond=0)
    s, sh3 = rpc("omelo_create_shift", {"p_requirement": req2, "p_shift": {"starts_at": iso(f_start),
                 "ends_at": iso(f_start + dt.timedelta(hours=8)), "required_workers": 3}}, tok["emp"])
    s, sh4 = rpc("omelo_create_shift", {"p_requirement": req2, "p_shift": {"starts_at": iso(f_start + dt.timedelta(hours=4)),
                 "ends_at": iso(f_start + dt.timedelta(hours=12)), "required_workers": 3}}, tok["emp"])
    s, r = rpc("omelo_assign_shift", {"p_shift": sh3, "p_assignments": [a2]}, tok["emp"])
    check("assign the worker to a day shift", s == 200 and r["assigned"] == 1, f"{s} {msg(r)}")
    s, r = rpc("omelo_assign_shift", {"p_shift": sh4, "p_assignments": [a2]}, tok["emp"])
    check("R5-004 an overlapping shift is refused as a schedule conflict",
          s == 200 and r["assigned"] == 0 and "conflict" in json.dumps(r["errors"]).lower(), f"{s} {msg(r)}")
    s, rep = rpc("omelo_shift_replacements", {"p_shift": sh4}, tok["emp"])
    check("replacement search excludes the double-booked worker", s == 200 and all(c["assignment_id"] != a2 for c in rep["candidates"]), msg(rep))
    s, d = rpc("omelo_cancel_shift", {"p_shift": sh3, "p_reason": "Stock delivery postponed"}, tok["emp"])
    check("cancel the shift", s in (200, 204), f"{s} {msg(d)}")
    s, work2 = rpc("omelo_my_work", {"p_from": now.date().isoformat(), "p_to": (now + dt.timedelta(days=5)).date().isoformat()}, tok["w2"])
    w3 = next((x for x in work2 if x["shift_id"] == sh3), {})
    check("the worker sees it cancelled", w3.get("status") == "cancelled", w3)
    s, d = rpc("omelo_check_in", {"p_shift_worker": w3.get("shift_worker_id")}, tok["w2"])
    blocked("R5-014 checking in to a cancelled shift", s, d)
    s, lv = rpc("omelo_request_leave", {"p_assignment": a2, "p_type": "sick", "p_start": (now + dt.timedelta(days=5)).date().isoformat(),
                "p_end": (now + dt.timedelta(days=5)).date().isoformat(), "p_reason": "Fever", "p_label": "Sick leave"}, tok["w2"])
    check("the worker requests sick leave", s == 200, f"{s} {msg(lv)}")
    s, d = rpc("omelo_review_leave", {"p_leave": lv, "p_approve": True}, tok["w2"]); blocked("the worker approves their own leave", s, d)
    s, d = rpc("omelo_review_leave", {"p_leave": lv, "p_approve": True, "p_note": "Get well"}, tok["emp"])
    check("the employer approves the leave", s in (200, 204), f"{s} {msg(d)}")
    s, d = rpc("omelo_set_assignment_status", {"p_assignment": a2, "p_status": "completed", "p_reason": "Season finished"}, tok["emp"])
    check("the employer completes the assignment", s in (200, 204), f"{s} {msg(d)}")
    s, exps = get(f"/rest/v1/experiences?select=employer_name,is_verified,work_identity_id,ended_on&person_id=eq.{acc['w2']['id']}", tok["w2"])
    check("R5-013 completed work becomes verified experience on the right identity",
          s == 200 and any(x["is_verified"] and x["work_identity_id"] == acc["w2"]["identity"] and x["ended_on"] for x in exps), exps)
    s, sh5 = rpc("omelo_create_shift", {"p_requirement": req2, "p_shift": {"starts_at": iso(f_start + dt.timedelta(days=1)),
                 "ends_at": iso(f_start + dt.timedelta(days=1, hours=8))}}, tok["emp"])
    s, r = rpc("omelo_assign_shift", {"p_shift": sh5, "p_assignments": [a2]}, tok["emp"])
    check("R5-015 a completed assignment receives no new shifts", s == 200 and r["assigned"] == 0, f"{s} {msg(r)}")
    s, d = post("/rest/v1/experiences", {"person_id": acc["w2"]["id"], "employer_name": "Fake Corp", "title": "Boss",
                "is_verified": True, "started_on": "2020-01-01"}, tok["w2"])
    blocked_or_unverified = s >= 400 or (isinstance(d, list) and d and d[0].get("is_verified") is False)
    check("R5-012 a worker cannot manufacture verified employment", blocked_or_unverified, f"{s} {msg(d)}")

    print("\nC. BULK OPERATIONS (asynchronous, authority per item)")
    s, d = rpc("omelo_start_workforce_job", {"p_company": st["emp_company"], "p_kind": "offer_assignments",
               "p_payload": {"requirement_id": req2}}, tok["x"])
    blocked("an outsider starts a bulk job for the employer", s, d)
    s, job = rpc("omelo_start_workforce_job", {"p_company": st["emp_company"], "p_kind": "offer_assignments",
                 "p_payload": {"requirement_id": req2, "identity_ids": [acc["w1"]["identity"], acc["w2"]["identity"]]}}, tok["emp"])
    check("the employer queues a bulk offer (runs in the background)", s == 200, f"{s} {msg(job)}")
    final = {}
    for _ in range(30):
        time.sleep(6)
        s, j = get(f"/rest/v1/workforce_jobs?select=status,processed,succeeded,failed,errors&id=eq.{job}", tok["emp"])
        final = j[0] if s == 200 and j else {}
        if final.get("status") in ("succeeded", "partial", "failed"): break
    check("R5-016 the scheduler processed it and refused the items the employer may not act on",
          final.get("processed") == 2 and final.get("failed") >= 1 and final.get("status") in ("partial", "failed"), final)

    print("\nD. DASHBOARDS")
    s, dash = rpc("omelo_workforce_dashboard", {"p_company": agency}, tok["rec"])
    check("agency dashboard: workforce + staffing counts", s == 200 and dash.get("active_workers") == 1
          and "pending_consents" in dash and "placements" in dash and "timesheets" in dash, dash)
    s, cw = rpc("omelo_client_workforce", {"p_company": st["client_company"]}, tok["cli"])
    check("the client sees the agency workers at its site, without pay",
          s == 200 and len(cw) == 1 and "pay" not in json.dumps(cw), cw)
    s, d = rpc("omelo_workforce_dashboard", {"p_company": agency}, tok["x"]); blocked("an outsider reads the agency dashboard", s, d)

    os.remove(STATE)
    print(f"\n{'ALL PASSED' if not FAIL else str(len(FAIL)) + ' FAILED: ' + '; '.join(FAIL)}")


if __name__ == "__main__":
    {"setup": setup, "run": run}.get(sys.argv[1] if len(sys.argv) > 1 else "", lambda: print(__doc__))()
