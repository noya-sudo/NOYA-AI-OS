# Marketing OS → NOYA HQ hand-off contract (v1, proposed)

Status: proposal. **No HQ change has been made.** The HQ intake described in §5 is a separate HQ change that needs Adam's approval
before anyone builds it. Until then, approved hand-offs wait in `leads.hq_handoffs` and Adam can copy them into HQ by hand.

## 1. Principle

Exactly one thing crosses: a **qualified commercial opportunity**. It crosses once, deliberately, with approval, and with only
the data HQ needs to act.

## 2. Qualification gates (all five must be true)

| Gate | Passes when | Example of failing |
|---|---|---|
| `identifiable` | A real person or organisation, named | Anonymous "how much?" comment |
| `reachable` | A usable contact route the person gave or published for business, with a lawful basis | Handle only, DMs closed |
| `real_need` | A NOYA service is wanted: travel, villa, yacht, aviation, events, production, corporate, partnership with commercial terms | "Love this!" |
| `fit` | Plausible for NOYA's positioning (destination, budget signal, B2B relevance) | A request for budget backpacking |
| `timing` | A date, season or active project, within about 12 months | "Someday" |

Verdicts:
- **qualified** (all five gates) → eligible for hand-off;
- **nurture** → stays in Marketing OS, on a nurture cadence;
- **not_relevant** → closed.

Scores (`fit_score`, `intent_score`) rank the queue. They never replace the gates.

**Stays in Marketing OS even when promising:** creator collaborations and press with no revenue, content partnerships (hotel
shoots, editorial), unpaid barters. **Crosses:** paid brand trips, productions with budget, corporate programmes, partners
proposing commission or retainer terms, private client requests.

## 3. Payload (v1)

```json
{
  "contract_version": "v1",
  "handoff_id": "7f0c…",                       // Marketing OS id; HQ stores it for idempotency
  "sent_at": "2026-11-07T10:00:00Z",
  "source": {
    "system": "noya-marketing-os",
    "channel": "instagram_dm",                  // see leads.inbound.channel
    "campaign": "egypt-winter-2027",            // UTM campaign or paid campaign name, if any
    "content_ref": "https://instagram.com/p/…", // the post or ad that started it, if known
    "first_touch_at": "2026-11-05T19:12:00Z"
  },
  "contact": {
    "name": "…",
    "company": "…",                             // null for private clients
    "role": "…",
    "email": "…",                               // only if the person gave it
    "phone": "…",                               // only if the person gave it
    "handle": "@…",
    "country": "GB",
    "lawful_basis": "enquiry"                   // enquiry | consent | legitimate_interest_b2b
  },
  "opportunity": {
    "segment": "private_client",                // private_client | corporate | travel_trade | brand_production | agency
    "services": ["villa", "yacht", "transfers"],
    "destination": "Red Sea, Egypt",
    "timing": "late March 2027, 6 nights",
    "party_size": 8,
    "budget_signal": "stated",                  // stated | inferred | unknown
    "budget_band": "GBP 40-60k",
    "summary": "Two families, 40th birthday, asked for a private villa with a yacht day. Prefers WhatsApp.",
    "excerpt": "…"                              // the minimum quoted text that justifies the need
  },
  "qualification": {
    "gates": { "identifiable": true, "reachable": true, "real_need": true, "fit": true, "timing": true },
    "fit_score": 82,
    "intent_score": 74,
    "assessed_by": "agent.lead_qualifier",
    "approved_by": "adam@…",
    "approved_at": "2026-11-07T09:58:00Z"
  }
}
```

Not sent: the full DM thread, follower data, other leads, internal marketing notes or analytics.

## 4. Delivery

1. The Lead Qualifier prepares `leads.hq_handoffs` (status `prepared`). The guard trigger refuses it unless the qualification
   verdict is `qualified` and all five gates are true.
2. An action request of type `hq.handoff_opportunity` is raised with the payload.
3. Adam approves (owner, with confirmation). The `handoff.hq` control must be armed.
4. The courier (n8n, no LLM) claims the request and POSTs to `HQ_HANDOFF_URL` with:
   - `Content-Type: application/json`;
   - `X-NOYA-Signature: sha256=<HMAC-SHA256(body, HQ_HANDOFF_SIGNING_SECRET)>`;
   - `X-NOYA-Timestamp: <unix seconds>` (HQ rejects anything older than 5 minutes);
   - `Idempotency-Key: <handoff_id>`.
5. HQ replies `{ "status": "accepted", "hq_reference": "<opportunity id>", "duplicate_of": null }` or
   `{ "status": "rejected", "reason": "…" }`.
6. Marketing OS records `delivered` / `acknowledged` or `rejected_by_hq`. A timeout is retried up to 3 times, with the same
   idempotency key.

## 5. What HQ would need (separate HQ change, not built)

A single intake that:
- verifies the HMAC, the timestamp and the idempotency key;
- **reuses HQ's own duplicate guards**, so an existing company, contact or open opportunity is matched, not duplicated;
- creates or links the company, contact and opportunity (source `MARKETING_OS`), plus one P1 task for Adam, exactly as workflow
  10d does for website enquiries today;
- writes HQ's own `approval_audit` row;
- returns `hq_reference`.

The natural home is a small HQ function next to the 10d website intake. Building it is HQ work, under HQ's own review.

## 6. Outcome feedback (closing the loop)

For attribution, Marketing OS needs to know what happened to each hand-off: `open`, `won`, `lost`, `duplicate` or `invalid`,
plus the value if won.

Preferred design: HQ calls a Marketing OS endpoint (signed the same way) when the opportunity stage changes. Marketing OS stores
only `hq_outcome`, `outcome_value_minor`, `outcome_currency` and `outcome_at`. No HQ client data flows back.

Until that exists, Adam (or the weekly review) records outcomes by hand.

## 7. Versioning

- Additive fields: same version. HQ ignores unknown fields.
- Renamed or removed fields: `v2`. Marketing OS can send both during a transition.
- HQ rejects unknown major versions.
