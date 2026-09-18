"""Omelo Meet end-to-end, as real users (publishable key + user JWTs).

    python tests/api/meet_e2e.py

Covers scheduling with a panel, rooms, the waiting room, admission, chat,
private feedback, abuse reports, host controls, reschedule/cancel, and the
meet-token / meet-control Edge Functions. Creates four probe.* accounts per
run (signup allows 10/hour per IP); clean up as described in
hiring_loop_e2e.py.

Without LiveKit secrets configured, an admitted join returns 503
meet_not_configured — the test accepts that, and checks the token when the
media server IS configured.
"""
import base64, datetime as dt, json, sys, time
from omelo_api import *

FAIL = []
def check(label, ok, detail=""):
    print(f"  {'PASS' if ok else 'FAIL'} | {label}" + (f" | {detail}" if detail and not ok else ""))
    if not ok: FAIL.append(label)

def blocked(label, s, d):
    check(f"blocked: {label}", s >= 400 or (isinstance(d, list) and len(d) == 0), f"HTTP {s} {msg(d)}")

def fn(name, body, tok):
    return post(f"/functions/v1/{name}", body, tok)

def iso(minutes):
    return (dt.datetime.now(dt.timezone.utc) + dt.timedelta(minutes=minutes)).replace(microsecond=0).isoformat()

stamp = str(int(time.time()))
PW = "ProbePass2026!"
emp_tok, emp_id = signup(f"probe.emp.{stamp}@omelo.dev", PW, "Sarah Host", "employer")
pnl_tok, pnl_id = signup(f"probe.pnl.{stamp}@omelo.dev", PW, "Imran Interviewer", "employer")
wrk_tok, wrk_id = signup(f"probe.wrk.{stamp}@omelo.dev", PW, "Ravi Candidate", "worker")
riv_tok, riv_id = signup(f"probe.riv.{stamp}@omelo.dev", PW, "Rival Person", "worker")

# --- setup: company, job for a cook, application, panel member ---------------
s, slug = rpc("omelo_company_slug", {"p_name": f"Meet Kitchens {stamp}"}, emp_tok)
s, co = post("/rest/v1/companies", {"slug": slug, "display_name": f"Meet Kitchens {stamp}", "country_code": "IN",
             "size_band": "11-50", "created_by": emp_id}, emp_tok); cid = co[0]["id"]
s, loc = get("/rest/v1/locations?select=id&latitude=not.is.null&country_code=eq.IN&limit=1")
s, prof = get("/rest/v1/professions?select=id,category_id&slug=eq.cook")
s, job = post("/rest/v1/jobs", {"company_id": cid, "created_by": emp_id, "title": "Tandoor Cook",
              "profession_id": prof[0]["id"], "category_id": prof[0]["category_id"], "location_id": loc[0]["id"],
              "location_text": "Sector 18 Market, Noida",
              "workplace_type": "onsite", "work_type": "full_time", "pay_min": 20000, "pay_max": 26000,
              "pay_period": "month", "pay_currency": "INR", "accepts_no_experience": True, "status": "draft"}, emp_tok)
jid = job[0]["id"]
post("/rest/v1/job_stages", [{"job_id": jid, "name": n, "position": i + 1, "maps_to_state": m, "is_terminal": t}
     for i, (n, m, t) in enumerate([("New", "applied", False), ("Interview", "interview", False),
                                    ("Offer", "offer", False), ("Hired", "hired", True), ("No", "rejected", True)])], emp_tok)
patch(f"/rest/v1/jobs?id=eq.{jid}", {"status": "published"}, emp_tok)
s, wi = get(f"/rest/v1/work_identities?select=id&person_id=eq.{wrk_id}&is_primary=eq.true", wrk_tok)
s, app = post("/rest/v1/applications", {"job_id": jid, "person_id": wrk_id, "company_id": cid,
              "work_identity_id": wi[0]["id"], "identity_snapshot": {}}, wrk_tok); aid = app[0]["id"]
