// Image registry. Every visual on the site resolves through here so that swapping a
// placeholder for owned photography is a one-line change.
//
// status:
//   TEMP_LOWRES  — safe NOYA-owned image, but cropped from a legacy screenshot. Replace with the original file.
//   PLACEHOLDER  — no approved image yet. Rendered as an art-directed tonal frame with a visible label.
//   FINAL        — approved original (none yet).

export type Scene =
  | "giza" | "cairo" | "nile" | "luxor" | "aswan" | "gouna" | "redsea" | "northcoast" | "sharm"
  | "riviera" | "aegean" | "monaco" | "alpine" | "engadin" | "desert-city" | "london" | "paris" | "milan"
  | "night" | "sea" | "sky" | "interior" | "studio" | "dinner";

export type Media =
  | { status: "TEMP_LOWRES" | "FINAL"; src: string; alt: string; width: number; height: number; note?: string }
  | { status: "PLACEHOLDER"; scene: Scene; alt: string; brief: string };

const ph = (scene: Scene, alt: string, brief: string): Media => ({ status: "PLACEHOLDER", scene, alt, brief });

export const MEDIA = {
  heroGiza: ph("giza", "The Giza plateau at first light", "Hero — Giza plateau, first light, no crowds. Owned or commissioned footage/photo."),
  poolsideTowels: {
    status: "TEMP_LOWRES", src: "/images/temp/noya-poolside-towels__edge-7__lowres.jpg",
    alt: "NOYA Concierge towels and robe beside a private pool", width: 953, height: 454,
    note: "Legacy Edge-7.jpg (NOYA-owned). Replace with original from download_assets.sh",
  },
  robes: {
    status: "TEMP_LOWRES", src: "/images/temp/noya-robes__about-12__lowres.jpg",
    alt: "Two guests in NOYA Concierge robes overlooking the sea", width: 514, height: 640,
    note: "Legacy About 12.png (NOYA-owned shoot). Confirm model release; replace with original",
  },
  businessCards: {
    status: "TEMP_LOWRES", src: "/images/temp/noya-business-cards__about-us-page__lowres.jpg",
    alt: "NOYA Concierge cards on a dark desk", width: 550, height: 413,
    note: "Legacy 'About us page.jpg' (NOYA-owned). Replace with original",
  },

  cairo: ph("cairo", "Cairo at dusk", "Cairo — Nile corniche or Islamic Cairo at dusk"),
  pyramids: ph("giza", "The Pyramids of Giza", "Pyramids — private early access"),
  nile: ph("nile", "Sailing on the Nile", "Nile — private boat, late afternoon"),
  luxor: ph("luxor", "Temple columns in Luxor", "Luxor — temple detail"),
  aswan: ph("aswan", "Aswan and the first cataract", "Aswan — granite and river"),
  gouna: ph("gouna", "El Gouna lagoon", "El Gouna — villa or lagoon (legacy IMG_0346 is a candidate)"),
  redsea: ph("redsea", "The Red Sea from a private boat", "Red Sea — boat, open water"),
  northcoast: ph("northcoast", "The Mediterranean at Egypt's North Coast", "North Coast — Sahel beach, summer"),
  sharm: ph("sharm", "Sharm El Sheikh coastline", "Sharm — reef and desert meeting"),

  stTropez: ph("riviera", "St Tropez harbour", "St Tropez"),
  mykonos: ph("aegean", "Mykonos above the Aegean", "Mykonos (legacy villa set is UNCERTAIN — needs owner permission)"),
  monaco: ph("monaco", "Monaco harbour", "Monaco"),
  courchevel: ph("alpine", "Courchevel in winter", "Courchevel — do NOT use legacy Consensio chalet set"),
  stMoritz: ph("engadin", "St Moritz lake", "St Moritz"),
  dubai: ph("desert-city", "Dubai at dusk", "Dubai"),
  london: ph("london", "London, Mayfair", "London"),

  hotels: ph("interior", "Hotel suite", "Hotels & residences"),
  villas: ph("aegean", "Private villa pool", "Private villas"),
  aviation: ph("sky", "Private jet on the apron", "Private aviation"),
  yachts: ph("sea", "Yacht at anchor", "Yachts"),
  airport: ph("night", "Private terminal", "Airport VIP"),
  chauffeur: ph("night", "Chauffeured car at night", "Chauffeur & security"),
  dining: ph("dinner", "Private dining table", "Dining"),
  experiences: ph("giza", "A private moment", "Private experiences"),

  production: ph("studio", "Campaign production on location", "Brands & production — BTS of a real NOYA shoot"),
  brandTrip: ph("gouna", "Brand trip on the Red Sea", "Brand trip"),

  storyRedSea: ph("redsea", "The Red Sea by boat", "Story — Red Sea / El Gouna"),
  storyNile: ph("luxor", "Luxor and Aswan", "Story — Luxor & Aswan"),
  storyAlps: ph("alpine", "Courchevel in winter", "Story — Alps"),
  storyPyramids: ph("giza", "Runway at the Pyramids", "Story — brand event at the Pyramids (legacy 0-1.jpg.webp; confirm rights)"),
} satisfies Record<string, Media>;
