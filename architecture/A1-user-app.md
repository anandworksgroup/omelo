# A1 — Omelo User App (Flutter)

**Phase 1 architecture document 1 of 4**
**Platform:** Flutter · Android + iOS · phone-first
**Audience:** every worker — no degree, no formal employment, no resume, no certifications, and no assumed digital literacy

---

## 1. Design constraints

These are not preferences. They are the constraints that make the app usable by the people it
exists for.

| # | Constraint | Consequence |
|---|---|---|
| **UC-1** | A person must see real jobs **before** signing up | `omelo_nearby_jobs` is callable by `anon` |
| **UC-2** | Nothing is required to participate | No mandatory resume, degree, email, or experience |
| **UC-3** | Signup to first application in under 10 minutes | Four onboarding questions, then jobs |
| **UC-4** | Every screen works on a mid-tier Android device on a metered connection | Paginate everything, cache aggressively, no heavy media on list screens |
| **UC-5** | Distance is a primary filter, not a secondary one | Nearby is the default discovery mode |
| **UC-6** | Nothing is a dead end | Every empty, error and rejection state offers a next action |
| **UC-7** | Every number shown about a person is explainable in one tap | Match scores never appear bare |
| **UC-8** | The app must be usable in the worker's own language | Full localisation including taxonomy |
| **UC-9** | Low literacy is a design target | Icons + labels, voice input on every long-text field, plain language throughout |

### 1.1 Language rules

| Never say | Say |
|---|---|
| "Professional profile" | "My work" |
| "Resume required" | "Tell us what you've done" |
| "Curriculum vitae" | "Your work history" |
| "Candidate" | "You" |
| "Qualifications" | "What you can do" |
| "Employment gap" | *(never referenced at all)* |

---

## 2. Navigation

### 2.1 Five tabs

```
+--------------------------------------------------+
|                     OMELO                        |
+--------------------------------------------------+
|                                                  |
|   HOME           what changed for me              |
|   DISCOVER       find work                        |
|   APPLICATIONS   what happened to my applications |
|   MESSAGES       employers talking to me          |
|   PROFILE        my work identity                 |
|                                                  |
+--------------------------------------------------+
```

Five tabs, permanently visible, never collapsed into a drawer. A hidden menu is invisible to a
first-time user.

### 2.2 The work-identity switcher

A person may hold up to 5 work identities (`work_identities`). The switcher is a **persistent
chip in the app bar** on Home, Discover and Profile.

```
+--------------------------------------------------+
| [ Delivery Driver  v ]              [bell] [pfp] |
+--------------------------------------------------+

  tapping the chip:
  +----------------------------------------+
  |  Switch work identity                  |
  |                                        |
  |  * Delivery Driver          primary    |
  |    Looking · visible to employers      |
  |                                        |
  |    Mechanic                            |
  |    Looking · hidden from employers     |
  |                                        |
  |  + Add another kind of work            |
  |                                        |
  |  Manage identities                     |
  +----------------------------------------+
```

**What the switcher changes:** recommendations, search defaults, saved searches, match scores,
the adaptive profile form, pay and availability preferences, and which identity an application
is submitted as.

**What it does not change:** documents, licences, education, languages, verification, blocks,
messages, notifications. Those are the person, not the identity.

Single-identity users (the large majority at launch) see the chip as a static label, not a
control. It becomes interactive only when a second identity exists — no first-time user is asked
to understand a concept they do not need.

### 2.3 Navigation graph

```
SPLASH -> LANGUAGE -> COUNTRY -> AUTH -> ONBOARD -> [ HOME ]
                                   |
                          (skip)   +-------------> [ DISCOVER ] (browse-only)

[HOME] --------> job detail, application detail, conversation, career, alerts
[DISCOVER] ----> search, filters, map, category grid, job detail, company
[APPLICATIONS]-> application detail -> timeline, interview, offer, documents
[MESSAGES] ----> conversation -> structured actions
[PROFILE] -----> identity mgmt, work identity sections, documents, verification,
                 preferences, career, settings, data rights
```

---

## 3. Entry and authentication

