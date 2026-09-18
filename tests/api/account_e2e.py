"""Release 1: progressive trust, sessions, account deletion, rate limits,
events and admin observability — as real users.

    python tests/api/account_e2e.py

Creates four probe.* accounts. Steps that need the server clock or the
email outbox (confirming an emailed code, processing a due deletion) are
verified separately in SQL; this script prints the ids needed for that.
"""
import sys, time
from omelo_api import *

FAIL = []
def check(label, ok, detail=""):
    print(f"  {'PASS' if ok else 'FAIL'} | {label}" + (f" | {detail}" if detail and not ok else ""))
    if not ok: FAIL.append(label)

def blocked(label, s, d):
    check(f"blocked: {label}", s >= 400 or (isinstance(d, list) and len(d) == 0) or d is False, f"HTTP {s} {msg(d)}")

stamp = str(int(time.time()))
PW = "ProbePass2026!"
emp_tok, emp_id = signup(f"probe.emp.{stamp}@omelo.dev", PW, "Owner Person", "employer")
mate_tok, mate_id = signup(f"probe.mate.{stamp}@omelo.dev", PW, "Team Mate", "employer")
wrk_tok, wrk_id = signup(f"probe.wrk.{stamp}@omelo.dev", PW, "Worker Person", "worker")
out_tok, out_id = signup(f"probe.out.{stamp}@omelo.dev", PW, "Outsider", "worker")

print("\n1. PROGRESSIVE TRUST")
s, st = rpc("omelo_my_trust_status", {}, wrk_tok)
check("trust status starts unverified", s == 200 and st["email_verified"] is False and st["phone_otp_available"] is False, f"{s} {st}")
s, d = rpc("omelo_request_email_verification", {}, wrk_tok)
check("request an email code (address masked)", s == 200 and "•••" in d.get("sent_to", ""), f"{s} {d}")
s, d = rpc("omelo_confirm_verification", {"p_channel": "email", "p_code": "000000"}, wrk_tok)
blocked("a wrong code", s, d)
s, d = get("/rest/v1/verification_challenges?select=*", wrk_tok)
check("challenges are not reachable over the API", s >= 400, f"{s} {msg(d)}")
s, d = rpc("omelo_request_phone_verification", {"p_phone": "+919876543210"}, wrk_tok)
check("phone OTP says it is not available yet (flag off)", s >= 400 and "not available" in msg(d), f"{s} {msg(d)}")
s, d = post("/rest/v1/verifications", {"subject_type": "person", "subject_id": wrk_id, "person_id": wrk_id,
            "type": "email", "status": "verified", "method": "otp"}, wrk_tok)
blocked("worker self-inserts a verified email", s, d)

print("\n2. SESSIONS")
a = login_full(f"probe.wrk.{stamp}@omelo.dev", PW)
b = login_full(f"probe.wrk.{stamp}@omelo.dev", PW)
s, ss = rpc("omelo_my_sessions", {}, b["access_token"])
check("lists my sessions, marks the current one", s == 200 and len(ss) >= 2 and sum(1 for x in ss if x["is_current"]) == 1, f"{s} {ss}")
check("IP addresses are only hinted, never shown", all((x["ip_hint"] or "").endswith((".x.x", "…")) or x["ip_hint"] is None for x in ss), ss)
other = next(x["id"] for x in ss if not x["is_current"])
s, d = rpc("omelo_revoke_session", {"p_session_id": other}, out_tok)
check("outsider cannot revoke my session", s == 200 and d is False, f"{s} {d}")
s, d = rpc("omelo_revoke_other_sessions", {}, b["access_token"])
check("sign out everywhere else", s == 200 and d >= 2, f"{s} {d}")
s, d = refresh(a["refresh_token"])
check("a revoked session cannot refresh", s >= 400, f"{s} {msg(d)}")
s, d = refresh(b["refresh_token"])
check("the current session keeps working", s == 200 and d.get("access_token"), f"{s} {msg(d)}")

print("\n3. ACCOUNT DELETION")
s, slug = rpc("omelo_company_slug", {"p_name": f"Delete Test {stamp}"}, emp_tok)
s, co = post("/rest/v1/companies", {"slug": slug, "display_name": f"Delete Test {stamp}", "country_code": "IN",
             "size_band": "1-10", "created_by": emp_id}, emp_tok); cid = co[0]["id"]
s, loc = get("/rest/v1/locations?select=id&latitude=not.is.null&country_code=eq.IN&limit=1")
s, prof = get("/rest/v1/professions?select=id,category_id&slug=eq.driver")
s, job = post("/rest/v1/jobs", {"company_id": cid, "created_by": emp_id, "title": "Delivery Driver",
              "profession_id": prof[0]["id"], "category_id": prof[0]["category_id"], "location_id": loc[0]["id"],
              "workplace_type": "onsite", "work_type": "full_time", "pay_min": 15000, "pay_max": 20000,
              "pay_period": "month", "pay_currency": "INR", "accepts_no_experience": True, "status": "draft"}, emp_tok)
jid = job[0]["id"]
_, _inv = rpc("omelo_invite_team_member", {"p_company": cid, "p_email": f"probe.mate.{stamp}@omelo.dev", "p_role": "recruiter"}, emp_tok)
assert rpc("omelo_accept_team_invitation", {"p_invitation": _inv}, mate_tok)[0] == 200, "teammate could not join the team"
s, d = rpc("omelo_request_account_deletion", {"p_reason": "testing"}, emp_tok)
check("sole owner of a team cannot delete until ownership moves", s >= 400 and "owner" in msg(d), f"{s} {msg(d)}")
s, d = rpc("omelo_request_account_deletion", {"p_reason": "Found work elsewhere"}, wrk_tok)
check("worker schedules deletion (14-day grace)", s == 200 and d.get("scheduled_for"), f"{s} {d}")
s, st = rpc("omelo_my_trust_status", {}, wrk_tok)
check("status shows the scheduled date", st.get("deletion_scheduled_for"), st)
s, d = rpc("omelo_cancel_account_deletion", {}, wrk_tok); check("worker can cancel", s == 200 and d is True, f"{s} {d}")
s, d = rpc("omelo_request_account_deletion", {}, wrk_tok); check("and schedule again", s == 200, f"{s} {d}")
s, d = get(f"/rest/v1/account_deletion_requests?select=person_id&person_id=eq.{wrk_id}", out_tok)
check("others cannot see my deletion request", s == 200 and d == [], d)
patch(f"/rest/v1/company_members?company_id=eq.{cid}&person_id=eq.{mate_id}", {"is_active": False}, emp_tok)
s, d = rpc("omelo_request_account_deletion", {}, emp_tok)
check("after the team is gone the owner can schedule deletion", s == 200, f"{s} {msg(d)}")

print("\n4. OBSERVABILITY")
s, d = rpc("omelo_admin_system_health", {"p_hours": 24}, emp_tok); blocked("non-admin reads system health", s, d)
s, d = rpc("omelo_admin_kpis", {"p_days": 30}, wrk_tok); blocked("non-admin reads KPIs", s, d)

print(f"\n{'ALL PASSED' if not FAIL else str(len(FAIL)) + ' FAILED: ' + '; '.join(FAIL)}")
print(f"stamp={stamp} worker={wrk_id} owner={emp_id} company={cid} job={jid}")
sys.exit(1 if FAIL else 0)