s, d = post("/rest/v1/company_members", {"company_id": cid, "person_id": pnl_id, "role": "interviewer", "is_active": True}, emp_tok)
blocked("adding a team member without their consent", s, d)
s, inv = rpc("omelo_invite_team_member", {"p_company": cid, "p_email": f"probe.pnl.{stamp}@omelo.dev", "p_role": "interviewer"}, emp_tok)
s2, d = rpc("omelo_accept_team_invitation", {"p_invitation": inv}, pnl_tok)
check("owner invites an interviewer, who accepts and joins the hiring team", s == 200 and s2 == 200, f"{s} {s2} {msg(d)}")
s, d = post("/rest/v1/job_interview_rounds", [
    {"job_id": jid, "position": 1, "name": "Technical Interview", "kind": "technical", "meeting_mode": "omelo_meet", "duration_minutes": 45},
    {"job_id": jid, "position": 2, "name": "Kitchen Trial", "kind": "practical", "meeting_mode": "in_person", "duration_minutes": 60},
    {"job_id": jid, "position": 3, "name": "Hiring Manager", "kind": "hiring_manager", "meeting_mode": "omelo_meet", "duration_minutes": 30}], emp_tok)
check("employer defines the interview process for the job", s == 201 and len(d) == 3, f"{s} {msg(d)}")
s, d = get(f"/rest/v1/job_interview_rounds?select=name,position&job_id=eq.{jid}&order=position", wrk_tok)
check("applicant can see the planned process", s == 200 and [r["name"] for r in d] == ["Technical Interview", "Kitchen Trial", "Hiring Manager"], d)
s, d = get(f"/rest/v1/job_interview_rounds?select=name&job_id=eq.{jid}", riv_tok)
check("non-applicant cannot see it", s == 200 and d == [], d)

print("\n1. SCHEDULE ON OMELO MEET")
s, d = rpc("omelo_schedule_interview", {"p_application_id": aid, "p_scheduled_at": iso(5)}, riv_tok)
blocked("outsider schedules an interview", s, d)
s, d = rpc("omelo_schedule_interview", {"p_application_id": aid, "p_scheduled_at": iso(5),
           "p_interviewer_ids": [emp_id, riv_id]}, emp_tok)
blocked("panel includes someone outside the hiring team", s, d)
s, iid = rpc("omelo_schedule_interview", {"p_application_id": aid, "p_scheduled_at": iso(5), "p_duration_minutes": 45,
             "p_interviewer_ids": [emp_id, pnl_id], "p_instructions": "Keep your ID ready", "p_timezone": "Asia/Kolkata"}, emp_tok)
