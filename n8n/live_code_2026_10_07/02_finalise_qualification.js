const GENERIC_DENYLIST = ['home','about','about us','contact','contact us','campaigns','campaign','news','blog','press','media','welcome','index','shop','store','products','services','portfolio','projects','careers','faq','sitemap','privacy policy','terms','become an ambassador','ambassador'];

function isUsable(name) {
  if (!name) { return false; }
  const n = name.trim().toLowerCase();
  if (n.length < 2) { return false; }
  if (GENERIC_DENYLIST.indexOf(n) !== -1) { return false; }
  return true;
}

const providerError = !!($json && $json.error);
const providerErrorSource = providerError ? ($json._provider || 'ANTHROPIC') : '';
const providerErrorReason = providerError ? ($json._reason || 'API_ERROR') : '';

const aiName = ($json.output && $json.output.verified_company_name) ? $json.output.verified_company_name.trim() : '';
const fallbackName = $('Load Final Candidates').item.json.company_name || '';

let finalCompanyName = '';
if (isUsable(aiName)) {
  finalCompanyName = aiName;
} else if (isUsable(fallbackName)) {
  finalCompanyName = fallbackName;
}

const missionValidTypes = {
  // Brands / PR / production lane (Adam, 7 Oct 2026): agencies, production companies and media (podcasts, YouTube
  // shows, publications that film) are in scope alongside brands; the minimum score still decides.
  BRAND: ['FASHION_BRAND','BEAUTY_BRAND','COSMETICS_BRAND','SKINCARE_BRAND','JEWELLERY_BRAND','WATCH_BRAND','AUTOMOTIVE_BRAND','SWIMWEAR_BRAND','LUXURY_GOODS_BRAND','LIFESTYLE_BRAND','CONSUMER_BRAND','FASHION_HOUSE',
          'MARKETING_AGENCY','PR_AGENCY','CREATIVE_AGENCY','PRODUCTION_COMPANY','MEDIA']
};

const mission = $('Load Final Candidates').item.json.mission;
const validTypes = missionValidTypes[mission] || missionValidTypes.BRAND;
const canonicalType = ($json.output && $json.output.canonical_company_type) ? $json.output.canonical_company_type.trim().toUpperCase() : 'UNKNOWN';
const missionFitComputed = validTypes.indexOf(canonicalType) !== -1;
const suggestedMission = ($json.output && $json.output.suggested_mission) ? $json.output.suggested_mission.trim().toUpperCase() : '';

return { json: { ...$json, final_company_name: finalCompanyName, name_ok: !!finalCompanyName, canonical_company_type: canonicalType, mission_fit_computed: missionFitComputed, suggested_mission: suggestedMission, evaluation_status: providerError ? 'PROVIDER_ERROR' : 'EVALUATED', provider_error_source: providerErrorSource, provider_error_reason: providerErrorReason } };