"""End-to-end proof of the hiring loop and its integrity guards, as real users.

Every request uses the publishable key + a real user JWT, so RLS and the
guard triggers apply exactly as they do for the apps.

    python tests/api/hiring_loop_e2e.py

Creates four throwaway `probe.*@omelo.dev` accounts per run. The signup
function allows 10 accounts per IP per hour, so run it at most twice an hour.
Remove the data afterwards (SQL editor, development only):

    delete from companies where created_by in
      (select id from persons where email like 'probe.%@omelo.dev');
    delete from auth.users where email like 'probe.%@omelo.dev';
"""
import sys, time, datetime as dt
from omelo_api import *

FAIL = []
def check(label, ok, detail=""):
    print(f"  {'PASS' if ok else 'FAIL'} | {label}" + (f" | {detail}" if detail and not ok else ""))
    if not ok: FAIL.append(label)

def blocked(label, s, d):
    ok = s >= 400 or (isinstance(d, list) and len(d) == 0)
    check(f"blocked: {label}", ok, f"HTTP {s} {msg(d)}")

stamp = str(int(time.time()))
PW = "ProbePass2026!"
emp_tok, emp_id = signup(f"probe.emp.{stamp}@omelo.dev", PW, "Priya Employer", "employer")
oth_tok, oth_id = signup(f"probe.oth.{stamp}@omelo.dev", PW, "Other Employer", "employer")
wrk_tok, wrk_id = signup(f"probe.wrk.{stamp}@omelo.dev", PW, "Arjun Worker", "worker")
wk2_tok, wk2_id = signup(f"probe.wk2.{stamp}@omelo.dev", PW, "Meena Worker", "worker")

def make_company(tok, uid, name):
    s, slug = rpc("omelo_company_slug", {"p_name": name}, tok)
    s, co = post("/rest/v1/companies", {"slug": slug, "display_name": name, "country_code": "IN",
                 "size_band": "11-50", "created_by": uid}, tok)
    assert s == 201, (s, co)
    return co[0]["id"]

def make_job(tok, uid, cid):
    s, loc = get("/rest/v1/locations?select=id&latitude=not.is.null&country_code=eq.IN&limit=1")
    s, prof = get("/rest/v1/professions?select=id,category_id&slug=eq.cook")
    if not prof: s, prof = get("/rest/v1/professions?select=id,category_id&limit=1")
    s, job = post("/rest/v1/jobs", {"company_id": cid, "created_by": uid, "title": "Line Cook",
                  "profession_id": prof[0]["id"], "category_id": prof[0]["category_id"],
                  "location_id": loc[0]["id"], "workplace_type": "onsite", "work_type": "full_time",
                  "pay_min": 18000, "pay_max": 24000, "pay_period": "month", "pay_currency": "INR",
                  "accepts_no_experience": True, "status": "draft"}, tok)
    assert s == 201, (s, job)
    jid = job[0]["id"]
    stages = [("New", 1, "applied", False), ("Shortlisted", 2, "shortlisted", False),
              ("Phone call", 3, "screening", False), ("Interview", 4, "interview", False),
              ("Offer", 5, "offer", False), ("Hired", 6, "hired", True),
              ("Not moving forward", 7, "rejected", True)]
    s, d = post("/rest/v1/job_stages", [{"job_id": jid, "name": n, "position": p, "maps_to_state": m,
                                         "is_terminal": t} for n, p, m, t in stages], tok)
    assert s == 201, (s, d)
    s, d = patch(f"/rest/v1/jobs?id=eq.{jid}", {"status": "published"}, tok)
    assert s == 200 and d, (s, d)
    return jid, prof[0]["id"]

cid = make_company(emp_tok, emp_id, f"Spice Route Kitchens {stamp}")
ocid = make_company(oth_tok, oth_id, f"Rival Foods {stamp}")
jid, prof_id = make_job(emp_tok, emp_id, cid)
ojid, _ = make_job(oth_tok, oth_id, ocid)

def apply(tok, uid, job, company):
    s, wi = get(f"/rest/v1/work_identities?select=id&person_id=eq.{uid}&is_primary=eq.true", tok)
    s, app = post("/rest/v1/applications", {"job_id": job, "person_id": uid, "company_id": company,
                  "work_identity_id": wi[0]["id"], "identity_snapshot": {"n": "probe"},
                  "state": "hired", "first_viewed_at": "2020-01-01T00:00:00Z"}, tok)
    assert s == 201, (s, app)
    return app[0], wi[0]["id"]

