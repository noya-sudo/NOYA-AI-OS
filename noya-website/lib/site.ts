// Single source for public contact details, navigation and legal status.
// Contact details confirmed by Adam on 2026-09-28. Legal entity details are still outstanding.

export const SITE_URL = "https://www.noyaconcierge.com";

export const CONTACT = {
  email: "noya@noyaconcierge.com",
  whatsappDisplay: "+44 7864 569006",
  whatsappE164: "447864569006",
  instagram: "https://instagram.com/noyaconcierge",
} as const;

export function whatsappLink(message = "Hello NOYA, I would like to make a private enquiry.") {
  return `https://wa.me/${CONTACT.whatsappE164}?text=${encodeURIComponent(message)}`;
}

// REQUIRED_FROM_ADAM — never render these as if they were real values.
export const LEGAL = {
  entityName: null as string | null,
  jurisdiction: null as string | null,
  registeredAddress: null as string | null,
};

export type NavItem = { label: string; href: string; note?: string };

// Primary navigation — the eleven top-level destinations of the new site.
// URLs with existing search value are kept (see lib/redirects.ts).
export const NAV: NavItem[] = [
  { label: "Home", href: "/" },
  { label: "Egypt", href: "/egypt" },
  { label: "Destinations", href: "/destinations" },
  { label: "Services", href: "/services" },
  { label: "NOYA Private", href: "/membership" },
  { label: "Corporate", href: "/corporate-concierge" },
  { label: "Brands & Production", href: "/brands-production" },
  { label: "Weddings & Events", href: "/weddings-events" },
  { label: "Partners", href: "/partners" },
  { label: "About", href: "/about" },
  { label: "Enquire", href: "/contact" },
];
