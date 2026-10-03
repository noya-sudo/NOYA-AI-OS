
const first = $input.first().json;
const raw = (first && first.body) ? first.body : (first || {});

function s(v) { return (v === undefined || v === null) ? '' : String(v).trim(); }
function num(v) { const n = Number(v); return Number.isFinite(n) ? n : null; }

const menuCategory = s(raw.menu_category).toUpperCase();
const validCategories = ['PRIVATE_VILLAS', 'TRAVEL_LIFESTYLE', 'CORPORATE_BRAND', 'WEDDING_EVENT', 'MEMBERSHIP', 'OTHER'];
const categoryToLeadType = {
  PRIVATE_VILLAS: 'VILLA_ENQUIRY',
  TRAVEL_LIFESTYLE: 'PRIVATE_CONCIERGE_ENQUIRY',
  CORPORATE_BRAND: 'CORPORATE_ENQUIRY',
  WEDDING_EVENT: 'WEDDING_EVENT_ENQUIRY',
  MEMBERSHIP: 'MEMBERSHIP_APPLICATION',
  OTHER: 'GENERAL_ENQUIRY',
};

// The six SPEAK TO NOYA categories cannot on their own reach BRAND_PRODUCTION_ENQUIRY
// or PARTNERSHIP_ENQUIRY, so the corporate/brand form sends an optional requirement_type
// that refines the base mapping. Deterministic keyword match, no AI, no guessing:
// an unrecognised or absent requirement_type leaves the category mapping untouched.
const requirementType = s(raw.requirement_type).toUpperCase();
const baseLeadType = categoryToLeadType[menuCategory] || 'GENERAL_ENQUIRY';

function refineLeadType(category, requirement, base) {
  if (!requirement) return base;
  const isProduction = /BRAND|PRODUCTION|SHOOT|CAMPAIGN|CONTENT|CREATIVE|EDITORIAL/.test(requirement);
  const isPartnership = /PARTNER|AFFILIATE|REFERRAL|COLLAB|SUPPLIER|TRADE/.test(requirement);
  if (isPartnership) return 'PARTNERSHIP_ENQUIRY';
  if (isProduction && category === 'CORPORATE_BRAND') return 'BRAND_PRODUCTION_ENQUIRY';
  return base;
}

const leadType = refineLeadType(menuCategory, requirementType, baseLeadType);

const email = s(raw.email).toLowerCase();
const fullName = s(raw.full_name);
const phone = s(raw.phone);
const nameParts = fullName.split(/\s+/).filter(Boolean);
const firstName = nameParts.length > 0 ? nameParts[0] : '';
const lastName = nameParts.length > 1 ? nameParts.slice(1).join(' ') : '';

const errors = [];
if (!validCategories.includes(menuCategory)) errors.push('menu_category must be one of: ' + validCategories.join(', '));
if (!fullName) errors.push('full_name is required');
if (!email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) errors.push('a valid email is required');

const utmSource = s(raw.utm_source);
const utmMedium = s(raw.utm_medium);
const utmCampaign = s(raw.utm_campaign);
const utmContent = s(raw.utm_content);
const utmTerm = s(raw.utm_term);
const hasUtm = !!(utmSource || utmMedium || utmCampaign);
const attributionConfidence = hasUtm ? 'ESTIMATED' : 'UNKNOWN';

function randomToken(len) {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  let out = '';
  for (let i = 0; i < len; i++) out += chars.charAt(Math.floor(Math.random() * chars.length));
  return out;
}
function uuidv4() {
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function (c) {
    const r = Math.floor(Math.random() * 16);
    const v = c === 'x' ? r : ((r & 0x3) | 0x8);
    return v.toString(16);
  });
}

const clientSubmissionId = s(raw.client_submission_id);
const submissionId = clientSubmissionId.length >= 8 ? clientSubmissionId : uuidv4();
const reference = 'NOYA-' + randomToken(6);

const companyName = s(raw.company_name);
const destination = s(raw.destination);
const dateFrom = s(raw.date_from) || null;
const dateTo = s(raw.date_to) || null;
const guests = num(raw.guests);
const bedrooms = num(raw.bedrooms);
const budget = s(raw.budget);
const propertyPreferences = s(raw.property_preferences);
const occasion = s(raw.occasion);
const specialRequirements = s(raw.special_requirements);
const message = s(raw.message);

