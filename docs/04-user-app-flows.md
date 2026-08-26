# 04 — User App Flows (Flutter)

**Status:** Frozen (Phase 0)
**Owner:** Product + Design

The user app is the primary consumer application. It must be fully usable by someone with:

- no degree
- no formal employment
- no resume
- no professional experience
- no certifications
- limited digital literacy

That constraint drives every screen below.

---

## 1. Navigation — five tabs

```
+----------------------------------------+
|                OMELO                   |
+----------------------------------------+
|                                        |
|  HOME           what changed for me    |
|                                        |
|  DISCOVER       find work              |
|                                        |
|  APPLICATIONS   where do I stand       |
|                                        |
|  MESSAGES       talk to employers      |
|                                        |
|  PROFILE        My Omelo               |
|                                        |
+----------------------------------------+
```

Career intelligence lives inside **Profile → My Career**, not as a sixth tab. Five tabs is the
limit before a bottom bar becomes unreadable on a small screen, and career tooling is a
considered visit rather than a daily one.

---

## 2. Entry flow

```
Splash
  |
Language Selection        <-- BEFORE anything else. 20 languages seeded.
  |
Country / Region          <-- drives currency, pay period, legal policy, document norms
  |
Login / Create Account
```

### 2.1 Authentication

| Method | Notes |
|---|---|
| **Phone + OTP** | Default in markets where `country_policies.phone_auth_preferred` is true (India, UAE, Philippines, Brazil, Mexico, South Africa) |
| Email + password | Default elsewhere |
| Google | Available everywhere |
| Apple | Required on iOS |

Phone-first is not a preference, it is table stakes. A large share of the target workforce has
a phone number and no email address they use.

### 2.2 Language before login

Selecting language first is deliberate. A person who cannot read the login screen cannot sign
up, and asking them to authenticate before they can change language is a dead end.

---

## 3. First-time onboarding

**Do not force a full profile before showing jobs.** Ask four questions, then show work.

```
Create account
      |
What are you looking for?
      |
      +-- Find a job                +-- Find temporary work
      +-- Find part-time work       +-- Find an internship
      +-- Find freelance work       +-- Find an apprenticeship
      +-- Just exploring
      |
Where do you want to work?
      |
      +-- Near me          +-- Remote
      +-- My city          +-- Another country
      +-- Anywhere in my country
      |
What kind of work?
      |
      Category grid -> professions
      |
Experience
      |
      +-- This is my first job     +-- 1-3 years
      +-- Less than 1 year         +-- 3+ years
      |
JOBS SHOWN IMMEDIATELY
      |
Profile is built progressively from here
```

### 3.1 "What kind of work?" — the category grid

```
  What kind of work are you looking for?

  [Construction]  [Delivery]     [Driving]
  [Food & Rest.]  [Retail]       [Security]
  [Cleaning]      [Healthcare]   [Warehousing]
  [Hospitality]   [Manufacturing][Technology]
  [Domestic]      [Beauty]       [Automotive]
                                  ... 34 total

  Pick one or more.        [ Skip - show me everything ]
```

Design rules:
- **Icons and plain names.** No industry jargon, no job-family taxonomy language.
- **Ordering is localised**, driven by real job volume in that country — not alphabetical, and not with Technology first.
- **Skip is always available.** An incomplete profile beats an abandoned one.
- Selecting a category reveals its professions, which sets the adaptive profile fields for later.

### 3.2 "This is my first job"

Selecting it sets the universal `first-job` attribute and filters discovery toward professions
where `is_entry_level_friendly = true`. The person immediately sees work that will actually
take them, rather than a wall of roles demanding three years' experience.

This is the single highest-leverage screen in the app for the persona everyone else ignores.

---

## 4. Home

Home answers one question: *what changed that affects my work?*

### 4.1 New user

```
  Welcome to Omelo

  What are you looking for?
  [ Find work near me ]

  Jobs near you                             142 within 10 km
  ------------------------------------------------
  Delivery Executive       Rs 22,000-30,000/month
  ABC Logistics            2.4 km

  Warehouse Packer         Rs 18,000-24,000/month
  QuickStore               3.1 km
  ------------------------------------------------

  Add 3 things to your profile and we can match
  you better.                    [ Add them ]
```

### 4.2 Active jobseeker