| ID | Screen | Content | CTAs → destination |
|---|---|---|---|
| **U-01** | Splash | Logo, version check | auto → U-02 |
| **U-02** | Language | Device language pre-selected; list from `languages` incl. `native_name` and `rtl` | Select → U-03 |
| **U-03** | Country | Geo-detected, editable; drives `country_policies` | Continue → U-04 |
| **U-04** | Welcome | "Find work that fits your life." Three value points. | **Find work now** → U-20 (browse, no account) · **Sign in / Create account** → U-05 |
| **U-05** | Auth | Phone-first where `country_policies.phone_auth_preferred`, else email. Google / Apple secondary. | Continue → U-06 |
| **U-06** | OTP | 6-digit, auto-read on Android, resend timer | Verify → U-10 (new) / Home (returning) · Change number → U-05 |

**U-04 is load-bearing.** "Find work now" leads straight to real jobs with no account. A worker
who has been burned by fake job sites will not create an account on faith. Applying prompts
signup at the moment the value is obvious.

---

## 4. Onboarding — four questions

| ID | Screen | Question | Options | Writes |
|---|---|---|---|---|
| **U-10** | Looking for | *What kind of work are you looking for?* | Full-time · Part-time · Freelance · Temporary / daily · Internship · Apprenticeship · Just exploring | `person_work_preferences.work_types` |
| **U-11** | Where | *Where do you want to work?* | Near me (+radius slider) · My city · Anywhere in country · Remote · Another country | `person_location_preferences`, `persons.geo` |
| **U-12** | What work | *What kind of work do you do?* | 34-category icon grid → professions. Free-text search. **"I'm looking for my first job"** always present. | `work_identities.category_id` / `.profession_id`, `person_professions` |
| **U-13** | Experience | *How much experience do you have?* | None / first job · Under 1 year · 1–3 · 3–5 · 5–10 · 10+ | `work_identities.total_experience_months` |
| **U-14** | Ready | *Here are N jobs near you.* Live count. | **See jobs** → Home |

Four screens. Every one skippable except U-12, which can be answered with "first job." No
resume, no email, no education, no document.

### 4.1 The category grid (U-12)

```
  What kind of work do you do?

  [search...]                       [ voice ]

  [truck]      [box]       [cart]      [chef]
  Delivery     Warehouse   Retail      Food

  [wrench]     [hardhat]   [broom]     [shield]
  Trades       Construct.  Cleaning    Security

  [stetho]     [book]      [laptop]    [car]
  Healthcare   Education   Technology  Transport

                 ... 34 total ...

  ------------------------------------------
  I'm looking for my first job
  ------------------------------------------
```

Icons carry equal weight to labels (UC-9). Voice search on the field. Order is configurable per
country by `job_categories.position` — Technology is not first in every market.

---

## 5. Home (U-20)

Home answers one question: **what changed that affects my work?** It is not a feed.

### 5.1 States

**New user, empty identity**

```
  [ My work  v ]

  Welcome to Omelo

  [        Find a job        ]

  Jobs near you
  ------------------------------------------
  Delivery Executive · ABC Logistics
  Rs 22,000-30,000 / month · 4.1 km
  Transport provided
  [ Apply ]

  Warehouse Assistant · FreshMart
  Rs 18,000-24,000 / month · 2.2 km
  No experience needed
  [ Apply ]
  ------------------------------------------

  Add 2 more things and see 40 more jobs   [ Add ]
```

**Active seeker**

```
  Good morning, Anand           [ Delivery Driver v ]

  [ Search jobs                        ]

  Your applications
    ABC Logistics moved you to Interview      >
    FreshMart viewed your application 2d ago  >

  Jobs near you                          See all >
    ... 3 cards ...

  Recommended for you                    See all >
    92% match · Senior Delivery Executive
    Why: 4 yrs experience, own vehicle, same area

  Your other work
    Mechanic: 12 new jobs match this identity  >
```

**Employed / not seeking** — reduced to application updates, messages and saved jobs. No job
recommendations. `person_work_preferences.seeking = false` is respected, per identity.

### 5.2 CTA map

