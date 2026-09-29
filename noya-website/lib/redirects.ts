// Legacy Squarespace URL → new URL. Applied by next.config.ts on the NEW site only.
// Nothing here is deployed to the live Squarespace site.
//
// Kept as-is (have search value, map cleanly to the new architecture):
//   /                               Home (canonical homepage)
//   /corporate-concierge            Corporate
//   /membership                     NOYA Private
//   /contact                        Enquire
//   /about, /privacy-policy, /terms-conditions
//   /bespoke-travel, /hotels-villas-and-residences, /lifestyle-services,
//   /yacht-charter-private-aviation  → kept as service detail pages under /services (Phase 5)

export type Redirect = { source: string; destination: string; permanent: true; reason: string };

export const LEGACY_REDIRECTS: Redirect[] = [
  { source: "/home", destination: "/", permanent: true, reason: "Duplicate homepage (was in legacy sitemap)" },
  { source: "/what-we-do-folder", destination: "/services", permanent: true, reason: "Squarespace mobile-nav duplicate" },
  { source: "/what-we-do", destination: "/services", permanent: true, reason: "Services hub replaces What We Do" },
  { source: "/exclusive-access", destination: "/membership", permanent: true, reason: "Member-only access now part of NOYA Private" },
  { source: "/cart", destination: "/", permanent: true, reason: "Squarespace commerce default, no store" },
  { source: "/search", destination: "/", permanent: true, reason: "Squarespace system page" },
];