```
  Good morning, Anand

  [ Search jobs ]

  Your applications
    ABC Logistics moved you to Trial Shift      [ view ]
    QuickStore viewed your application 2 days ago

  Jobs near you
    Electrician              Rs 25,000-35,000/month   2.4 km
    Delivery Executive       Rs 22,000-30,000/month   4.1 km

  Recommended for you
    92% match  Site Electrician - Metro Constructions
               Rs 30,000-40,000/month  |  Accommodation

  Your profile
    Adding your electrician licence would unlock
    340 more jobs.                    [ Add licence ]
```

Every item states why it is shown and can be muted at its source.

---

## 5. Discover

```
Discover
  |
  +-- Search
  +-- Nearby              <-- default for onsite work
  +-- Recommended
  +-- Remote
  +-- Part-time
  +-- Full-time
  +-- Temporary
  +-- Freelance
  +-- Internship
  +-- Apprenticeship
  +-- Government / Public   (shown only where the country supports it)
```

Tabs shown are country-dependent. Apprenticeships matter enormously in Germany and barely
register elsewhere; government job boards are a major channel in India and irrelevant in others.

### 5.1 Natural-language search with visible interpretation

The user types freely; Omelo shows how it read the query and lets them correct it.

```
  "night shift warehouse jobs near me"

  We read that as:
    [Profession: Warehouse Worker x]  [Shift: Night x]
    [Within 10 km x]                  [+ add filter]

    Not what you meant? Tap any chip to change it.

  86 jobs        Sort: [ Nearest v ]
```

Must handle all of these equally well:

- `Driver jobs near Delhi`
- `Night shift warehouse jobs`
- `Flutter developer remote Europe`
- `Construction jobs in Dubai with accommodation`
- `कंस्ट्रक्शन जॉब दिल्ली` *(query language is not the interface language)*

Extracted facets: profession, category, location, distance, work type, shift, pay, remote,
country, benefits, licence, language.

### 5.2 Filters

| Filter | Notes |
|---|---|
| Location / Distance | Distance is the default sort for onsite work |
| Pay | Range **plus period** — comparing ₹700/day to ₹22,000/month is the platform's job, not the user's |
| Job type | Full-time, part-time, contract, gig, seasonal, daily wage, apprenticeship |
| Workplace | Onsite, hybrid, remote, field-based |
| Shift | Day, evening, night, rotating, split, weekend |
| Experience | Includes **"no experience needed"** as a first-class option |
| Education | Includes **"no formal education required"** |
| Category / Profession | |
| Company | |
| Working hours | |
| Benefits | Accommodation, transport, meals, insurance, flights |
| Language | |
| Licence | e.g. "jobs that don't need a licence" |
| Visa sponsorship | Available / Not required / Unknown — never silently inferred |
| Date posted | |
| Immediate start | |

**Gender and age filters do not exist in the user-facing filter set.** Where a jurisdiction
lawfully permits such criteria on a posting, that is an employer-side guarded exception
([02 §9](02-domain-model.md)) and never a browsing facet.

### 5.3 The job card

```
+---------------------------------------------------------+
| [logo]  Delivery Executive                      [save]  |
|         ABC Logistics                    * 4.2          |
|         Saket, New Delhi              2.4 km away       |
|                                                         |
|         Rs 22,000 - 30,000 / month                      |
|         Full-time  |  Day & Evening shifts              |
|                                                         |
|         + Transport allowance   + Health insurance      |
|         + No experience needed                          |
|                                                         |
|         87% match      Why?                             |
|                                                         |
|         Posted 3 days ago                               |
|         Usually responds in 2 days                      |
|                              [ View ]    [ Apply ]      |
+---------------------------------------------------------+
```

Mandatory on every card:
- **Pay with its period.** Never a bare number.
- **Distance** for onsite work.
- **Benefits that decide it** — accommodation and transport outrank a culture statement.
- **Match score with a "Why?"** — never a bare score ([08](08-matching-engine.md)).
- **Employer response behaviour** — what makes the marketplace honest.

### 5.4 Jobs that cannot hire you

Never silently filtered. Shown separately with the reason:

```
  8 jobs matched but can't hire you right now

  Site Electrician - Metro Constructions
  Needs an Electrician Licence (Wireman or above).
  [ Add my licence ]   [ How do I get one? ]
```