print("\n1. APPLY + MATCH")
app, wi_id = apply(wrk_tok, wrk_id, jid, cid)
aid = app["id"]
check("application starts as 'applied' even when the client sends state=hired", app["state"] == "applied")
check("client-sent first_viewed_at ignored", app["first_viewed_at"] is None)
check("match score computed at submission", isinstance(app["match_score"], int), app["match_score"])
s, d = post("/rest/v1/applications", {"job_id": jid, "person_id": wk2_id, "company_id": ocid,
            "work_identity_id": wi_id, "identity_snapshot": {}}, wk2_tok)
blocked("application with a company_id that is not the job's company", s, d)

print("\n2. EXPLOITS FROM THE PROBE (must all be blocked now)")
s, d = patch(f"/rest/v1/applications?id=eq.{aid}", {"state": "hired"}, emp_tok); blocked("employer sets state=hired directly", s, d)
s, d = patch(f"/rest/v1/applications?id=eq.{aid}", {"state": "rejected"}, emp_tok); blocked("employer rejects directly, no reason", s, d)
s, stg = get(f"/rest/v1/job_stages?select=id&job_id=eq.{ojid}&maps_to_state=eq.hired", oth_tok)
s, d = patch(f"/rest/v1/applications?id=eq.{aid}", {"stage_id": stg[0]["id"]}, emp_tok); blocked("employer sets a stage from another job", s, d)
s, d = post("/rest/v1/employments", {"person_id": wrk_id, "company_id": cid, "title": "Forged",
            "started_on": "2020-01-01", "status": "ended"}, emp_tok); blocked("employer inserts an employment", s, d)
s, d = post("/rest/v1/experiences", {"person_id": wrk_id, "employer_name": "Google", "title": "Staff Engineer",
            "is_verified": True}, wrk_tok); blocked("worker inserts a verified experience", s, d)
s, sk = get("/rest/v1/skills?select=id&limit=1")
s, d = post("/rest/v1/person_skills", {"person_id": wrk_id, "skill_id": sk[0]["id"], "is_verified": True,
            "evidence_type": "employer_verified"}, wrk_tok); blocked("worker self-marks a skill employer_verified", s, d)
s, d = patch(f"/rest/v1/companies?id=eq.{cid}", {"is_verified": True}, emp_tok); blocked("employer self-verifies company", s, d)
s, d = patch(f"/rest/v1/companies?id=eq.{cid}", {"total_hires": 500}, emp_tok); blocked("employer inflates total_hires", s, d)
s, d = post("/rest/v1/application_events", {"application_id": aid, "event_type": "decision_made",
            "actor_type": "recruiter", "to_state": "hired"}, emp_tok); blocked("employer forges an audit event", s, d)
s, d = post("/rest/v1/application_events", {"application_id": aid, "event_type": "withdrawn",
            "actor_type": "candidate"}, wrk_tok); blocked("worker forges an audit event", s, d)
s, d = post("/rest/v1/interviews", {"application_id": aid, "job_id": jid, "company_id": cid, "person_id": wrk_id,
            "type": "phone", "scheduled_at": "2030-01-01T10:00:00Z", "status": "completed"}, emp_tok)
blocked("employer inserts an interview directly", s, d)
s, d = post("/rest/v1/offers", {"application_id": aid, "job_id": jid, "company_id": cid, "person_id": wrk_id,
            "title": "Line Cook", "status": "accepted"}, emp_tok); blocked("employer inserts an already-accepted offer", s, d)
s, d = rpc("omelo_move_application", {"p_application_id": aid, "p_state": "shortlisted"}, oth_tok)
blocked("another company moves my candidate", s, d)
s, d = rpc("omelo_reject_application", {"p_application_id": aid, "p_reason": "nope"}, wrk_tok)
blocked("worker calls reject on own application", s, d)
s, d = rpc("omelo_move_application", {"p_application_id": aid, "p_state": "hired"}, emp_tok)
blocked("move_application straight to hired", s, d)
s, d = rpc("omelo_reject_application", {"p_application_id": aid, "p_reason": " "}, emp_tok)
blocked("reject with a blank reason", s, d)