| CTA | Destination |
|---|---|
| Search jobs | U-30 Search |
| Jobs near you / See all | U-31 Nearby |
| Job card | U-40 Job detail |
| Apply (on card) | U-50 Apply |
| Application row | U-61 Application detail |
| Recommended card | U-40 |
| Why (match reason) | U-41 Match explanation |
| Add / Complete profile | U-80 Profile completion |
| Other identity row | switches identity → Discover |
| Bell | U-25 Notifications |
| Avatar | U-80 Profile |

---

## 6. Discover

| ID | Screen | Purpose |
|---|---|---|
| **U-30** | Search | Natural-language + facets |
| **U-31** | Nearby | Distance-sorted list, **default discovery mode** |
| **U-32** | Map | Pins, radius, cluster |
| **U-33** | Categories | 34-category grid → profession → results |
| **U-34** | Results | Unified result list |
| **U-35** | Filters | Full filter sheet |
| **U-36** | Saved searches | Manage + alert cadence |
| **U-37** | Companies | Company search |
| **U-38** | Company profile | About, jobs, hiring behaviour |

### 6.1 Discover landing

```
  [ Search jobs, companies         ]  [ mic ]

  [ Nearby ] [ Recommended ] [ Remote ] [ Part-time ]
  [ No experience needed ] [ Immediate start ] [ Walk-in ]

  Browse by category
  [ 34-category grid ]

  Your saved searches
    Night warehouse jobs · 4 new           >
```

**"No experience needed"**, **"Immediate start"** and **"Walk-in"** as first-class chips are
what make this a universal employment app. They map to `jobs.accepts_no_experience`,
`jobs.is_immediate_start` and `jobs.walk_in_details is not null`.

### 6.2 Natural-language search (U-30)

Interpretation is always visible and editable:

```
  "night shift warehouse jobs near me with transport"

  We understood:
  [Warehousing x] [Night shift x] [Within 10 km x] [Transport x]
                                              [ + add filter ]

  84 jobs        Sort: [ Best match v ]
```

Low-confidence facets render in an unconfirmed style and ask rather than assume. On AI timeout,
fall back to lexical search and label the facets unconfirmed — never block the search.

### 6.3 Filters (U-35)

| Group | Filters |
|---|---|
| Location | Distance radius · city · country · remote · relocation |
| Pay | Min amount · **period (hour/day/week/month/year)** · negotiable |
| Work | Work type · workplace type · **shift** · hours per week · immediate start · duration |
| Requirements | Experience level · **no experience needed** · education · licence · language |
| Benefits | **Accommodation · transport · meals** · insurance · visa sponsorship · overtime · tips |
| Company | Verified only · size · industry · **responds quickly** |
| Applying | **Quick apply** · walk-in · no resume needed |
| Posted | 24h · 3d · 7d · 30d |

Filters are driven by `country_policies`. Gender and age filters appear **only** where
`gender_criteria_permitted` / `age_criteria_permitted` is true for that country, and never as a
default.

The pay-period selector is essential: a worker thinking in daily wages cannot use a filter that
only speaks annual salary.

### 6.4 Job card

```
  +--------------------------------------------------+
  | [logo]  Delivery Executive              [ save ] |
  |         ABC Logistics  * verified                |
  |         4.1 km · Sector 18, Noida                |
  |                                                  |
  |         Rs 22,000 - 30,000 / month               |
  |         Full-time · Day shift                    |
  |                                                  |
  |         + Transport  + Meals  + Insurance        |
  |                                                  |
  |         87% match      No experience needed      |
  |                                                  |
  |         Posted 2d ago · usually replies in 3d    |
  |                        [ View ]   [ Apply ]      |
  +--------------------------------------------------+
```

Mandatory on every card: distance, pay **with period**, benefits, verification badge, match
score, employer response behaviour. `usually replies in 3d` comes from
`companies.median_response_hours` and is what makes the marketplace honest.

---

## 7. Job detail (U-40)

Ordered by what a worker decides on, not by what an employer wants to say.