A person filtered without explanation concludes the platform is broken, or that they are
unemployable. Naming the constraint turns a dead end into an action.

---

## 6. Job details

```
Delivery Executive
ABC Logistics                                 [ Verified ]

Rs 22,000 - 30,000 / month
Saket, New Delhi  |  2.4 km  |  Field based
Full-time  |  Day & Evening  |  6 days/week
Start: Immediate

About this job
Responsibilities
Requirements
  - Two-wheeler with valid licence
  - Smartphone
  - No prior experience needed
Skills
Benefits
  Transport allowance  |  Health insurance
Documents needed
  Driving licence - at offer stage
  Government ID   - at offer stage
Work authorisation
Company information
Hiring process
  Apply -> Phone call -> Trial shift -> Hire
  Usually 5-7 days
Application deadline
Similar jobs

[ APPLY NOW ]  [ SAVE ]  [ SHARE ]  [ ASK RECRUITER ]  [ REPORT ]
```

**"Documents needed"** shows *when* each is requested, not just what. Seeing that a passport
scan is required only at offer stage — not to apply — is a meaningful trust signal, and its
absence is a known fraud pattern.

**"Hiring process"** renders the employer's real configured stages. The candidate knows what
they are entering before they enter it.

---

## 7. Apply

Application friction must scale with the job.

### 7.1 Quick apply — simple jobs

```
Apply -> Confirm phone -> Submit
```

For a job with `quick_apply_enabled` and `requires_resume = false`, that is the whole flow.
**Never demand a ten-page resume for a warehouse shift.**

### 7.2 Full apply

```
Apply
  |
Choose profile / details to share
  |
Required information
  |
Resume or Omelo profile
  |
Employer questions
  |
Review  <-- exactly what the employer will receive
  |
Submit
  |
Confirmation + timeline created
```

### 7.3 The review step is non-negotiable

Before submitting, the person sees the exact payload: which identity fields, which answers,
which documents. Nothing is transmitted that they have not seen.

### 7.4 Document requests are staged

At apply time, only documents whose `request_at_stage = 'apply'` are requested — normally none.
Each share creates an explicit, revocable `document_shares` row.

```
  ABC Logistics is asking for:
    Driving licence

  They will be able to view it until this application closes.
  You can revoke access at any time.

  [ Share ]   [ Not now ]
```

---

## 8. Applications

```
Applications

  ACTIVE
    Applied  |  Viewed  |  Shortlisted  |  Screening
    Interview  |  Assessment  |  Offer  |  Hired

  ARCHIVED
    Rejected  |  Withdrawn  |  Expired
```

### 8.1 The timeline

```
  Delivery Executive
  ABC Logistics

    [x] Applied                    20 Aug
    [x] Employer viewed            21 Aug
    [x] Shortlisted                22 Aug
    [>] Trial shift                28 Aug, 09:00
    [ ] Final decision

  [ View job ]  [ Message ]  [ Upload document ]  [ Withdraw ]
```

The employer named the stage "Trial Shift"; the timeline shows it while the underlying state is
`interview`. Employers get their own vocabulary; candidates get guaranteed honesty.

### 8.2 The silence state

```
    [x] Applied                    20 Aug
    [ ] Employer viewed

  No activity for 11 days.
  ABC Logistics usually responds within 2 days.
  This will expire on 19 Sep, and we'll tell you when it does.

  [ Message employer ]  [ Withdraw ]  [ Find similar jobs ]
```

Three rules: state the elapsed time plainly, give the employer's real baseline, and always offer
a next action.

### 8.3 Rejection

```
  ABC Logistics has decided not to move forward.        18 Aug

  Reason: Looking for someone with a heavy vehicle licence.

  This is one job, not a verdict.
    - 34 similar jobs near you are hiring now
    - Adding an HMV licence would unlock 210 more

  [ See similar jobs ]   [ How to get an HMV licence ]
```

Rejection is always communicated. Where no reason was given, say so honestly rather than
inventing one.

---

## 9. Messages

```
Messages
  |
  +-- Recruiters
  +-- Companies
  +-- Interviews
  +-- Support
```