check("schedule Omelo Meet interview with a 2-person panel", s == 200 and isinstance(iid, str), f"{s} {msg(iid)}")
s, iv = get(f"/rest/v1/interviews?select=round,round_name,round_kind,meeting_mode,type,status&id=eq.{iid}", wrk_tok)
check("round name comes from the job's planned process", iv and iv[0]["round_name"] == "Technical Interview" and iv[0]["round_kind"] == "technical", iv)
check("meeting mode is Omelo Meet", iv and iv[0]["meeting_mode"] == "omelo_meet", iv)
s, room = get(f"/rest/v1/interview_rooms?select=room_name,status,waiting_room,recording_enabled&interview_id=eq.{iid}", wrk_tok)
check("candidate can see their room", s == 200 and len(room) == 1 and room[0]["room_name"].startswith("om-"), f"{s} {msg(room)}")
room_name = room[0]["room_name"] if room else ""
check("waiting room on, recording off", room and room[0]["waiting_room"] and room[0]["recording_enabled"] is False, room)
s, d = get(f"/rest/v1/interview_rooms?select=room_name&interview_id=eq.{iid}", riv_tok)
check("outsider cannot discover the room", s == 200 and d == [], d)
s, q = get(f"/rest/v1/interview_questions?select=question,source&interview_id=eq.{iid}&order=position", emp_tok)
check("profession questions seeded for a cook", s == 200 and len(q) >= 4 and any("cuisine" in x["question"].lower() for x in q), f"{s} {q[:2] if isinstance(q, list) else q}")
s, d = get(f"/rest/v1/interview_questions?select=question&interview_id=eq.{iid}", wrk_tok)
check("candidate cannot see interview questions", s == 200 and d == [], d)
s, d = get(f"/rest/v1/interview_questions?select=question&interview_id=eq.{iid}", pnl_tok)
check("panel interviewer can see questions", s == 200 and len(d) >= 4, f"{s} {msg(d)}")
s, d = get(f"/rest/v1/persons?select=display_name&id=eq.{wrk_id}", pnl_tok)
check("panel interviewer (role: interviewer) can read the candidate's profile", s == 200 and len(d) == 1, f"{s} {d}")
s, d = get(f"/rest/v1/work_identities?select=label&person_id=eq.{wrk_id}", pnl_tok)
check("panel interviewer can read the candidate's work identity", s == 200 and len(d) >= 1, f"{s} {d}")
s, d = rpc("omelo_rank_applicants", {"p_job_id": jid}, emp_tok)
s, d = get(f"/rest/v1/matches?select=score&person_id=eq.{wrk_id}&job_id=eq.{jid}", pnl_tok)
check("panel interviewer can read the match analysis for this job", s == 200 and len(d) == 1, f"{s} {d}")
s, d = get(f"/rest/v1/persons?select=display_name&id=eq.{wrk_id}", riv_tok)
check("outsider cannot read the candidate's profile", s == 200 and d == [], d)
s, d = patch(f"/rest/v1/interview_rooms?interview_id=eq.{iid}", {"recording_enabled": True}, emp_tok)
blocked("employer switches recording on", s, d)
s, d = post("/rest/v1/interview_rooms", {"interview_id": iid, "opens_at": iso(0), "closes_at": iso(60)}, emp_tok)
blocked("client creates a room directly", s, d)
s, d = patch(f"/rest/v1/interviews?id=eq.{iid}", {"meeting_mode": "phone"}, emp_tok)
blocked("employer changes format directly", s, d)

print("\n2. JOIN: WAITING ROOM AND ADMISSION")
s, d = fn("meet-token", {"room_name": room_name}, riv_tok); blocked("outsider asks for a token", s, d)
s, d = fn("meet-token", {"room_name": room_name}, wrk_tok)
check("candidate lands in the waiting room", s == 200 and d.get("state") == "waiting", f"{s} {d}")
check("waiting response carries interview context", s == 200 and d.get("interview", {}).get("round_name") == "Technical Interview", d)
s, d = rpc("omelo_meet_admit", {"p_interview_id": iid, "p_person_id": wrk_id}, wrk_tok); blocked("candidate admits themself", s, d)
s, d = rpc("omelo_meet_admit", {"p_interview_id": iid, "p_person_id": wrk_id}, riv_tok); blocked("outsider admits the candidate", s, d)
s, d = get(f"/rest/v1/interview_participants?select=person_id,role,status&interview_id=eq.{iid}", wrk_tok)
check("before admission the candidate sees only themself", s == 200 and len(d) == 1, d)
s, d = get(f"/rest/v1/interview_participants?select=person_id,role,status&interview_id=eq.{iid}&status=eq.waiting", emp_tok)
check("host sees the candidate waiting", s == 200 and len(d) == 1 and d[0]["person_id"] == wrk_id, d)

s, host = fn("meet-token", {"room_name": room_name}, emp_tok)
host_ok = (s == 200 and host.get("state") == "admitted" and host.get("token")) or (s == 503 and host.get("code") == "meet_not_configured")
check("host is admitted straight in (token, or 503 until LiveKit keys are set)", host_ok, f"{s} {host}")
MEDIA = s == 200
if MEDIA:
    claims = json.loads(base64.urlsafe_b64decode(host["token"].split(".")[1] + "=="))
    check("token is scoped to this room and expires within 10 min", claims["video"]["room"] == room_name and claims["exp"] - time.time() <= 600, claims)
    check("client token has no media-server admin rights", not claims["video"].get("roomAdmin"), claims)