print("\n3. REVIEW -> SHORTLIST")
s, d = rpc("omelo_mark_application_viewed", {"p_application_id": aid}, emp_tok); check("employer opens candidate", s in (200, 204), f"{s} {msg(d)}")
s, d = rpc("omelo_rank_applicants", {"p_job_id": jid}, emp_tok); check("rank applicants", s == 200 and len(d) == 1, f"{s} {msg(d)}")
s, m = get(f"/rest/v1/matches?select=score,feature_vector&job_id=eq.{jid}&person_id=eq.{wrk_id}", emp_tok)
check("employer can read the stored explanation", s == 200 and m and "strengths" in m[0]["feature_vector"], f"{s} {msg(m)}")
s, d = rpc("omelo_move_application", {"p_application_id": aid, "p_state": "shortlisted"}, emp_tok); check("shortlist", s == 200, f"{s} {msg(d)}")

print("\n4. INTERVIEW")
when = (dt.datetime.utcnow() + dt.timedelta(days=2)).replace(microsecond=0).isoformat() + "Z"
s, iid = rpc("omelo_schedule_interview", {"p_application_id": aid, "p_type": "in_person", "p_scheduled_at": when,
             "p_duration_minutes": 30, "p_location_text": "Sector 18 kitchen, back entrance"}, emp_tok)
check("schedule interview", s == 200 and isinstance(iid, str), f"{s} {msg(iid)}")
s, d = patch(f"/rest/v1/interviews?id=eq.{iid}", {"status": "completed"}, emp_tok); blocked("employer marks interview completed directly", s, d)
s, d = rpc("omelo_confirm_interview", {"p_interview_id": iid}, emp_tok); blocked("employer confirms on the worker's behalf", s, d)
s, d = rpc("omelo_confirm_interview", {"p_interview_id": iid}, wrk_tok); check("worker confirms interview", s in (200, 204), f"{s} {msg(d)}")
s, d = rpc("omelo_complete_interview", {"p_interview_id": iid, "p_outcome": "completed", "p_rating": 4,
           "p_recommendation": "strong_yes", "p_notes": "Fast and clean knife work."}, emp_tok)
check("complete interview with scorecard", s in (200, 204), f"{s} {msg(d)}")
s, d = get(f"/rest/v1/application_notes?select=body&application_id=eq.{aid}", wrk_tok)
check("worker cannot read the private scorecard", s == 200 and d == [], f"{s} {d}")
s, d = get(f"/rest/v1/application_notes?select=body&application_id=eq.{aid}", emp_tok)
check("employer sees the scorecard", s == 200 and d and "Rating: 4/5" in d[0]["body"], f"{s} {d}")

print("\n5. OFFER")
start = (dt.date.today() + dt.timedelta(days=7)).isoformat()
s, oid = rpc("omelo_send_offer", {"p_application_id": aid, "p_pay_amount": 22000, "p_pay_period": "month",
             "p_start_date": start}, emp_tok)
check("send offer", s == 200 and isinstance(oid, str), f"{s} {msg(oid)}")
s, d = rpc("omelo_send_offer", {"p_application_id": aid, "p_pay_amount": 1, "p_pay_period": "month",
           "p_start_date": start}, emp_tok); blocked("a second open offer", s, d)
s, d = patch(f"/rest/v1/offers?id=eq.{oid}", {"pay_amount": 99000, "status": "accepted"}, wrk_tok)
blocked("worker rewrites pay while accepting", s, d)
s, d = patch(f"/rest/v1/offers?id=eq.{oid}", {"pay_amount": 5000}, emp_tok); blocked("employer edits a sent offer", s, d)
s, d = rpc("omelo_respond_to_offer", {"p_offer_id": oid, "p_accept": True}, emp_tok); blocked("employer accepts on the worker's behalf", s, d)
s, d = rpc("omelo_view_offer", {"p_offer_id": oid}, wrk_tok); check("worker opens offer", s in (200, 204), f"{s} {msg(d)}")
s, d = get(f"/rest/v1/applications?select=state&id=eq.{aid}", wrk_tok); check("worker sees state=offer", d and d[0]["state"] == "offer", d)

print("\n6. ACCEPT -> HIRED -> VERIFIED EMPLOYMENT -> IDENTITY UPDATED")
s, res = rpc("omelo_respond_to_offer", {"p_offer_id": oid, "p_accept": True}, wrk_tok)
check("worker accepts", s == 200 and res.get("status") == "accepted" and res.get("employment_id"), f"{s} {msg(res)}")
s, d = get(f"/rest/v1/applications?select=state,closed_at&id=eq.{aid}", emp_tok)
check("application is hired and closed", d and d[0]["state"] == "hired" and d[0]["closed_at"], d)
s, d = get(f"/rest/v1/employments?select=id,offer_id,application_id,status&person_id=eq.{wrk_id}", wrk_tok)
check("employment record linked to offer + application", d and d[0]["offer_id"] == oid and d[0]["application_id"] == aid, d)
s, ex = get(f"/rest/v1/experiences?select=id,is_verified,work_identity_id,employer_name,is_current&person_id=eq.{wrk_id}", wrk_tok)
check("verified experience on the identity used to apply",
      ex and ex[0]["is_verified"] and ex[0]["work_identity_id"] == wi_id and ex[0]["is_current"], ex)