```
Sarah - Recruiter at ABC Logistics        [ Verified employer ]
Re: Delivery Executive

  Sarah: Hi Anand, your application looks good. Can you
         come for a trial shift on Wednesday?     14 Aug

  [ Accept ]  [ Suggest another time ]  [ Ask a question ]

  -----------------------------------------------------
  Omelo will never ask you to pay to apply or work.
  No real employer asks for money or bank details.
  [ Report ]                          [ Block company ]
```

- Every conversation is anchored to a job. No context-free outreach.
- Structured actions inline, so the conversation drives the pipeline.
- Block and report always one tap away.
- Read receipts symmetric or absent — never one-sided in the employer's favour.
- The fraud warning is persistent because it works even when detection fails.

---

## 10. Profile — "My Omelo"

Called **My Omelo**, not "Resume." A resume is one thing Omelo can produce; it is not the
identity.

```
My Omelo
  |
  +-- Basic information        +-- Portfolio
  +-- About me                 +-- Languages
  +-- Work preferences         +-- Documents
  +-- Skills                   +-- References
  +-- Experience               +-- Verification
  +-- Education                +-- Availability
  +-- Certifications           +-- My Career
  +-- Licences                 +-- Privacy
  +-- Projects
```

### 10.1 The adaptive profile in the UI

Sections and fields are resolved by `omelo_profile_schema_for()`. The person sees only what
their work needs.

| A driver sees | A nurse sees | An electrician sees | An engineer sees |
|---|---|---|---|
| Vehicle types | Specialisation | Trade level | Portfolio / GitHub |
| Driving licence + class | Nursing registration | Electrician licence | Skills |
| Years driving | Clinical settings | Own tools | Laptop & internet |
| Routes known | Night shifts | Site types | |
| Own vehicle | | Safety training | |
| Night driving | | Comfortable at height | |

Nobody sees another column's questions. There are no profession-specific columns in the
database — this is `profile_attributes` rendering itself.

### 10.2 "I don't have a resume"

A primary call to action, not a fallback.

```
  No resume? That's fine.

  [ Build my profile by answering questions ]

  Tell us about yourself
     |
  What work have you done?        <-- free text, voice input supported
     |
  Where?                          <-- employer name, no registration required
     |
  How long?                       <-- "about 2 years" is acceptable
     |
  What can you do?                <-- skills, adaptive to the profession
     |
  Education                       <-- "none" is a valid answer
     |
  Skills
     |
  [ Generate my resume ]
```

Omelo produces a formatted resume from the structured answers. The person reviews and edits it
before it is ever sent.

Design notes:
- **Voice input** on every free-text field. Typing is a literacy barrier.
- **"About 2 years" is acceptable** — precision demands are an exclusion mechanism.
- **"None" is always a valid answer**, never a validation error.

### 10.3 Document vault

```
Documents
  +-- Resume                    +-- Education certificate
  +-- Government ID             +-- Professional certificate
  +-- Work permit               +-- Portfolio
  +-- Licence                   +-- Other

  Shared with
    ABC Logistics - Driving licence     until this application closes
                                                          [ Revoke ]
```

**Employers get nothing automatically.** Every view requires a live `document_shares` row.
Revocation is immediate and always visible from this screen.

### 10.4 Verification centre

```
Verification

  Phone            Verified
  Email            Verified
  Identity         Not verified      [ Verify ]
  Driving licence  Verified          Class LMV, MCWG - expires Mar 2029
  Employment       Verified          ABC Logistics, hired through Omelo
  Education        Not verified      [ Verify ]

  Verified workers get 3x more employer responses.
```

Each badge states exactly what was checked and how. A badge never implies more than the claim
behind it. Unverified is the default and is never presented as suspicious.

The employment badge above came free — it was written by the hiring loop.

### 10.5 Work, location, and pay preferences

```
I'm looking for
  [x] Full-time   [ ] Part-time   [ ] Contract
  [ ] Freelance   [x] Temporary   [ ] Apprenticeship
  [ ] Gig         [ ] Daily wage  [ ] Seasonal

Workplace
  [x] On-site  [ ] Hybrid  [ ] Remote  [x] Field based

Shifts I can work
  [x] Day  [x] Evening  [ ] Night  [ ] Rotating  [ ] Weekend

Available
  (o) Immediately  ( ) 15 days  ( ) 30 days  ( ) 60 days  ( ) 90+ days

Pay I'm looking for
  Minimum  [ 20,000 ] [ INR ] per [ month v ]
  Expected [ 28,000 ] [ INR ] per [ month v ]

Location
  Current: Saket, New Delhi
  Within [ 10 km ] of me
  [ ] Willing to relocate       [ ] Need accommodation
  [ ] Willing to travel         [ ] Need transport
```