s, d = rpc("omelo_meet_admit", {"p_interview_id": iid, "p_person_id": wrk_id}, pnl_tok)
check("interviewer on the panel admits the candidate", s in (200, 204), f"{s} {msg(d)}")
s, d = fn("meet-token", {"room_name": room_name}, wrk_tok)
check("admitted candidate gets in", (s == 200 and d.get("state") == "admitted") or (s == 503 and d.get("code") == "meet_not_configured"), f"{s} {d}")
s, d = get(f"/rest/v1/interview_participants?select=display_name,role,status&interview_id=eq.{iid}", wrk_tok)
check("inside the room the candidate sees who is on the call", s == 200 and len(d) == 3, d)

print("\n3. CHAT")
s, d = post("/rest/v1/meet_messages", {"interview_id": iid, "sender_id": wrk_id, "sender_name": "Sarah Host (fake)", "body": "Hello, can you hear me?"}, wrk_tok)
check("candidate sends a chat message", s == 201, f"{s} {msg(d)}")
check("sender name stamped by the server, not the client", s == 201 and d[0]["sender_name"] == "Ravi Candidate", d)
s, d = post("/rest/v1/meet_messages", {"interview_id": iid, "sender_id": emp_id, "body": "impersonation"}, wrk_tok)
blocked("candidate sends as the host", s, d)
s, d = post("/rest/v1/meet_messages", {"interview_id": iid, "sender_id": riv_id, "body": "let me in"}, riv_tok)
blocked("outsider posts into the room", s, d)
s, d = get(f"/rest/v1/meet_messages?select=body&interview_id=eq.{iid}", riv_tok)
check("outsider cannot read the chat", s == 200 and d == [], d)
s, d = get(f"/rest/v1/meet_messages?select=body,sender_name&interview_id=eq.{iid}", emp_tok)
check("host reads the chat", s == 200 and len(d) == 1, d)

print("\n4. PRIVATE FEEDBACK")
s, qs = get(f"/rest/v1/interview_questions?select=id&interview_id=eq.{iid}&order=position", pnl_tok)
s, d = rpc("omelo_save_interview_feedback", {"p_interview_id": iid, "p_recommendation": "hire", "p_submit": True}, wrk_tok)
blocked("candidate writes feedback", s, d)
s, d = rpc("omelo_save_interview_feedback", {"p_interview_id": iid, "p_strengths": "Fast, clean", "p_submit": True}, pnl_tok)
blocked("submit without a recommendation", s, d)
s, fid = rpc("omelo_save_interview_feedback", {"p_interview_id": iid, "p_strengths": "Fast, clean knife work",
             "p_concerns": "Tandoor temperature control", "p_rating": 4,
             "p_competencies": [{"name": "Technical skills", "assessment": "strong"}, {"name": "Communication", "assessment": "strong"}],
             "p_skills": [{"name": "Tandoor", "demonstrated": True}, {"name": "Menu costing", "demonstrated": False}],
             "p_answers": [{"question_id": qs[0]["id"], "evaluation": "strong", "notes": "North Indian, Mughlai"}]}, pnl_tok)
check("interviewer saves a draft with answers", s == 200 and isinstance(fid, str), f"{s} {msg(fid)}")
s, d = rpc("omelo_save_interview_feedback", {"p_interview_id": iid, "p_recommendation": "strong_hire", "p_rating": 4,
           "p_strengths": "Fast, clean knife work", "p_concerns": "Tandoor temperature control", "p_submit": True}, pnl_tok)
check("interviewer submits", s == 200, f"{s} {msg(d)}")
s, d = get(f"/rest/v1/interview_feedback?select=recommendation&interview_id=eq.{iid}", wrk_tok)
check("candidate cannot read feedback", s == 200 and d == [], d)
s, d = get(f"/rest/v1/interview_answers?select=notes&interview_id=eq.{iid}", wrk_tok)
check("candidate cannot read answers", s == 200 and d == [], d)
s, d = get(f"/rest/v1/interview_feedback?select=recommendation,status,competencies,skills_assessed&interview_id=eq.{iid}", emp_tok)
check("hiring team reads submitted feedback with competencies and skills",
      s == 200 and len(d) == 1 and d[0]["status"] == "submitted" and d[0]["recommendation"] == "strong_hire"
      and len(d[0]["competencies"]) == 2 and len(d[0]["skills_assessed"]) == 2, d)