```
  Delivery Executive
  ABC Logistics * verified          [ save ] [ share ]

  Rs 22,000 - 30,000 / month
  Sector 18, Noida · 4.1 km from you
  Full-time · Day shift · 6 days/week
  Starts immediately

  87% match          [ Why? ]

  What you need
    Own two-wheeler        you have this
    Driving licence (MC)   you have this, verified
    1 year experience      you have 4 years
    Smartphone             you have this

  What you get
    Transport allowance · Two meals · Insurance
    Overtime pay · Uniform provided

  The work
    ... responsibilities ...

  Working conditions
    Outdoors · Lifting up to 20 kg · Standing

  Hiring process
    Apply -> Phone call -> Trial shift -> Hire
    ABC Logistics usually decides in 4 days

  About ABC Logistics
    * Verified · 240 employees · 84 hires on Omelo
    Replies to 91% of applications

  [            APPLY            ]
  [ Ask a question ]  [ Report this job ]

  Omelo will never ask you to pay to apply.
```

**"What you need" is checked against the worker's own identity**, item by item. A person can see
in two seconds whether they qualify — instead of guessing, applying, and hearing nothing.

The anti-fraud line is permanent, not dismissible.

### 7.1 Match explanation (U-41)

Rendered from `matches.feature_vector`. Never AI-invented.

```
  Why 87%?

  Distance          4.1 km            strong
  Experience        4 yrs (needs 1)   strong
  Vehicle           own two-wheeler   strong
  Licence           MC, verified      strong
  Pay expectation   overlaps 85%      good
  Shift             day (you prefer)  good

  Not counted
    Your age, gender, photo, name, or any gap
    in your work history. Ever.

  This score ranks jobs for you. A person at the
  company decides who is hired.

  [ Ask for human review ]
```

---

## 8. Applying

Two paths. The default is the short one.

### 8.1 Quick apply (U-50) — `jobs.quick_apply_enabled`

```
  Apply to Delivery Executive
  ABC Logistics

  Applying as:  [ Delivery Driver v ]

  They will see:
    Your name and phone
    4 years delivery experience
    Driving licence (MC) - verified
    Your area (Sector 62, Noida)

  They will NOT see:
    Your documents, unless you share them later

  1 question from this employer:
    Do you have your own two-wheeler?   [Yes] [No]

  [           SEND APPLICATION           ]
```

Three things matter here: **which identity** is applying, **exactly** what the employer receives,
and an explicit statement of what they do **not** receive. No resume, no cover letter, no upload.

### 8.2 Full apply (U-51)

For `requires_resume = true` or jobs with several questions. Same preview contract, plus
document selection from the vault with a per-employer share.

### 8.3 Applying without an account

```
  Sign in to apply — 30 seconds

  [ phone number          ]
  Your application is saved and sends as soon
  as you verify.
```

The application is held, not discarded.

### 8.4 Knockout questions

If a question is disqualifying, the worker is told **before** answering, and the outcome is
shown immediately rather than manufacturing a fake pipeline entry:

```
  This employer requires a heavy-vehicle licence.
  You have a motorcycle licence.

  You can still apply, but they have said this is
  required.

  [ Apply anyway ]   [ See 34 similar jobs you match ]
```

---

## 9. Applications

| ID | Screen | Content |
|---|---|---|
| **U-60** | Applications list | **Active** / **Archived** tabs |
| **U-61** | Application detail | Timeline + actions |
| **U-62** | Interview detail | When, where, what to bring |
| **U-63** | Offer detail | Full terms, accept / decline / ask |
| **U-64** | Document request | Employer asked for a document |

Active groups by state: Applied · Viewed · Shortlisted · Screening · Assessment · Interview ·
Offer. Archived: Rejected · Withdrawn · Expired.

### 9.1 The timeline (U-61)

```
  Delivery Executive
  ABC Logistics

  [x] Applied              20 Aug, 09:14
  [x] Employer viewed      21 Aug, 11:02
  [x] Shortlisted          22 Aug, 16:30
  [>] Trial shift          28 Aug, 07:00      [ details ]
  [ ] Decision

  ABC Logistics usually decides within 4 days
  of a trial shift.

  [ Message employer ]  [ View job ]
  [ Withdraw application ]
```

`Employer viewed` is written by `omelo_mark_application_viewed()` and **cannot be suppressed**.
Employer stage names map to these states through `job_stages.maps_to_state`, so an employer can
run whatever pipeline they like but cannot hide movement.