const summaryParts = [];
if (destination) summaryParts.push('Destination: ' + destination);
if (dateFrom || dateTo) summaryParts.push('Dates: ' + (dateFrom || '?') + ' to ' + (dateTo || '?'));
if (guests) summaryParts.push('Guests: ' + guests);
if (bedrooms) summaryParts.push('Bedrooms: ' + bedrooms);
if (budget) summaryParts.push('Budget: ' + budget);
if (propertyPreferences) summaryParts.push('Preferences: ' + propertyPreferences);
if (occasion) summaryParts.push('Occasion: ' + occasion);
if (specialRequirements) summaryParts.push('Special requirements: ' + specialRequirements);
if (requirementType) summaryParts.push('Requirement type: ' + requirementType);
if (companyName) summaryParts.push('Company: ' + companyName);
if (message) summaryParts.push('Message: ' + message);
const opportunitySummary = summaryParts.length > 0 ? summaryParts.join(' | ') : 'No additional details provided.';

// Private Calendar (website V3, 3 Oct 2026): "Plan around this event" sends
// source = website_calendar with the event's id (its /calendar/<slug>), name, city
// and dates (YYYY-MM-DD/YYYY-MM-DD). HQ then reads Website → Private Calendar → event.
// Every other enquiry sends none of these, so nothing below changes for them.
const isCalendar = s(raw.source).toLowerCase() === 'website_calendar' && !!s(raw.event_name);
const eventId = isCalendar ? s(raw.event_id).slice(0, 120) : '';
const eventName = isCalendar ? s(raw.event_name).slice(0, 200) : '';
const eventCity = isCalendar ? s(raw.event_city).slice(0, 120) : '';
const eventDates = isCalendar ? s(raw.event_dates).slice(0, 40) : '';
const eventWhereWhen = [eventCity, eventDates.replace('/', ' to ')].filter(Boolean).join(', ');
const eventLabel = isCalendar ? eventName + (eventWhereWhen ? ' (' + eventWhereWhen + ')' : '') : '';

// Website context (website v2, 30 Sep 2026): where the enquiry came from. Stored as
// text on the opportunity / interaction; landing page, referrer and UTMs are also
// written to their own columns below.
const landingPage = s(raw.landing_page).slice(0, 500);
const referrer = s(raw.referrer).slice(0, 500);
const sourcePage = s(raw.source_page).slice(0, 300);
const clientSubmittedAt = s(raw.submitted_at).slice(0, 40);
const contextParts = [isCalendar ? 'Channel: Website → Private Calendar → ' + eventLabel : 'Channel: Website'];
if (isCalendar && eventId) contextParts.push('Event page: /calendar/' + eventId);
if (sourcePage) contextParts.push('Form page: ' + sourcePage);
if (landingPage) contextParts.push('Landing page: ' + landingPage);
if (referrer) contextParts.push('Referrer: ' + referrer);
const utmPairs = [['source', utmSource], ['medium', utmMedium], ['campaign', utmCampaign], ['content', utmContent], ['term', utmTerm]]
  .filter(function (p) { return p[1]; })
  .map(function (p) { return p[0] + '=' + p[1]; });
if (utmPairs.length) contextParts.push('UTM: ' + utmPairs.join(', '));
if (clientSubmittedAt) contextParts.push('Sent from browser at: ' + clientSubmittedAt);
const websiteContext = contextParts.join(' | ');

return [{
  json: {
    isValid: errors.length === 0,
    errors,
    submissionId,
    reference,
    menuCategory,
    leadType,
    requirementType,
    fullName,
    firstName,
    lastName,
    email,
    phone,
    destination,
    dateFrom,
    dateTo,
    guests,
    bedrooms,
    budget,
    propertyPreferences,
    occasion,
    specialRequirements,
    companyName,
    hasCompanyName: !!companyName,
    message,
    opportunitySummary,
    utmSource,
    utmMedium,
    utmCampaign,
    utmContent,
    utmTerm,
    landingPage,
    referrer,
    sourcePage,
    clientSubmittedAt,
    websiteContext,
    websiteSessionId: s(raw.website_session_id),
    attributionConfidence,
    isCalendar,
    sourceDetail: isCalendar ? 'PRIVATE_CALENDAR' : '',
    eventId,
    eventName,
    eventCity,
    eventDates,
    eventLabel,
  }
}];
