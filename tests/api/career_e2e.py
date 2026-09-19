"""Release 7: career intelligence + employer intelligence, as real users.

    python tests/api/career_e2e.py

Worker: an electrician with 3 years' experience sets the goal "Industrial Electrician", sees the gap
(PLC programming, motor controls, industrial safety), gets a development plan, passes an Omelo
assessment (evidence is added on the server), fails one (cooldown), and sees readiness rise.
Employer: a company hiring industrial electricians below the market sees supply, compensation,
match quality, funnels, a hiring-difficulty score, the bottleneck and plain recommendations —
aggregates only. Attacks R7-001 .. R7-006. Creates four probe.* accounts (single phase).
"""
import json, sys, time
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
def skill(slug):
    return get(f"/rest/v1/skills?select=id&slug=eq.{slug}")[1][0]["id"]

# The answer key lives in the migration (64) and here, never in a client response.
KEY = {
    "In ladder logic, what does a normally open (NO) contact do when its input bit is ON (1)?": 1,
    "What is the typical order of a PLC scan cycle?": 1,
    "Which instruction keeps an output ON after the start button is released, until it is reset?": 1,
    "A TON (timer on-delay) done bit turns ON when…": 1,
    "Why are stop buttons usually wired as normally closed (NC) devices?": 1,
    "What is a PLC's analogue input typically used for?": 1,
    "What does a thermal overload relay protect a motor against?": 1,
    "In a three-wire start/stop circuit, what keeps the contactor energised after START is released?": 1,
    "How do you reverse the direction of a three-phase induction motor?": 0,
    "What does a variable frequency drive (VFD) mainly control?": 0,
    "Why is a star-delta starter used on larger motors?": 1,
    "Interlocking the forward and reverse contactors prevents…": 0,
}