### 9.2 The silence state

The most important screen in the app.

```
  [x] Applied              20 Aug
  [ ] Employer viewed

  No activity for 11 days.
  ABC Logistics usually replies within 4 days.

  This application will close on 20 Sep if nothing
  changes, and we will tell you when it does.

  [ Message employer ]
  [ Withdraw ]
  [ 28 similar jobs near you ]
```

Three rules: state elapsed time plainly, give the employer's real baseline, always offer a next
action.

### 9.3 Rejection

```
  ABC Logistics is not moving forward.        22 Aug

  Reason: Looking for heavy-vehicle experience.

  This is one job, not a verdict.
    41 jobs near you match you above 85%
    A heavy-vehicle licence would open 260 more

  [ See matching jobs ]   [ About that licence ]
```

Where no reason was given, say so honestly. Never fabricate one.

---

## 10. Messages

| ID | Screen |
|---|---|
| **U-70** | Conversation list |
| **U-71** | Conversation |
| **U-72** | Report |

```
  Sarah · ABC Logistics  * verified employer
  About: Delivery Executive

  Sarah  We liked your application. Can you come
         for a trial shift on Thursday?      14:20

  [ Confirm Thursday ]  [ Suggest another time ]
  [ Ask a question ]

  ---------------------------------------------
  Omelo will never ask you to pay to apply, interview,
  or start a job. No real employer asks for money,
  bank details, or your original documents.

  [ Report ]                    [ Block company ]
```

Every conversation is anchored to a job. Structured actions sit inline so the conversation
drives the pipeline. Report and Block are one tap, always visible, never buried. Read receipts
are symmetric or absent.

---

## 11. Profile — "My Omelo"

Never called "resume."

```
  [ photo ]  Anand Singh
             Sector 62, Noida
             * Phone  * Licence verified

  [ Delivery Driver v ]        Profile 68% complete

  Add your ID document -> +12% and 40 more jobs   [ Add ]

  THIS WORK IDENTITY
    What I do                 Delivery Executive  >
    My skills                 6 added             >
    My experience             3 jobs              >
    What I'm looking for      Full-time, day      >
    Where I want to work      Within 10 km        >
    Pay I expect              Rs 25,000/month     >
    When I can start          Immediately         >
    Who can find me           Visible             >

  ME (shared across all my work)
    Personal details                              >
    Education                                     >
    Licences                    1 verified        >
    Certificates                                  >
    Languages                   3                 >
    Documents                   4                 >
    References                                    >
    Verification                2 of 5            >

  MY WORK IDENTITIES
    Delivery Driver             primary           >
    Mechanic                    hidden            >
    + Add another kind of work

  Career                                          >
  Settings                                        >
```

The split between **this work identity** and **me** is explicit and visible. It is how a person
understands, without being taught, that changing their pay expectation as a Mechanic does not
change it as a Delivery Driver — but their licence is the same licence.

### 11.1 Adaptive profile

`omelo_profile_schema_for(work_identity_id)` returns different fields per identity. Verified live:
a delivery worker gets `delivery-vehicle`, `smartphone-available`, `can-travel-daily-km`,
`first-job` — and is never asked about clinical specialisations or heavy-vehicle classes.

| Identity | Asked about |
|---|---|
| Delivery worker | Vehicle type · smartphone · daily travel distance |
| Driver | Licence classes · vehicle types driven · years driving · routes |
| Nurse | Registration number · specialisation · ward experience · shifts |
| Electrician | Licence class · voltage rating · industrial vs domestic · tools owned |
| Chef | Cuisines · kitchen size · station · food-safety certificate |
| Software engineer | Languages · frameworks · cloud |
| Security guard | Licence · armed/unarmed · shift tolerance |
| Teacher | Subjects · levels · board · teaching licence |

**There are no profession-specific columns anywhere in the database.** This is entirely driven
by `profile_attributes` + `person_attributes`, keyed on `work_identity_id`.

### 11.2 Adding a second work identity (U-85)