s, d = get(f"/rest/v1/interview_feedback?select=recommendation&interview_id=eq.{iid}", riv_tok)
check("outsider cannot read feedback", s == 200 and d == [], d)

print("\n5. SAFETY + HOST CONTROLS")
s, rid = rpc("omelo_report_meet_abuse", {"p_interview_id": iid, "p_reason": "other", "p_details": "test report"}, wrk_tok)
check("candidate can report abuse from the room", s == 200 and isinstance(rid, str), f"{s} {msg(rid)}")
s, d = rpc("omelo_report_meet_abuse", {"p_interview_id": iid, "p_reason": "other"}, riv_tok)
blocked("outsider files a report on a room they are not in", s, d)
s, d = fn("meet-control", {"interview_id": iid, "action": "end"}, wrk_tok); blocked("candidate ends the interview", s, d)
s, d = fn("meet-control", {"interview_id": iid, "action": "remove", "person_id": emp_id}, pnl_tok); blocked("interviewer removes the host", s, d)
s, d = fn("meet-control", {"interview_id": iid, "action": "end"}, emp_tok)
check("host ends the interview", s == 200 and d.get("ok"), f"{s} {d}")
s, d = get(f"/rest/v1/interviews?select=status,completed_at&id=eq.{iid}", wrk_tok)
check("interview is completed", d and d[0]["status"] == "completed" and d[0]["completed_at"], d)
s, d = get(f"/rest/v1/interview_rooms?select=status&interview_id=eq.{iid}", wrk_tok)
check("room is closed", d and d[0]["status"] == "ended", d)
s, d = fn("meet-token", {"room_name": room_name}, wrk_tok); blocked("rejoin after the end", s, d)
s, d = get(f"/rest/v1/applications?select=state&id=eq.{aid}", wrk_tok)
check("application stays in interview (final review) for the employer to decide", d and d[0]["state"] == "interview", d)
s, n = get(f"/rest/v1/notifications?select=title&person_id=eq.{wrk_id}&order=id", wrk_tok)
check("candidate told the interview was submitted", any(x["title"] == "Interview completed" for x in n), n)
s, n = get(f"/rest/v1/notifications?select=title&person_id=eq.{pnl_id}", pnl_tok)
check("panel asked for feedback", any(x["title"] == "Submit interview feedback" for x in n), n)

print("\n6. NEXT ROUNDS, TOO EARLY, RESCHEDULE, CANCEL")
s, iid2 = rpc("omelo_schedule_interview", {"p_application_id": aid, "p_scheduled_at": iso(60 * 24)}, emp_tok)
check("schedule round 2 with no format chosen", s == 200, f"{s} {msg(iid2)}")
s, iv2 = get(f"/rest/v1/interviews?select=round,round_name,meeting_mode,duration_minutes,location_text&id=eq.{iid2}", wrk_tok)
check("round 2 follows the plan: in-person Kitchen Trial, 60 min, at the job's address",
      iv2 and iv2[0]["round"] == 2 and iv2[0]["round_name"] == "Kitchen Trial" and iv2[0]["meeting_mode"] == "in_person"
      and iv2[0]["duration_minutes"] == 60 and iv2[0]["location_text"] == "Sector 18 Market, Noida", iv2)
s, d = get(f"/rest/v1/interview_rooms?select=id&interview_id=eq.{iid2}", emp_tok)
check("in-person round has no Meet room", s == 200 and d == [], d)
s, n = get(f"/rest/v1/notifications?select=title&person_id=eq.{wrk_id}&order=id.desc&limit=1", wrk_tok)
check("candidate told they were invited to the next round", n and n[0]["title"] == "Invited to the next round", n)

