"""Tiny client for testing Omelo against the live API as real users.

Always uses the PUBLISHABLE key, so every request goes through RLS exactly
as a browser or the Flutter app would. Never the service role.
"""
import json
import urllib.error
import urllib.request

BASE = "https://jfyqnlucoraazjkndbvm.supabase.co"
KEY = "sb_publishable_dFLJlbaDMDSTiZIw8dtMeA_kENpacgv"


def _req(method, path, token=None, body=None, prefer="return=representation"):
    headers = {
        "apikey": KEY,
        "Authorization": "Bearer " + (token or KEY),
        "Content-Type": "application/json",
    }
    if prefer:
        headers["Prefer"] = prefer
    data = json.dumps(body).encode() if body is not None else None
    r = urllib.request.Request(BASE + path, data=data, method=method, headers=headers)
    try:
        with urllib.request.urlopen(r, timeout=40) as resp:
            raw = resp.read().decode()
            return resp.status, (json.loads(raw) if raw else None)
    except urllib.error.HTTPError as e:
        raw = e.read().decode()
        try:
            return e.code, json.loads(raw)
        except Exception:
            return e.code, raw


def login(email, password):
    s, d = _req("POST", "/auth/v1/token?grant_type=password",
                body={"email": email, "password": password}, prefer=None)
    if s != 200:
        raise SystemExit(f"login failed for {email}: {s} {d}")
    return d["access_token"], d["user"]["id"]


def signup(email, password, name, role):
    s, d = _req("POST", "/functions/v1/auth-signup",
                body={"email": email, "password": password, "full_name": name, "role": role},
                prefer=None)
    if s != 200:
        raise SystemExit(f"signup failed: {s} {d}")
    return login(email, password)


def get(path, token=None):
    return _req("GET", path, token, prefer=None)


def post(path, body, token=None):
    return _req("POST", path, token, body)


def patch(path, body, token=None):
    return _req("PATCH", path, token, body)


def delete(path, token=None):
    return _req("DELETE", path, token)


def rpc(fn, args, token=None):
    return _req("POST", "/rest/v1/rpc/" + fn, token, args, prefer=None)


def msg(d):
    if isinstance(d, dict):
        return d.get("message") or d.get("msg") or json.dumps(d)[:140]
    if isinstance(d, list):
        return f"{len(d)} rows"
    return str(d)[:140]