def main():
    stamp = str(int(time.time()))
    acc, tok = {}, {}
    for key, name, role in [("emp", "Irfan Plant", "employer"), ("w1", "Kiran Electrician", "worker"),
                            ("w2", "Deepa Industrial", "worker"), ("x", "Rogue Outsider", "employer")]:
        email = f"probe.c{key}.{stamp}@omelo.dev"
        tok[key], pid = signup(email, PW, name, role)
        acc[key] = {"email": email, "id": pid}
    elec, ind = prof("electrician"), prof("industrial-electrician")
    SK = {s: skill(s) for s in ("electrical-wiring", "blueprint-reading", "plc-programming", "motor-controls",
                                "industrial-safety", "hand-tools", "site-safety")}

    print("\n0. PROFILES")
    s, w1 = rpc("omelo_create_work_identity", {"p_label": "Electrician", "p_profession_id": elec}, tok["w1"])
    s2, w2 = rpc("omelo_create_work_identity", {"p_label": "Industrial Electrician", "p_profession_id": ind}, tok["w2"])
    check("identities created", s == 200 and s2 == 200, f"{s} {msg(w1)} / {s2} {msg(w2)}")
    for k, wid in (("w1", w1), ("w2", w2)):
        s, d = rpc("omelo_set_primary_identity", {"p_identity": wid}, tok[k])
        check(f"{k} makes it the main identity", s in (200, 204), f"{s} {msg(d)}")
    patch(f"/rest/v1/work_identities?id=eq.{w1}", {"discoverability": "discoverable", "total_experience_months": 36}, tok["w1"])
    patch(f"/rest/v1/work_identities?id=eq.{w2}", {"discoverability": "discoverable"}, tok["w2"])
    for sk, prof_l, ev in [("electrical-wiring", "advanced", "experience"), ("blueprint-reading", "basic", "self_declared"),
                           ("hand-tools", "advanced", "experience"), ("site-safety", "intermediate", "experience")]:
        s, d = post("/rest/v1/person_skills", {"person_id": acc["w1"]["id"], "work_identity_id": w1, "skill_id": SK[sk],
                    "proficiency": prof_l, "evidence_type": ev, "source": "user"}, tok["w1"])
        check(f"worker 1 lists {sk}", s == 201, f"{s} {msg(d)}")
    for k, wid in (("w1", w1), ("w2", w2)):
        s, d = patch(f"/rest/v1/person_work_preferences?work_identity_id=eq.{wid}", {"seeking": True,
                     "availability": "immediate", "expected_pay_amount": 30000, "expected_pay_period": "month",
                     "pay_currency": "INR"}, tok[k])
        check(f"{k} availability and pay expectation", s == 200 and d, f"{s} {msg(d)}")

    print("\n1. CAREER GOAL AND GAP")
    s, sug = rpc("omelo_suggest_career_goals", {}, tok["w1"])
    ie = next((x for x in (sug or {}).get("suggestions", []) if x["slug"] == "industrial-electrician"), {}) if s == 200 else {}
    check("suggested next roles from Electrician include Industrial Electrician", bool(ie), f"{s} {msg(sug)}")
    check("…with what is missing (PLC, motor controls, industrial safety)",
          {"PLC programming", "Motor controls", "Industrial safety"} <= set(ie.get("missing", [])), ie)
    s, g = rpc("omelo_save_career_goal", {"p": {"profession_id": ind, "target_countries": ["IN"], "generate_plan": True,
               "target_pay_amount": 45000, "target_pay_period": "month", "target_currency": "INR"}}, tok["w1"])
    check("worker sets the goal and gets a development plan", s == 200 and g.get("id"), f"{s} {msg(g)}")
    goal = g.get("id") if s == 200 else None
    s, d = rpc("omelo_save_career_goal", {"p": {"profession_id": ind, "target_currency": "XYZ"}}, tok["w1"]); blocked("a goal in an unknown currency", s, d)
    # a goal keeps its identity when edited, even if another identity is now the main one (fix 67)
    s, others = get(f"/rest/v1/work_identities?select=id&person_id=eq.{acc['w1']['id']}&id=neq.{w1}", tok["w1"])
    other = others[0]["id"] if s == 200 and others else None
    rpc("omelo_set_primary_identity", {"p_identity": other}, tok["w1"])
    s, g2 = rpc("omelo_save_career_goal", {"p": {"id": goal, "target_date": "2028-06-30"}}, tok["w1"])
    check("editing a goal keeps its work identity", s == 200 and g2.get("work_identity_id") == w1, f"{s} {msg(g2)}")
    rpc("omelo_set_primary_identity", {"p_identity": w1}, tok["w1"])
    s, path = rpc("omelo_career_path", {"p_goal": goal}, tok["w1"])
    r0 = (path or {}).get("readiness") if s == 200 else None
    check("career path: readiness between 0 and 100", isinstance(r0, (int, float)) and 0 < r0 < 100, f"{s} {msg(path)}")
    check("…missing: PLC programming, Motor controls, Industrial safety",
          {"PLC programming", "Motor controls", "Industrial safety"} <= set(path.get("missing", [])), path.get("missing"))
    check("…weak: Blueprint reading (self-declared, basic)", "Blueprint reading" in path.get("weak", []), path.get("weak"))
    check("…strong: Electrical wiring (3 years' experience)", "Electrical wiring" in path.get("strong", []), path.get("strong"))
    rec = next((x for x in path.get("recommended", []) if x["skill"] == "PLC programming"), {})
    check("…recommended for PLC: an Omelo assessment and resources", rec.get("assessment") and len(rec.get("resources", [])) >= 2, rec)
    check("…typical transition time shown", (path.get("transition") or {}).get("typical_months") == 24, path.get("transition"))
    plan = path.get("plan", [])
    check("…plan steps for each missing / weak skill", len(plan) >= 4 and any(p["kind"] == "assessment" for p in plan), plan)

    print("\n2. PRIVACY OF CAREER DATA (R7-001)")
    s, d = get(f"/rest/v1/career_goals?select=id&person_id=eq.{acc['w1']['id']}", tok["w2"]); blocked("another worker reads the goal", s, d)
    s, d = get(f"/rest/v1/career_goals?select=id&person_id=eq.{acc['w1']['id']}", tok["emp"]); blocked("an employer reads the goal", s, d)
    s, d = get(f"/rest/v1/career_plan_items?select=id&goal_id=eq.{goal}", tok["w2"]); blocked("another worker reads the plan", s, d)
    s, d = post("/rest/v1/career_plan_items", {"person_id": acc["w2"]["id"], "goal_id": goal, "kind": "custom", "title": "hijack"}, tok["w2"])
    blocked("adding a step to someone else's goal", s, d)
    s, d = rpc("omelo_career_path", {"p_goal": goal}, tok["w2"]); blocked("another worker opens the path", s, d)
    s, d = rpc("omelo_career_path", {"p_goal": goal}); blocked("signed out", s, d)
    s, d = post("/rest/v1/career_plan_items", {"person_id": acc["w1"]["id"], "goal_id": goal, "kind": "custom",
                "title": "Ask my supervisor for PLC work"}, tok["w1"])
    check("the worker adds her own step", s == 201, f"{s} {msg(d)}")
    step = d[0]["id"] if s == 201 else None
    s, d = patch(f"/rest/v1/career_plan_items?id=eq.{step}", {"status": "in_progress"}, tok["w1"])
    check("…and marks it in progress", s == 200 and d and d[0]["status"] == "in_progress", f"{s} {msg(d)}")

    print("\n3. OMELO ASSESSMENTS (R7-002, R7-003)")
    s, d = get("/rest/v1/skill_assessment_questions?select=prompt,answer_index&limit=1", tok["w1"]); blocked("reading the answer key", s, d)
    s, d = get("/rest/v1/skill_assessment_questions?select=prompt&limit=1"); blocked("reading questions signed out", s, d)
    s, a1 = rpc("omelo_start_skill_assessment", {"p_skill": SK["plc-programming"]}, tok["w1"])
    qs = (a1 or {}).get("questions", []) if s == 200 else []
    check("start the PLC assessment: 5 questions", len(qs) == 5, f"{s} {msg(a1)}")
    check("…the answers are not sent", "answer" not in json.dumps(a1).replace("answers", ""), [list(q.keys()) for q in qs])
    s, again = rpc("omelo_start_skill_assessment", {"p_skill": SK["plc-programming"]}, tok["w1"])
    check("starting again resumes the same attempt", s == 200 and again.get("attempt_id") == a1.get("attempt_id"), again)
    s, d = rpc("omelo_submit_skill_assessment", {"p_attempt": a1["attempt_id"], "p_answers": [0, 0]}, tok["w1"]); blocked("submitting too few answers", s, d)
    s, d = rpc("omelo_submit_skill_assessment", {"p_attempt": a1["attempt_id"], "p_answers": [1] * 5}, tok["w2"]); blocked("submitting someone else's attempt", s, d)
    s, res = rpc("omelo_submit_skill_assessment", {"p_attempt": a1["attempt_id"], "p_answers": [KEY[q["prompt"]] for q in qs]}, tok["w1"])
    check("all correct -> passed (graded on the server)", s == 200 and res.get("status") == "passed" and res.get("score_percent") == 100, f"{s} {msg(res)}")
    s, d = rpc("omelo_submit_skill_assessment", {"p_attempt": a1["attempt_id"], "p_answers": [1] * 5}, tok["w1"]); blocked("submitting a finished attempt again", s, d)
    s, ps = get(f"/rest/v1/person_skills?select=evidence_type,proficiency&skill_id=eq.{SK['plc-programming']}&person_id=eq.{acc['w1']['id']}", tok["w1"])
    check("the pass adds PLC programming with 'assessment' evidence", s == 200 and ps and ps[0]["evidence_type"] == "assessment", ps)
    s, a2 = rpc("omelo_start_skill_assessment", {"p_skill": SK["motor-controls"]}, tok["w1"])
    wrong = [(KEY[q["prompt"]] + 1) % len(q["options"]) for q in a2.get("questions", [])] if s == 200 else []
    s, res2 = rpc("omelo_submit_skill_assessment", {"p_attempt": a2.get("attempt_id"), "p_answers": wrong}, tok["w1"])
    check("all wrong -> failed, with a retry time", s == 200 and res2.get("status") == "failed" and res2.get("retry_after"), f"{s} {msg(res2)}")
    s, d = rpc("omelo_start_skill_assessment", {"p_skill": SK["motor-controls"]}, tok["w1"]); blocked("retrying before the cooldown", s, d)
    s, d = post("/rest/v1/person_skills", {"person_id": acc["w1"]["id"], "work_identity_id": w1, "skill_id": SK["motor-controls"],
                "proficiency": "expert", "evidence_type": "assessment", "source": "user"}, tok["w1"])
    blocked("R7-003 claiming 'assessment' evidence directly", s, d)
    s, d = patch(f"/rest/v1/person_skills?person_id=eq.{acc['w1']['id']}&skill_id=eq.{SK['blueprint-reading']}",
                 {"evidence_type": "assessment"}, tok["w1"])
    blocked("upgrading a skill's evidence to 'assessment'", s, d)
    s, d = rpc("omelo_start_skill_assessment", {"p_skill": SK["electrical-wiring"]}, tok["w1"]); blocked("a skill with no assessment", s, d)
    s, path2 = rpc("omelo_career_path", {"p_goal": goal}, tok["w1"])
    check("readiness rises after the pass; PLC is now strong",
          s == 200 and path2.get("readiness", 0) > r0 and "PLC programming" in path2.get("strong", []),
          f"{r0} -> {path2.get('readiness') if s == 200 else path2}")
    last = next((x.get("assessment", {}).get("last") for x in path2.get("recommended", []) if x["skill"] == "Motor controls"), None)
    check("the path shows the failed motor-controls attempt", (last or {}).get("status") == "failed", last)

    print("\n4. MARKET INSIGHTS")
    s, d = rpc("omelo_market_insights", {"p_profession": ind, "p_country": "IN"}); blocked("signed out", s, d)
    s, d = rpc("omelo_market_insights", {"p_profession": ind, "p_country": "IN", "p_currency": "QQQ"}, tok["w1"]); blocked("an unknown currency", s, d)

    print("\n5. EMPLOYER INTELLIGENCE (R7-004, R7-005)")
    s, slug = rpc("omelo_company_slug", {"p_name": f"Pune Plant {stamp}"}, tok["emp"])
    s, co = post("/rest/v1/companies", {"slug": slug, "display_name": f"Pune Plant {stamp}", "country_code": "IN",
                 "size_band": "201-500", "created_by": acc["emp"]["id"]}, tok["emp"])
    if s != 201: raise SystemExit(f"company: {s} {msg(co)}")
    company = co[0]["id"]
    s, loc = get("/rest/v1/locations?select=id&latitude=not.is.null&country_code=eq.IN&kind=eq.city&limit=1")
    loc = loc[0]["id"]
    def job(title, pay):
        s, j = post("/rest/v1/jobs", {"company_id": company, "created_by": acc["emp"]["id"], "title": title, "profession_id": ind,
                    "location_id": loc, "workplace_type": "onsite", "work_type": "full_time", "country_code": "IN",
                    "pay_min": pay, "pay_max": pay, "pay_period": "month", "pay_currency": "INR", "openings": 2,
                    "status": "draft"}, tok["emp"])
        jid = j[0]["id"]
        post("/rest/v1/job_stages", [{"job_id": jid, "name": "New", "position": 1, "maps_to_state": "applied", "is_terminal": False}], tok["emp"])
        post("/rest/v1/job_skills", {"job_id": jid, "skill_id": SK["motor-controls"], "requirement_level": "required", "weight": 1}, tok["emp"])
        patch(f"/rest/v1/jobs?id=eq.{jid}", {"status": "published"}, tok["emp"])
        return jid
    target = job("Industrial Electrician (Line 2)", 25000)
    for t, pay in (("Industrial Electrician (Plant A)", 38000), ("Industrial Electrician (Plant B)", 40000),
                   ("Industrial Electrician (Plant C)", 42000)):
        job(t, pay)
    check("the employer publishes a job below three comparable jobs", bool(target))
    s, app = post("/rest/v1/applications", {"job_id": target, "person_id": acc["w1"]["id"], "company_id": company,
                  "work_identity_id": w1, "identity_snapshot": {}}, tok["w1"])
    check("worker 1 applies (the goal job)", s == 201, f"{s} {msg(app)}")
    rpc("omelo_my_match", {"p_job_id": target, "p_work_identity_id": w1}, tok["w1"])
    rpc("omelo_my_match", {"p_job_id": target, "p_work_identity_id": w2}, tok["w2"])

    s, ji = rpc("omelo_job_intelligence", {"p_job": target}, tok["emp"])
    check("job intelligence for the hiring team", s == 200 and ji.get("job_id") == target, f"{s} {msg(ji)}")
    sup, comp = (ji or {}).get("supply", {}), (ji or {}).get("compensation", {})
    check("supply: workers in the profession and available soon", sup.get("workers_in_profession", 0) >= 1 and "available_soon" in sup, sup)
    check("compensation: below market (3 comparable jobs, median 40,000 INR)",
          comp.get("position") == "below_market" and (comp.get("market_jobs_monthly") or {}).get("median") == 40000, comp)
    check("R7-005 worker expectations hidden below 5 workers", comp.get("worker_expectations_monthly") is None, comp)
    fq = ji.get("application_funnel", {})
    check("application funnel counts the application", fq.get("applied") == 1, fq)
    check("match quality from the matcher (scored, missing skills)",
          ji.get("match_quality", {}).get("scored", 0) >= 1, ji.get("match_quality"))
    check("difficulty score and label", isinstance(ji.get("difficulty", {}).get("score"), (int, float))
          and ji["difficulty"].get("label") in ("easy", "moderate", "hard", "very_hard"), ji.get("difficulty"))
    check("a bottleneck with an explanation", ji.get("bottleneck", {}).get("stage") in ("supply", "compensation")
          and ji["bottleneck"].get("explanation"), ji.get("bottleneck"))
    recs = " ".join(ji.get("recommendations", []))
    check("recommendations: raise pay, open the unread application", "below the market median" in recs and "not been opened" in recs, recs)
    dump = json.dumps(ji)
    check("R7-004 aggregates only: no names, emails or person ids",
          all(v not in dump for k in ("w1", "w2") for v in (acc[k]["id"], acc[k]["email"])) and "Kiran" not in dump and "Deepa" not in dump, "leak")
    s, d = rpc("omelo_job_intelligence", {"p_job": target}, tok["x"]); blocked("an outsider reads job intelligence", s, d)
    s, d = rpc("omelo_job_intelligence", {"p_job": target}, tok["w1"]); blocked("a worker reads job intelligence", s, d)
    s, ci = rpc("omelo_company_intelligence", {"p_company": company}, tok["emp"])
    check("company view: open jobs ranked by difficulty with the top recommendation",
          s == 200 and ci["summary"]["open_jobs"] == 4 and ci["jobs"][0].get("difficulty"), f"{s} {msg(ci)}")
    check("…the below-market job is the hardest", s == 200 and ci["jobs"][0]["job_id"] == target, [j["title"] for j in ci.get("jobs", [])] if s == 200 else ci)
    s, d = rpc("omelo_company_intelligence", {"p_company": company}, tok["x"]); blocked("an outsider reads company intelligence", s, d)

    s, mi = rpc("omelo_market_insights", {"p_profession": ind, "p_country": "IN"}, tok["w1"])
    check("market insights for the worker: open jobs, pay range, skills in demand",
          s == 200 and mi.get("open_jobs", 0) >= 4 and (mi.get("pay_monthly") or {}).get("currency") == "INR"
          and any(x["name"] == "Motor controls" for x in mi.get("skills_in_demand", [])), f"{s} {msg(mi)}")
    s, path3 = rpc("omelo_career_path", {"p_goal": goal}, tok["w1"])
    check("the path lists open jobs for the goal (not the one already applied to) with match scores",
          s == 200 and len(path3.get("jobs", [])) >= 3 and all(x["job_id"] != target for x in path3["jobs"])
          and all(isinstance(x.get("score"), int) for x in path3["jobs"]), path3.get("jobs") if s == 200 else path3)
    check("…and the market pay for the goal in her currency", (path3.get("market") or {}).get("pay_monthly", {}).get("currency") == "INR",
          path3.get("market"))

    print(f"\n{'ALL PASSED' if not FAIL else str(len(FAIL)) + ' FAILED: ' + '; '.join(FAIL)}")
    sys.exit(1 if FAIL else 0)


if __name__ == "__main__":
    main()