s, iid5 = rpc("omelo_schedule_interview", {"p_application_id": aid, "p_scheduled_at": iso(60 * 48)}, emp_tok)
check("schedule round 3 (planned Hiring Manager on Omelo Meet)", s == 200, f"{s} {msg(iid5)}")
s, room3 = get(f"/rest/v1/interview_rooms?select=room_name&interview_id=eq.{iid5}", wrk_tok)
s, d = fn("meet-token", {"room_name": room3[0]["room_name"] if room3 else ""}, wrk_tok)
check("joining two days early returns a countdown", s == 200 and d.get("state") == "too_early" and d.get("opens_at"), f"{s} {d}")
s, d = rpc("omelo_reschedule_interview", {"p_interview_id": iid5, "p_scheduled_at": iso(60 * 72), "p_reason": "Manager travelling"}, emp_tok)
check("reschedule round 3", s in (200, 204), f"{s} {msg(d)}")
s, d = rpc("omelo_cancel_interview", {"p_interview_id": iid5, "p_reason": "I have a family function that day"}, wrk_tok)
check("candidate cancels with a reason", s in (200, 204), f"{s} {msg(d)}")
s, d = get(f"/rest/v1/interview_rooms?select=status&interview_id=eq.{iid5}", wrk_tok)
check("cancelled interview closes its room", d and d[0]["status"] == "cancelled", d)
s, n = get(f"/rest/v1/notifications?select=title&person_id=eq.{emp_id}", emp_tok)
check("host told the candidate cannot attend", any(x["title"] == "Candidate cannot attend" for x in n), n)

s, iid3 = rpc("omelo_schedule_interview", {"p_application_id": aid, "p_scheduled_at": iso(60 * 24), "p_meeting_mode": "phone",
              "p_round_name": "Reference call",
              "p_questions": [{"question": "Can you start on Monday?", "category": "availability", "required": True}]}, emp_tok)
check("phone interview with a custom question", s == 200, f"{s} {msg(iid3)}")
s, d = get(f"/rest/v1/interview_rooms?select=id&interview_id=eq.{iid3}", emp_tok)
check("phone interview has no room", s == 200 and d == [], d)
s, d = get(f"/rest/v1/interview_questions?select=question,source,required&interview_id=eq.{iid3}", emp_tok)
check("custom question stored", d and d[0]["question"] == "Can you start on Monday?" and d[0]["source"] == "custom" and d[0]["required"], d)
s, d = rpc("omelo_complete_interview", {"p_interview_id": iid3, "p_recommendation": "hire", "p_rating": 4, "p_notes": "Can start Monday"}, emp_tok)
check("complete phone interview with feedback", s in (200, 204), f"{s} {msg(d)}")
s, d = get(f"/rest/v1/interview_feedback?select=recommendation,status&interview_id=eq.{iid3}", emp_tok)
check("its feedback lands in the structured feedback table", d and d[0]["status"] == "submitted", d)

s, d = patch(f"/rest/v1/company_members?company_id=eq.{cid}&person_id=eq.{pnl_id}", {"is_active": False}, emp_tok)
check("owner deactivates the interviewer", s == 200 and d, f"{s} {msg(d)}")
s, d = get(f"/rest/v1/persons?select=display_name&id=eq.{wrk_id}", pnl_tok)
check("a removed teammate loses access to the candidate", s == 200 and d == [], d)

print("\n7. CLIENTS CANNOT TOUCH THE OUTBOX")
s, d = get("/rest/v1/outbound_messages?select=id&limit=1", emp_tok); blocked("employer reads the email outbox", s, d)
s, d = rpc("omelo_comms_claim", {"p_limit": 5}, emp_tok); blocked("client claims outbox messages", s, d)

print(f"\n{'ALL PASSED' if not FAIL else str(len(FAIL)) + ' FAILED: ' + '; '.join(FAIL)}")
print(f"media server configured: {MEDIA}   probe stamp {stamp}   interview {iid}")
sys.exit(1 if FAIL else 0)
