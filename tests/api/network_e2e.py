"""Release 9: the professional network, as real users.

    python tests/api/network_e2e.py

Three workers and an organization. One worker posts publicly and to connections only; the
organization posts an update and shares its own job. People react, comment, reply, share, save,
follow, connect, mute, block and report. The feed is checked tab by tab, and every boundary is
attacked: a stranger reading a connections-only post, editing someone else's post, writing a
reaction count by hand, sharing a draft job, connecting with someone who blocked you.

Attacks R9-001 .. R9-008. Creates five probe.* accounts (single phase).
"""
import json, sys, time
from omelo_api import *

PW = "ProbePass2026!"
FAIL = []
def check(label, ok, detail=""):
    print(f"  {'PASS' if ok else 'FAIL'} | {label}" + (f" | {detail}" if detail and not ok else ""))
    if not ok: FAIL.append(label)
def blocked(label, s, d):
    check(f"blocked: {label}", s >= 400 or (isinstance(d, list) and len(d) == 0) or d is None, f"HTTP {s} {msg(d)}")
def prof(slug):
    return get(f"/rest/v1/professions?select=id&slug=eq.{slug}")[1][0]["id"]
def ids(feed):
    return [p["id"] for p in (feed or {}).get("posts", [])]


def main():
    stamp = str(int(time.time()))
    acc, tok = {}, {}
    for key, name, role in [("w1", "Nadia Writer", "worker"), ("w2", "Omar Reader", "worker"),
                            ("w3", "Sara Stranger", "worker"), ("emp", "Elena Employer", "employer"),
                            ("x", "Rogue Outsider", "worker")]:
        email = f"probe.n{key}.{stamp}@omelo.dev"
        tok[key], pid = signup(email, PW, name, role)
        acc[key] = {"email": email, "id": pid}
    nurse = prof("nurse")

    print("\n0. PROFILES AND AN ORGANIZATION")
    for k in ("w1", "w2", "w3"):
        s, wid = rpc("omelo_create_work_identity", {"p_label": "Registered Nurse", "p_profession_id": nurse}, tok[k])
        acc[k]["identity"] = wid
        patch(f"/rest/v1/persons?id=eq.{acc[k]['id']}", {"headline": f"Nurse · {k}"}, tok[k])
    s, slug = rpc("omelo_company_slug", {"p_name": f"Northside Clinic {stamp}"}, tok["emp"])
    s, co = post("/rest/v1/companies", {"slug": slug, "display_name": f"Northside Clinic {stamp}", "country_code": "IN",
                 "size_band": "51-200", "created_by": acc["emp"]["id"]}, tok["emp"])
    if s != 201: raise SystemExit(f"company: {s} {msg(co)}")
    org = co[0]["id"]
    s, loc = get("/rest/v1/locations?select=id&latitude=not.is.null&country_code=eq.IN&kind=eq.city&limit=1")
    s, j = post("/rest/v1/jobs", {"company_id": org, "created_by": acc["emp"]["id"], "title": "Staff Nurse (night)",
                "profession_id": nurse, "location_id": loc[0]["id"], "workplace_type": "onsite", "work_type": "full_time",
                "country_code": "IN", "pay_min": 40000, "pay_max": 48000, "pay_period": "month", "pay_currency": "INR",
                "status": "draft"}, tok["emp"])
    job = j[0]["id"]
    post("/rest/v1/job_stages", [{"job_id": job, "name": "New", "position": 1, "maps_to_state": "applied", "is_terminal": False}], tok["emp"])
    s, d = post("/rest/v1/jobs", {"company_id": org, "created_by": acc["emp"]["id"], "title": "Draft only",
                "profession_id": nurse, "location_id": loc[0]["id"], "workplace_type": "onsite", "work_type": "full_time",
                "country_code": "IN", "status": "draft"}, tok["emp"])
    draft_job = d[0]["id"]
    patch(f"/rest/v1/jobs?id=eq.{job}", {"status": "published"}, tok["emp"])
    check("organization and a published job are ready", bool(job and org))

    print("\n1. POSTING (R9-001)")
    s, p1 = rpc("omelo_create_post", {"p": {"body": "First day on the new ward — the team made it easy.",
               "visibility": "public", "work_identity_id": acc["w1"]["identity"]}}, tok["w1"])
    check("a worker writes a public post", s == 200 and p1.get("id") and p1["author"]["type"] == "person", f"{s} {msg(p1)}")
    public_post = p1.get("id") if s == 200 else None
    s, p2 = rpc("omelo_create_post", {"p": {"body": "Only my connections should read this one.",
               "visibility": "connections"}}, tok["w1"])
    check("…and one for connections only", s == 200 and p2.get("visibility") == "connections", f"{s} {msg(p2)}")
    private_post = p2.get("id") if s == 200 else None
    s, d = rpc("omelo_create_post", {"p": {"visibility": "public"}}, tok["w1"])
    blocked("an empty post", s, d)
    s, o1 = rpc("omelo_create_post", {"p": {"company_id": org, "body": "We are growing our night team.",
               "visibility": "public"}}, tok["emp"])
    check("the organization posts an update", s == 200 and o1["author"]["type"] == "organization", f"{s} {msg(o1)}")
    org_post = o1.get("id") if s == 200 else None
    s, o2 = rpc("omelo_create_post", {"p": {"company_id": org, "job_id": job, "body": "Hiring: Staff Nurse (night).",
               "visibility": "public"}}, tok["emp"])
    check("…and shares its own published job", s == 200 and (o2.get("job") or {}).get("id") == job, f"{s} {msg(o2)}")
    job_post = o2.get("id") if s == 200 else None
    s, d = rpc("omelo_create_post", {"p": {"company_id": org, "job_id": draft_job, "body": "x"}}, tok["emp"])
    blocked("R9-003 sharing a job that is not published", s, d)
    s, d = rpc("omelo_create_post", {"p": {"company_id": org, "body": "x"}}, tok["w1"])
    blocked("posting as an organization you do not belong to", s, d)
    s, d = post("/rest/v1/posts", {"author_person_id": acc["w2"]["id"], "body": "not mine"}, tok["w1"])
    blocked("R9-001 writing a post as someone else", s, d)

    print("\n2. VISIBILITY (R9-002)")
    s, seen = rpc("omelo_post_detail", {"p_post": public_post})
    check("signed out, a public post is readable", s == 200 and seen and seen.get("id") == public_post, f"{s} {msg(seen)}")
    s, seen = rpc("omelo_post_detail", {"p_post": private_post})
    check("signed out, a connections-only post is not", s == 200 and seen is None, f"{s} {msg(seen)}")
    s, seen = rpc("omelo_post_detail", {"p_post": private_post}, tok["w3"])
    check("a stranger cannot read it either", s == 200 and seen is None, f"{s} {msg(seen)}")
    s, d = get(f"/rest/v1/posts?select=id,body&id=eq.{private_post}", tok["w3"])
    blocked("…nor straight from the table", s, d)
    s, mine = rpc("omelo_person_posts", {"p_person": acc["w1"]["id"]})
    check("signed out, a person's public posts are listed", s == 200 and [x["id"] for x in mine] == [public_post], f"{s} {msg(mine)}")
    s, of = rpc("omelo_organization_feed", {"p_company": org})
    check("the public organization feed works signed out", s == 200 and len(of.get("posts", [])) == 2
          and of["organization"]["type"] == "organization", f"{s} {msg(of)}")

    print("\n3. ENGAGEMENT (R9-004)")
    s, r = rpc("omelo_react_to_post", {"p_post": public_post, "p_kind": "celebrate"}, tok["w2"])
    check("a reader reacts", s == 200 and r.get("reactions") == 1, f"{s} {msg(r)}")
    s, r = rpc("omelo_react_to_post", {"p_post": public_post, "p_kind": "support"}, tok["w2"])
    check("…changes the reaction, without doubling the count", s == 200 and r.get("reactions") == 1, f"{s} {msg(r)}")
    s, d = rpc("omelo_react_to_post", {"p_post": public_post, "p_kind": "applause"}, tok["w2"])
    blocked("an invented reaction", s, d)
    s, d = rpc("omelo_react_to_post", {"p_post": private_post, "p_kind": "like"}, tok["w3"])
    blocked("reacting to a post you cannot see", s, d)
    s, c1 = rpc("omelo_comment_on_post", {"p_post": public_post, "p_body": "Welcome to the ward!"}, tok["w2"])
    check("a reader comments", s == 200 and c1.get("id"), f"{s} {msg(c1)}")
    s, c2 = rpc("omelo_comment_on_post", {"p_post": public_post, "p_body": "Thank you!", "p_parent": c1.get("id")}, tok["w1"])
    check("the author replies", s == 200 and c2.get("id"), f"{s} {msg(c2)}")
    s, d = rpc("omelo_comment_on_post", {"p_post": public_post, "p_body": "third level", "p_parent": c2.get("id")}, tok["w2"])
    blocked("a reply to a reply (threads stay one deep)", s, d)
    s, comments = rpc("omelo_post_comments", {"p_post": public_post})
    check("comments come back with their replies", s == 200 and len(comments) == 1 and len(comments[0]["thread"]) == 1, f"{s} {msg(comments)}")
    s, d = patch(f"/rest/v1/posts?id=eq.{public_post}", {"reaction_count": 999}, tok["w1"])
    blocked("R9-004 writing your own engagement count", s, d)
    s, d = get(f"/rest/v1/posts?select=reaction_count,comment_count&id=eq.{public_post}", tok["w1"])
    check("counts are kept by Omelo", d and d[0]["reaction_count"] == 1 and d[0]["comment_count"] == 2, d)
    s, d = rpc("omelo_save_post", {"p_post": job_post, "p_save": True}, tok["w2"])
    check("a reader saves the job post", s == 200 and d.get("saved") is True, f"{s} {msg(d)}")
    s, sh = rpc("omelo_share_post", {"p_post": org_post, "p_body": "Worth a look if you are a night nurse."}, tok["w1"])
    check("a worker shares the organization's post", s == 200 and (sh.get("shared_post") or {}).get("id") == org_post, f"{s} {msg(sh)}")
    s, d = get(f"/rest/v1/posts?select=share_count&id=eq.{org_post}", tok["emp"])
    check("…and the original counts the share", d and d[0]["share_count"] == 1, d)

    print("\n4. CONNECTIONS (R9-005)")
    s, cn = rpc("omelo_request_connection", {"p_person": acc["w2"]["id"], "p_message": "We worked the same ward."}, tok["w1"])
    check("a connection request is sent", s == 200 and cn.get("status") == "pending", f"{s} {msg(cn)}")
    conn = cn.get("id") if s == 200 else None
    s, d = rpc("omelo_request_connection", {"p_person": acc["w2"]["id"]}, tok["w1"])
    blocked("asking twice", s, d)
    s, d = rpc("omelo_respond_connection", {"p_connection": conn, "p_accept": True}, tok["w3"])
    blocked("someone else answering the request", s, d)
    s, inv = rpc("omelo_my_network", {"p_view": "invitations"}, tok["w2"])
    check("the invitation is waiting", s == 200 and any(i["connection_id"] == conn for i in inv), f"{s} {msg(inv)}")
    s, d = rpc("omelo_respond_connection", {"p_connection": conn, "p_accept": True}, tok["w2"])
    check("it is accepted", s == 200 and d.get("status") == "accepted", f"{s} {msg(d)}")
    s, net = rpc("omelo_my_network", {"p_view": "connections"}, tok["w1"])
    check("both sides now see the connection", s == 200 and any(p["id"] == acc["w2"]["id"] for p in net), f"{s} {msg(net)}")
    s, seen = rpc("omelo_post_detail", {"p_post": private_post}, tok["w2"])
    check("R9-002 the connections-only post is now readable by the connection", s == 200 and seen and seen["id"] == private_post, f"{s} {msg(seen)}")
    s, d = post("/rest/v1/connections", {"requester_id": acc["x"]["id"], "addressee_id": acc["w1"]["id"]}, tok["x"])
    blocked("R9-005 writing a connection straight into the table", s, d)

    print("\n5. FOLLOWING")
    s, f1 = rpc("omelo_follow", {"p_target_type": "person", "p_target_id": acc["w1"]["id"]}, tok["w3"])
    check("a stranger follows the writer", s == 200 and f1.get("followers") == 1, f"{s} {msg(f1)}")
    s, f2 = rpc("omelo_follow", {"p_target_type": "company", "p_target_id": org}, tok["w2"])
    check("a reader follows the organization", s == 200 and f2.get("following") is True, f"{s} {msg(f2)}")
    s, d = rpc("omelo_follow", {"p_target_type": "person", "p_target_id": acc["w3"]["id"]}, tok["w3"])
    blocked("following yourself", s, d)
    s, fl = rpc("omelo_my_network", {"p_view": "following"}, tok["w2"])
    check("the follow list shows the organization", s == 200 and any(x["id"] == org for x in fl), f"{s} {msg(fl)}")

    print("\n6. THE FEED")
    s, feed = rpc("omelo_feed", {"p_tab": "following"}, tok["w2"])
    check("following: the connection's and the organization's posts", s == 200
          and public_post in ids(feed) and org_post in ids(feed), f"{s} {msg(feed)}")
    check("…each card says why it is there", all(p.get("why") for p in feed.get("posts", [])), feed.get("posts", [])[:1])
    s, feed = rpc("omelo_feed", {"p_tab": "organizations"}, tok["w2"])
    check("organizations: only organization posts", s == 200 and ids(feed) and all(
          p["author"]["type"] == "organization" for p in feed["posts"]), f"{s} {msg(feed)}")
    s, feed = rpc("omelo_feed", {"p_tab": "jobs"}, tok["w2"])
    check("jobs: the job share, with the job attached", s == 200 and job_post in ids(feed)
          and feed["posts"][0]["job"]["title"].startswith("Staff Nurse"), f"{s} {msg(feed)}")
    s, feed = rpc("omelo_feed", {"p_tab": "saved"}, tok["w2"])
    check("saved: what the reader saved", s == 200 and ids(feed) == [job_post], f"{s} {msg(feed)}")
    s, feed = rpc("omelo_feed", {"p_tab": "for_you"}, tok["w2"])
    check("for you: ranked, with a score and the ranking explained", s == 200 and ids(feed)
          and all("score" in p for p in feed["posts"]) and feed.get("ranking"), f"{s} {msg(feed)}")
    s, d = rpc("omelo_save_feed_preferences", {"p": {"show_jobs": False}}, tok["w2"])
    check("the reader turns job posts off", s == 200 and d.get("show_jobs") is False, f"{s} {msg(d)}")
    s, feed = rpc("omelo_feed", {"p_tab": "for_you"}, tok["w2"])
    check("…and job posts disappear from the feed", job_post not in ids(feed), ids(feed))
    rpc("omelo_save_feed_preferences", {"p": {"show_jobs": True}}, tok["w2"])
    s, d = rpc("omelo_mute_from_feed", {"p_target_type": "person", "p_target_id": acc["w1"]["id"]}, tok["w2"])
    check("the reader mutes the writer", s == 200 and d.get("muted") is True, f"{s} {msg(d)}")
    s, feed = rpc("omelo_feed", {"p_tab": "for_you"}, tok["w2"])
    check("R9-006 …and their posts leave the feed", public_post not in ids(feed), ids(feed))
    rpc("omelo_mute_from_feed", {"p_target_type": "person", "p_target_id": acc["w1"]["id"], "p_mute": False}, tok["w2"])
    s, d = rpc("omelo_feed", {"p_tab": "for_you"}); blocked("the feed signed out", s, d)
    s, d = rpc("omelo_feed", {"p_tab": "everything"}, tok["w2"]); blocked("an unknown feed tab", s, d)

    print("\n7. BLOCKING, REPORTING, DELETING (R9-006)")
    s, d = post("/rest/v1/blocks", {"person_id": acc["w1"]["id"], "target_type": "person",
                "target_id": acc["x"]["id"], "reason": "unwanted messages"}, tok["w1"])
    check("the writer blocks the outsider", s == 201, f"{s} {msg(d)}")
    s, seen = rpc("omelo_post_detail", {"p_post": public_post}, tok["x"])
    check("R9-006 a blocked person loses sight of the post", s == 200 and seen is None, f"{s} {msg(seen)}")
    s, d = rpc("omelo_request_connection", {"p_person": acc["w1"]["id"]}, tok["x"])
    blocked("…and cannot ask to connect", s, d)
    s, d = post("/rest/v1/reports", {"reporter_id": acc["w3"]["id"], "subject_type": "post", "subject_id": public_post,
                "reason": "spam", "details": "Looks like an advert"}, tok["w3"])
    check("anyone can report a post", s == 201, f"{s} {msg(d)}")
    s, d = rpc("omelo_update_post", {"p_post": public_post, "p": {"body": "First day on the new ward — edited."}}, tok["w2"])
    blocked("editing someone else's post", s, d)
    s, d = rpc("omelo_update_post", {"p_post": public_post, "p": {"body": "First day on the new ward — edited."}}, tok["w1"])
    check("the author edits their own post", s == 200 and d.get("edited_at"), f"{s} {msg(d)}")
    s, d = rpc("omelo_delete_comment", {"p_comment": c1.get("id")}, tok["w3"])
    blocked("a stranger deleting a comment", s, d)
    s, d = rpc("omelo_delete_comment", {"p_comment": c1.get("id")}, tok["w1"])
    check("the post's author can remove a comment on it", s == 200, f"{s} {msg(d)}")
    s, d = get(f"/rest/v1/posts?select=comment_count&id=eq.{public_post}", tok["w1"])
    check("…and the count follows", d and d[0]["comment_count"] == 1, d)
    s, d = rpc("omelo_delete_post", {"p_post": public_post}, tok["w2"])
    blocked("deleting someone else's post", s, d)
    s, d = rpc("omelo_delete_post", {"p_post": public_post}, tok["w1"])
    check("the author deletes their post", s == 200 and d.get("deleted") is True, f"{s} {msg(d)}")
    s, seen = rpc("omelo_post_detail", {"p_post": public_post}, tok["w2"])
    check("…and it is gone for everyone", s == 200 and seen is None, f"{s} {msg(seen)}")

    print("\n8. THE NETWORK NEVER TOUCHES PRIVATE WORK (R9-008)")
    s, d = post("/rest/v1/post_media", {"post_id": org_post, "position": 5, "kind": "image",
                "storage_path": "x/y.png", "mime_type": "image/png"}, tok["w3"])
    blocked("attaching media to someone else's post", s, d)
    s, feed = rpc("omelo_feed", {"p_tab": "for_you"}, tok["w2"])
    dump = json.dumps(feed)
    check("no feed card carries pay, applications or offers",
          all(k not in dump for k in ("application", "offer_id", "earnings", "timesheet", "pay_amount")), "leak")
    s, d = get("/rest/v1/applications?select=id&limit=1", tok["w3"]); blocked("a reader browsing applications", s, d)
    s, d = get("/rest/v1/earnings?select=id&limit=1", tok["w3"]); blocked("…or earnings", s, d)

    print(f"\n{'ALL PASSED' if not FAIL else str(len(FAIL)) + ' FAILED: ' + '; '.join(FAIL)}")
    sys.exit(1 if FAIL else 0)


if __name__ == "__main__":
    main()