```
  Add another kind of work

  Many people do more than one kind of work.
  Each one gets its own pay, hours, and privacy
  settings — but you keep one profile, one set of
  documents, and one verified identity.

  What else do you do?
  [ search or pick a category ]

  Name it:  [ Mechanic            ]

  [ Create ]
```

Then immediately:

```
  Your Mechanic identity is ready.

  Who can find you as a Mechanic?
   ( ) Nobody - I'm not looking for mechanic work
   (o) Employers hiring mechanics
   ( ) Anyone

  Your Delivery Driver identity stays exactly as
  it is. These settings are separate.
```

That last sentence is the entire feature explained in one line.

### 11.3 "I don't have a resume" (U-90)

A primary CTA, not a fallback.

```
  No resume? That's fine.

  Most jobs on Omelo don't need one. If you want,
  we can make one from a few questions.

  [ Make my resume ]   [ Skip - I don't need one ]
```

Question-led builder, voice input on every field:

```
  U-91  What work have you done?      [ mic ]
  U-92  Where did you work?
  U-93  How long?
  U-94  What could you do there?
  U-95  Any school or training?
  U-96  What are you good at?
  U-97  Preview -> Save to documents
```

Output is a `documents` row with `is_generated = true`. **The worker reviews it before it is
ever sent.**

### 11.4 Document vault (U-100)

```
  My documents                        [ + Add ]

  Resume (made by Omelo)      shared with 2   >
  Aadhaar card               * sensitive      >
  Driving licence            * verified       >
  Experience letter                           >

  Who has my documents
    ABC Logistics - Driving licence   [ Stop sharing ]
    FreshMart - Resume                [ Stop sharing ]
```

**Applying shares nothing.** Documents move only through an explicit `document_shares` row, and
"Stop sharing" revokes it immediately. Sensitive documents carry a warning before any share.

### 11.5 Verification centre (U-110)

```
  Verification

  Phone         * verified
  Email           add
  Identity        not verified      [ Verify ]
  Licence       * verified 12 Aug 2026
  Education       not verified      [ Verify ]
  Experience    * 1 of 3 verified

  Verified workers get 3x more employer responses.

  Each badge says exactly what was checked.
```

Unverified is the default and is never presented as suspicious.

### 11.6 Privacy (U-120)

```
  Who can find me

  Master switch
   ( ) Nobody can find me
   (o) Let employers find me

  Per work identity
    Delivery Driver   [ Employers hiring delivery v ]
    Mechanic          [ Nobody v ]

  Never show me to
    [ Current Employer Ltd  x ]      [ + Add ]

  Blocked companies never see you and are never
  told they were blocked.
```

The per-identity row is the payoff of the whole model. The blocklist row is what makes the app
safe for someone quietly looking while employed.

---

## 12. Career (U-130, Phase 2)

Entry from Profile. Not a tab in Phase 1b.

```
  Your work                Delivery Driver

  Where you are
    Delivery Executive · 4 years
    Based on 3 jobs and a verified licence

  Where you could go
    Senior Delivery Executive   +20%   6-12 months
    Delivery Supervisor         +45%   1-2 years
    Fleet Coordinator           +60%   2-3 years

  Delivery Supervisor
    You have 7 of 10 things needed
    Missing: team handling, route planning, basic English
    -> would match you to 340 more jobs

  [ Set as my goal ]   [ See the gap ]
```

Paths come from `profession_transitions`. While `observed_count` is low the UI says the paths
are typical rather than observed. No unsourced advice.

---

## 13. Notifications (U-25)

| Type | Channel | Deeplink |
|---|---|---|
| `job_match` | Push | U-40 |
| `job_alert`, `saved_search` | Push | U-34 |
| `application_update` | Push + SMS | U-61 |
| `recruiter_message` | Push | U-71 |
| `interview_scheduled` | Push + SMS | U-62 |
| `interview_reminder` | Push + SMS | U-62 |
| `offer_received` | Push + SMS | U-63 |
| `document_request` | Push | U-64 |
| `verification_update` | Push | U-110 |
| `job_closing_soon` | Push | U-40 |
| `profile_reminder` | Push | U-80 |

Quiet hours are enforced **server-side in the worker's timezone**. A night-shift worker asleep
at 11:00 is not woken by a job alert. Interviews and offers also go by SMS because they are
time-critical and many workers have no active email address.