Period selectors sit next to every amount. A daily-wage worker and a salaried engineer both
express themselves naturally, and Omelo does the normalisation.

### 10.6 Privacy and who can contact me

```
Who can find me
  ( ) No one - I'm not looking
  (o) Employers matching what I want
  ( ) Any verified employer

  Only about jobs paying at least  [ 20,000 INR / month ]
  Only for:  [Delivery Executive] [Driver] [+]

Never show me to
  [ Current Employer Ltd  x ]   [ + add ]
```

The blocklist is what makes Omelo usable by someone who already has a job. It is a query-time
exclusion: a blocked employer gets absence, never a signal that they were blocked.

---

## 11. My Career

```
My Career

  Where you are
    Electrician - Skilled level - 4 years
    Based on 3 jobs and a verified licence      [ Correct this ]

  Where you could go
    Electrician
        |
        +-- Senior Electrician       +25% pay      6-12 months
        +-- Site Supervisor          +40% pay      12-18 months
        +-- Electrical Contractor    +80% pay      2-3 years

  To become a Site Supervisor you would need
    Supervisor licence      -> how to get it
    Team management         -> 3 jobs near you build this
    Site safety training    -> 2-day course, Rs 3,500

    This would unlock 340 more jobs near you.

  Your skills in the market
    "Industrial wiring" appears in 34% more jobs than last quarter
```

Career intelligence is for trades as much as for professions. "How do I go from electrician to
contractor" is exactly as real a career question as "how do I go from engineer to architect" —
and nobody currently answers it.

While transition data is thin, paths come from taxonomy priors and the UI **says so** rather
than implying evidence it does not have.

---

## 12. Notifications

| Type | Deep link |
|---|---|
| New matching job | Job details |
| Job alert / saved search | Search results |
| Application update | Timeline |
| Recruiter message | Conversation |
| Interview scheduled / reminder | Interview details |
| Offer received | Offer |
| Document request | Document share consent |
| Verification update | Verification centre |
| Career recommendation | My Career |
| Job closing soon | Job details |
| Profile reminder | The specific section |

Every notification carries a `deeplink`. **Nothing is a dead end** — this is enforced by the
`notifications` table shape, not by convention.

Preferences: push, email, SMS, WhatsApp, per-type mute, and quiet hours. SMS and WhatsApp
matter — for a large part of the audience, push notifications on a shared or low-end device are
not reliable.

---

## 13. Complete CTA map

| CTA | Destination |
|---|---|
| Search jobs | Discover → Search |
| Find nearby jobs | Discover → Nearby |
| Recommended job | Job details |
| Apply | Apply flow |
| Quick apply | Confirm → Submit |
| Save | Saved jobs |
| Share | Share sheet |
| Ask recruiter | Conversation |
| View company | Company profile |
| Complete profile | Profile section with the biggest impact |
| Add skill / experience / education | That section |
| Add licence | Licences |
| Add certificate | Certifications |
| Verify | Verification centre |
| Create resume | Resume builder |
| Career path | My Career |
| Skill gap | My Career → gaps |
| Application | Timeline |
| Interview | Interview details |
| Offer | Offer details |
| Message | Conversation |
| Notification | Its deep link |
| Job alert | Saved searches |
| Report job | Report flow |
| Withdraw | Application |
| Accept / decline offer | Offer |
| Share document | Document consent |
| Revoke access | Document vault |
| Block company | Privacy |
| Settings | Settings |

---

## 14. Flow invariants

1. No flow dead-ends. Every failure state offers a next action.
2. Nothing reaches an employer without the person seeing the exact payload first.
3. Every AI-generated artifact passes user review before it leaves the account.
4. Every inference is shown with its evidence and is correctable.
5. Every exclusion is explainable to the person excluded.
6. Block and report are one tap from any employer-contact surface.
7. Every score links to why.
8. "Skip" exists on every profile step. Incomplete beats abandoned.
9. "None" is a valid answer everywhere, never a validation error.
10. Every amount of money is shown with its period.
