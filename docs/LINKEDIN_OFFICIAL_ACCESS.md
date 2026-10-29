# LinkedIn: official access (29 Oct 2026)

**Short answer.** HQ has no live LinkedIn connection and will not claim one. LinkedIn only gives inbox and connection data to approved
partners, and the one self-serve route that includes the inbox is limited to members in the EU, EEA or Switzerland. Until LinkedIn
grants something, Adam's own data download stays the production truth.

## Phase A: production (in use now)

| Step | Who | What happens |
|---|---|---|
| Monthly export | Adam | LinkedIn → Settings → Data privacy → Get a copy of your data → *Connections*, *Messages* and *Invitations*. Upload the zip on the HQ LinkedIn page |
| Import | HQ | Connections and message history are matched to CRM people and companies. *Invitations.csv* sets **REQUEST PENDING** (Adam sent it: never send another) and **REQUEST RECEIVED** (they asked Adam: accept first, then write) |
| Warm-route check | HQ | Before any first message: Gmail history, LinkedIn connection, messages, pending requests, meetings, other people at the company, relationship edges. Outcome: WARM RECONNECT / EMAIL FIRST / LINKEDIN FIRST / INTRODUCTION ROUTE / HOLD |
| Send | Adam | Copy & Open → send in LinkedIn → Mark sent. The touch is logged, the follow-up booked, the task closed |

What HQ never does: session cookies, Unipile or any unofficial inbox tool, scraping Adam's account, sending anything by itself.

## Phase B: what LinkedIn actually offers

| Route | Gives | Who can get it | Realistic for NOYA |
|---|---|---|---|
| Sign In with LinkedIn (OpenID Connect) | Name, photo, email of the signed-in member | Any app, self-serve | Yes, but adds nothing commercial |
| Share on LinkedIn | Post to Adam's own feed | Any app, self-serve | Yes, but out of scope (no auto-posting) |
| Member Data Portability API (DMA) | Adam's own profile, connections and **inbox**, as a snapshot then a 28-day changelog, with one-year consent | Members located in the EU, EEA or Switzerland; needs a LinkedIn Company Page and app review | **Only if Adam's LinkedIn account is registered in the EU/EEA/Switzerland.** A UK or Egypt account is not eligible |
| Messaging / Compliance partner programmes | Inbox read and send | Approved partners only, private and paid | No |
| Sales Navigator Application Platform (SNAP) | CRM sync for Sales Navigator | Approved CRM vendors only (new partners rarely admitted) | No |

## If the DMA route applies

1. Create the NOYA Company Page (if it does not exist) and a LinkedIn developer app owned by it.
2. Request the *Member Data Portability (3rd party)* product. Application text, ready to submit:
   > NOYA Concierge is a concierge and destination company. With the member's consent, we read the member's own connections and
   > message history once, then the changelog, to show relationship context inside our private CRM, so that the member does not
   > contact the same person twice or cold-contact someone they already know. Read-only. We never send, post or message through
   > the API, never store data about members who did not consent beyond what the member's own export already contains, and delete
   > the data when consent is withdrawn or expires.
3. If granted: OAuth with the portability scope only, read first, nothing sent automatically. The import writes into the same
   tables as the archive upload, so HQ screens do not change.
4. If refused or not eligible: nothing changes. Phase A remains production.

## Decision for Adam

**Where is your LinkedIn account registered?** EU/EEA/Switzerland → apply (about one hour of setup on your side for the Company Page
and app). UK, Egypt or elsewhere → do not apply; keep the monthly export, which already gives HQ the same history.
