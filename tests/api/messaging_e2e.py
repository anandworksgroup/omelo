"""Job-context messaging and the notification inbox, as real users.

    python tests/api/messaging_e2e.py

Creates four probe.* accounts per run (signup allows 10/hour per IP); clean
up as described in hiring_loop_e2e.py.
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
emp_tok, emp_id = signup(f"probe.emp.{stamp}@omelo.dev", PW, "Sarah Recruiter", "employer")
vwr_tok, vwr_id = signup(f"probe.vwr.{stamp}@omelo.dev", PW, "Finance Viewer", "employer")
wrk_tok, wrk_id = signup(f"probe.wrk.{stamp}@omelo.dev", PW, "Ravi Candidate", "worker")
riv_tok, riv_id = signup(f"probe.riv.{stamp}@omelo.dev", PW, "Rival Worker", "worker")

s, slug = rpc("omelo_company_slug", {"p_name": f"Chat Kitchens {stamp}"}, emp_tok)
s, co = post("/rest/v1/companies", {"slug": slug, "display_name": f"Chat Kitchens {stamp}", "country_code": "IN",
             "size_band": "11-50", "created_by": emp_id}, emp_tok); cid = co[0]["id"]
_, _inv = rpc("omelo_invite_team_member", {"p_company": cid, "p_email": f"probe.vwr.{stamp}@omelo.dev", "p_role": "viewer"}, emp_tok)
assert rpc("omelo_accept_team_invitation", {"p_invitation": _inv}, vwr_tok)[0] == 200, "viewer could not join the team"
s, loc = get("/rest/v1/locations?select=id&latitude=not.is.null&country_code=eq.IN&limit=1")
s, prof = get("/rest/v1/professions?select=id,category_id&slug=eq.cook")
s, job = post("/rest/v1/jobs", {"company_id": cid, "created_by": emp_id, "title": "Line Cook",
              "profession_id": prof[0]["id"], "category_id": prof[0]["category_id"], "location_id": loc[0]["id"],
              "workplace_type": "onsite", "work_type": "full_time", "pay_min": 18000, "pay_max": 22000,
              "pay_period": "month", "pay_currency": "INR", "accepts_no_experience": True, "status": "draft"}, emp_tok)
jid = job[0]["id"]
post("/rest/v1/job_stages", [{"job_id": jid, "name": "New", "position": 1, "maps_to_state": "applied", "is_terminal": False}], emp_tok)
patch(f"/rest/v1/jobs?id=eq.{jid}", {"status": "published"}, emp_tok)
s, wi = get(f"/rest/v1/work_identities?select=id&person_id=eq.{wrk_id}&is_primary=eq.true", wrk_tok)
s, app = post("/rest/v1/applications", {"job_id": jid, "person_id": wrk_id, "company_id": cid,
              "work_identity_id": wi[0]["id"], "identity_snapshot": {}}, wrk_tok); aid = app[0]["id"]

print("\n1. NO UNSOLICITED OUTREACH")
s, d = post("/rest/v1/conversations", {"company_id": cid, "person_id": riv_id, "initiated_by": "recruiter", "subject": "Hi"}, emp_tok)
blocked("employer opens a conversation with someone who never applied", s, d)
s, d = rpc("omelo_start_conversation", {"p_application_id": aid}, riv_tok)
blocked("outsider opens a conversation on someone else's application", s, d)
s, d = rpc("omelo_start_conversation", {"p_application_id": aid}, vwr_tok)
blocked("viewer-role teammate opens a conversation", s, d)

print("\n2. CONVERSATION")
s, conv = rpc("omelo_start_conversation", {"p_application_id": aid}, emp_tok)
check("recruiter starts a conversation on the application", s == 200 and isinstance(conv, str), f"{s} {msg(conv)}")
s, conv2 = rpc("omelo_start_conversation", {"p_application_id": aid}, wrk_tok)
check("candidate gets the same conversation (one per application)", s == 200 and conv2 == conv, f"{conv} vs {conv2}")
s, d = post("/rest/v1/messages", {"conversation_id": conv, "sender_person_id": wrk_id, "sender_type": "recruiter",
            "kind": "action", "action_type": "offer_accept", "body": "forged"}, wrk_tok)
blocked("direct insert (impersonation / forged action message)", s, d)
s, mid = rpc("omelo_send_message", {"p_conversation_id": conv, "p_body": "Hi Ravi, can you come in for a trial shift on Friday?"}, emp_tok)
check("recruiter sends a message", s == 200 and isinstance(mid, int), f"{s} {msg(mid)}")
s, d = rpc("omelo_send_message", {"p_conversation_id": conv, "p_body": "   "}, emp_tok); blocked("empty message", s, d)
s, d = rpc("omelo_send_message", {"p_conversation_id": conv, "p_body": "x" * 4001}, emp_tok); blocked("over-long message", s, d)
s, d = rpc("omelo_send_message", {"p_conversation_id": conv, "p_body": "let me in"}, riv_tok); blocked("outsider posts", s, d)
s, d = rpc("omelo_send_message", {"p_conversation_id": conv, "p_body": "hello"}, vwr_tok); blocked("viewer-role teammate posts", s, d)

s, n = get(f"/rest/v1/notifications?select=id,type,title,body,deeplink,read_at&person_id=eq.{wrk_id}", wrk_tok)
note = [x for x in n if x["type"] == "message_received"]
check("candidate notified with a preview and a deep link", note and note[0]["deeplink"] == f"/messages/{conv}" and "trial shift" in note[0]["body"], n)
s, d = get(f"/rest/v1/messages?select=body,sender_type,read_at&conversation_id=eq.{conv}", wrk_tok)
check("candidate reads the thread; sender_type set by the server", s == 200 and len(d) == 1 and d[0]["sender_type"] == "recruiter" and d[0]["read_at"] is None, d)
s, d = get(f"/rest/v1/messages?select=body&conversation_id=eq.{conv}", riv_tok); check("outsider cannot read the thread", s == 200 and d == [], d)
s, d = get(f"/rest/v1/messages?select=body&conversation_id=eq.{conv}", vwr_tok); check("viewer-role teammate cannot read the thread", s == 200 and d == [], d)
s, d = get(f"/rest/v1/conversations?select=id&id=eq.{conv}", riv_tok); check("outsider cannot see the conversation", s == 200 and d == [], d)

s, d = rpc("omelo_mark_conversation_read", {"p_conversation_id": conv}, wrk_tok)
check("candidate marks the thread read", s == 200 and d == 1, f"{s} {d}")
s, d = get(f"/rest/v1/notifications?select=read_at&person_id=eq.{wrk_id}&type=eq.message_received", wrk_tok)
check("opening the thread also clears its notification", d and d[0]["read_at"], d)
s, d = rpc("omelo_send_message", {"p_conversation_id": conv, "p_body": "Yes, Friday works. What time?"}, wrk_tok)
check("candidate replies", s == 200, f"{s} {msg(d)}")
s, n = get(f"/rest/v1/notifications?select=title,deeplink&person_id=eq.{emp_id}&type=eq.message_received", emp_tok)
check("recruiter notified of the reply", n and n[0]["deeplink"] == f"/dashboard/messages/{conv}", n)
s, d = get(f"/rest/v1/messages?select=sender_type,read_at&conversation_id=eq.{conv}&order=id", emp_tok)
check("recruiter sees read receipt on their message", d and d[0]["read_at"] and d[1]["sender_type"] == "candidate", d)

print("\n3. ARCHIVE + NOTIFICATION INBOX INTEGRITY")
s, d = patch(f"/rest/v1/conversations?id=eq.{conv}", {"person_archived": True}, wrk_tok)
check("candidate archives their side", s == 200 and d and d[0]["person_archived"], f"{s} {msg(d)}")
s, d = patch(f"/rest/v1/conversations?id=eq.{conv}", {"company_archived": True}, wrk_tok); blocked("candidate archives the employer's side", s, d)
s, d = patch(f"/rest/v1/conversations?id=eq.{conv}", {"subject": "rewritten"}, emp_tok); blocked("employer rewrites the conversation", s, d)
s, d = post("/rest/v1/notifications", {"person_id": wrk_id, "type": "offer_received", "title": "You got the job!"}, wrk_tok)
blocked("client forges a notification", s, d)
nid = note[0]["id"]
s, d = patch(f"/rest/v1/notifications?id=eq.{nid}", {"title": "rewritten"}, wrk_tok); blocked("client rewrites a notification", s, d)
s, d = patch(f"/rest/v1/notifications?id=eq.{nid}", {"read_at": None}, wrk_tok)
check("owner can mark a notification unread", s == 200 and d, f"{s} {msg(d)}")
s, d = get(f"/rest/v1/notifications?select=id&person_id=eq.{wrk_id}", riv_tok); check("outsider cannot read notifications", s == 200 and d == [], d)
s, d = delete(f"/rest/v1/notifications?id=eq.{nid}", wrk_tok); check("owner can delete a notification", s == 200 and d, f"{s} {msg(d)}")

print("\n4. RESPECT WITHDRAWAL")
s, d = rpc("omelo_withdraw_application", {"p_application_id": aid, "p_reason": "Found another job"}, wrk_tok)
check("candidate withdraws", s in (200, 204), f"{s} {msg(d)}")
s, d = rpc("omelo_send_message", {"p_conversation_id": conv, "p_body": "Please reconsider"}, emp_tok)
blocked("employer keeps messaging after withdrawal", s, d)
s, d = rpc("omelo_send_message", {"p_conversation_id": conv, "p_body": "Thanks for understanding"}, wrk_tok)
check("candidate can still write", s == 200, f"{s} {msg(d)}")

print(f"\n{'ALL PASSED' if not FAIL else str(len(FAIL)) + ' FAILED: ' + '; '.join(FAIL)}")
print(f"probe stamp {stamp}")
sys.exit(1 if FAIL else 0)