s, v = get(f"/rest/v1/verifications?select=subject_id,status,method&person_id=eq.{wrk_id}", wrk_tok)
check("verification points at the experience", v and v[0]["subject_id"] == ex[0]["id"] and v[0]["status"] == "verified", v)
s, d = patch(f"/rest/v1/experiences?id=eq.{ex[0]['id']}", {"title": "Head Chef"}, wrk_tok)
blocked("worker inflates the verified title", s, d)
s, d = patch(f"/rest/v1/experiences?id=eq.{ex[0]['id']}", {"description": "Grill and tandoor station"}, wrk_tok)
check("worker can still describe their verified job", s == 200 and d, f"{s} {msg(d)}")
s, d = get(f"/rest/v1/companies?select=total_hires&id=eq.{cid}")
check("company hire count incremented by Omelo", d and d[0]["total_hires"] == 1, d)

print("\n7. AUDIT TRAIL (worker-visible)")
s, ev = get(f"/rest/v1/application_events?select=event_type,actor_type,from_state,to_state,reason&application_id=eq.{aid}&order=id", wrk_tok)
for e in ev:
    print(f"     {e['event_type']:<20} {e['actor_type']:<10} {str(e['from_state']):<12} -> {str(e['to_state']):<12} {e['reason'] or ''}")
types = [e["event_type"] for e in ev]
for t in ["created", "viewed", "shortlisted", "interview_scheduled", "interview_completed", "offer_extended", "offer_responded", "decision_made"]:
    check(f"event '{t}' recorded", t in types)
check("hire decision attributed to the candidate",
      any(e["event_type"] == "decision_made" and e["to_state"] == "hired" and e["actor_type"] == "candidate" for e in ev))
s, n = get(f"/rest/v1/notifications?select=type,title&person_id=eq.{wrk_id}&order=id", wrk_tok)
check("worker notified at each step", len(n) >= 3, n)
print("     " + " | ".join(x["title"] for x in n))

print("\n8. REJECT + WITHDRAW PATHS")
app2, _ = apply(wk2_tok, wk2_id, jid, cid)
s, d = patch(f"/rest/v1/applications?id=eq.{app2['id']}", {"state": "declined_by_candidate"}, wk2_tok)
blocked("candidate sets declined_by_candidate directly", s, d)
s, d = rpc("omelo_reject_application", {"p_application_id": app2["id"], "p_reason": "Looking for more grill experience"}, emp_tok)
check("reject with reason", s in (200, 204), f"{s} {msg(d)}")
s, d = get(f"/rest/v1/applications?select=state,rejection_reason&id=eq.{app2['id']}", wk2_tok)
check("worker sees rejection and reason", d and d[0]["state"] == "rejected" and d[0]["rejection_reason"], d)
s, d = rpc("omelo_move_application", {"p_application_id": app2["id"], "p_state": "shortlisted"}, emp_tok)
blocked("move a rejected application", s, d)
app3, _ = apply(wk2_tok, wk2_id, ojid, ocid)
s, d = patch(f"/rest/v1/applications?id=eq.{app3['id']}", {"state": "withdrawn", "withdrawal_reason": "Found work"}, wk2_tok)
check("candidate withdraw still works from the app", s == 200 and d and d[0]["state"] == "withdrawn", f"{s} {msg(d)}")

print("\n9. WORKER RECOMMENDATIONS")
s, rec = rpc("omelo_recommend_jobs", {"p_lat": 28.6273, "p_lng": 77.3714, "p_limit": 5}, wrk_tok)
check("recommendations honour limit", s == 200 and 0 < len(rec) <= 5, f"{s} {msg(rec)}")
check("recommendations sorted best first", [r["score"] for r in rec if r["eligible"]] == sorted([r["score"] for r in rec if r["eligible"]], reverse=True))

print(f"\n{'ALL PASSED' if not FAIL else str(len(FAIL)) + ' FAILED: ' + '; '.join(FAIL)}")
print(f"probe stamp {stamp}")
sys.exit(1 if FAIL else 0)