---

## 14. Complete CTA map

| CTA | Destination |
|---|---|
| Find work now (pre-signup) | U-31 Nearby |
| Search jobs | U-30 |
| Voice search | U-30 with mic |
| Nearby jobs | U-31 |
| Map view | U-32 |
| Browse categories | U-33 |
| Category tile | U-34 filtered |
| Filter | U-35 |
| Save search | U-36 |
| Job card | U-40 |
| Why (match) | U-41 |
| Save job | saved list, stays in place |
| Share job | OS share sheet |
| Apply | U-50 / U-51 |
| Ask a question | U-71 |
| Report job | U-72 |
| View company | U-38 |
| Application row | U-61 |
| Interview | U-62 |
| Offer | U-63 |
| Accept offer | U-63 confirm |
| Decline offer | U-63 reason |
| Upload requested document | U-64 |
| Withdraw | U-61 confirm |
| Message | U-71 |
| Block company | confirm, silent to employer |
| Complete profile | U-80 |
| Switch identity | identity sheet |
| Add work identity | U-85 |
| Add skill / experience / education | respective editors |
| Add licence | U-105 |
| Verify | U-110 |
| Make my resume | U-90 |
| Documents | U-100 |
| Stop sharing document | revokes `document_shares` |
| Who can find me | U-120 |
| Career | U-130 |
| Notification | its own deeplink |
| Export my data | U-140 |
| Delete account | U-141 |

**Nothing in this table is a dead end.** Every terminal state — rejection, expiry, no results,
offline — carries a forward action.

---

## 15. Empty, error and offline states

| State | Behaviour |
|---|---|
| No jobs nearby | Widen radius automatically, show the count at each radius, offer remote |
| No search results | Show which filter eliminated the most jobs, offer to relax it |
| No applications | Show 3 jobs they match above 80% |
| No messages | Explain that employers message after viewing |
| Offline | Serve cached jobs, saved jobs and applications. **Never queue an apply.** |
| Apply failed | Preserve everything entered, retry inline |
| Job closed while viewing | Say so, show 5 similar jobs |
| AI unavailable | Facets fall back to lexical; matching continues on deterministic features |

Never queueing an offline apply is deliberate: an application that silently fires days later
against a closed job is worse than an honest error.

---

## 16. Technical notes

| Concern | Approach |
|---|---|
| State | Riverpod; one provider per domain |
| Routing | `go_router`, deeplink-first — every notification must resolve to a screen |
| Data | `supabase_flutter`, **anon key only**; generated types |
| Realtime | Subscriptions on messages, applications, notifications, interviews, offers |
| Location | Foreground permission only, with an in-context explanation before the OS prompt |
| Images | Aggressive downscaling; no images on list rows beyond a small logo |
| Lists | Paginated, 20 per page |
| Localisation | ARB files, RTL support, taxonomy localised via `*_aliases.locale` |
| Accessibility | WCAG 2.2 AA; minimum 44 pt targets; full screen-reader labelling |
| Analytics | Outcome events only — applications, responses, hires. Not session length. |

---

## Decision log

| Decision | Rationale |
|---|---|
| Jobs visible before signup | A worker burned by fake job sites will not register on faith |
| Four onboarding questions | Anything longer loses the person this product exists for |
| Nearby is the default discovery mode | Distance is the primary constraint for most of the workforce |
| Identity switcher is inert until a second identity exists | Never teach a concept the user does not yet need |
| "This work identity" vs "Me" shown explicitly in Profile | Teaches the model by layout instead of explanation |
| Apply preview lists what employers will **not** see | Trust is built by naming the limit, not just the disclosure |
| Applying shares no documents | Applying is not consent to hand over a passport |
| "No experience needed" is a top-level filter | It is the single most important filter for a first-job seeker |
| Pay filter leads with period | A daily-wage worker cannot use an annual-salary filter |
| Resume builder is a primary CTA | The absence of a resume must never feel like a deficiency |
| Rejection screen shows matching jobs | A rejection is one employer's decision, not a verdict on a person |
| No offline apply queue | A delayed apply against a closed job is worse than an error |
