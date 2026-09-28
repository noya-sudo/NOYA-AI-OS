#!/usr/bin/env python3
"""
Builds the machine-readable legacy-site inventory from the crawl of
https://www.noyaconcierge.com captured 2026-09-28 (via Firecrawl, live fetch, maxAge=0).

Every value below was extracted from the live site. Nothing is invented.
Outputs:
  content/pages.json                 page-level inventory (metadata, headings, CTAs, forms, images, links)
  assets/images/IMAGE_MANIFEST.csv   one row per unique image URL, with pages + role + rights flag
  assets/download_assets.sh          fetches every original image into assets/images/ (run where the CDN is reachable)
"""
import csv, json, os, re, urllib.parse

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
P = "https://images.squarespace-cdn.com/content/v1/6a2ca70a5f4ef31a099c9b40/"
SITE = "https://www.noyaconcierge.com"
CAPTURED = "2026-09-28"

GLOBAL_ASSETS = [
    ("logo-header", P + "1781311265119-157C4WQPYBJUH7PN8TJ7/Screenshot+2026-01-15+at+19.54.04.png"),
    ("logo-header-variant", P + "1781311265806-WPK0HRB2SQ6HB47RUFY8/Screenshot+2026-01-15+at+19.54.04.png"),
    ("logo-footer (served from a DIFFERENT Squarespace site id 696944e5...)",
     "https://images.squarespace-cdn.com/content/v1/696944e519264306716a67e5/c12883f1-cb6c-43d0-b47b-e7943706eb7f/Screenshot+2026-01-15+at+19.54.04.png"),
    ("favicon", P + "1781311267277-PB6WI45YE8V1VI68XIEY/favicon.ico"),
    ("og-share-image (all pages)", "https://static1.squarespace.com/static/6a2ca70a5f4ef31a099c9b40/t/6a2ca7225f4ef31a099ca014/1744398030158/Beyond+Luxury.-2+2.jpg"),
]

ENQ_FORM = ["First Name*", "Last Name*", "Email*", "Phone*", "Country of Residence*",
            "How did you hear about us?*", "Let us know how we can help you ?*"]

def imgs(prefix_list):
    return [(role, (u if u.startswith("http") else P + u)) for role, u in prefix_list]

PAGES = [
  dict(slug="/", nav="Home", type="Homepage", in_sitemap=False,
       title="N O Y A", meta="Noya tailors your exclusive travel, premium accommodations, and VIP experiences across Egypt. Elevate your journey with seamless luxury and world-class service.",
       h1=None,
       headings=["H2 Beyond Luxury.", "H2 Tailored For You.", "(label) Bespoke Concierge", "H2 Bespoke Travel", "H2 Lifestyle Services",
                 "H2 Hotels, Villas & Residences", "H2 Yacht Charter and Private Aviation", "H2 Exclusive Access",
                 "H2 Access Exclusive First and Business Class Rates", "(label) Business Services", "H2 Corporate Concierge",
                 "H2 Private Events", "H2 Brand Events and Experiences", "H2 Inquire Privately", "H2 Follow us", "H3 FAQs"],
       ctas=["Make an Enquiry (href=/ — self-link)", "Apply for membership (href=/ — should be /membership)",
             "Explore private travel → /bespoke-travel", "Explore lifestyle → /lifestyle-services",
             "Discover villas → /hotels-villas-and-residences", "Request aviation → /yacht-charter-private-aviation",
             "Explore access → /exclusive-access", "Make an Enquiry (href=/)", "Explore corporate concierge → /corporate-concierge",
             "Plan a private event → /#speak-to-noya", "Start a brand project → /#speak-to-noya",
             "Follow us → instagram.com/noyaconcierge", "Become a member (header) → /membership",
             "Speak to NOYA (floating button, opens 'Private enquiry' popup)"],
       forms=[("Inquire Privately", ENQ_FORM)],
       images=imgs([
         ("hero", "1781311257872-JW0NIO3W7UL0DJAZV29A/Edge-7.jpg"),
         ("card: Bespoke Travel (alt: Aerial view of a Mediterranean coastline)", "1781311258030-J8K0RKUGC824UKODUPRN/96.jpg"),
         ("card: Lifestyle Services", "1781311253533-GRBELB3R0OLI41D6IC6V/Screenshot+2024-09-18+at+02.59.18.png"),
         ("card: Hotels, Villas & Residences", "1781311253539-MSAUWZ1BHK01R3QQ3U2U/67.jpg"),
         ("card: Yacht Charter + card: Exclusive Access (same image used twice; alt: Superyacht moored at a marina)", "7b34cb8c-d659-4b19-8e5e-1ed4b9c64ff2/IMG_4968.jpg"),
         ("banner: First & Business Class", "1781311253557-2L9903LEJ421I0G2XM94/Fly+web.jpg"),
         ("card: Corporate Concierge", "1781311253562-XAYX1LJWVPGZTV2C0SPE/About+us+page.jpg"),
         ("card: Private Events", "1781311253567-3ZHST7176QAG0KZJ5V16/Edge-93.jpg"),
         ("card: Brand Events and Experiences", "1781311253573-Q1SNMP4SP7A6SSZKEF3K/0-1.jpg.webp"),
         ("Follow us grid 1", "1781311253582-ICZ949FZYWWTHLGP2A6G/Screenshot+2024-09-18+at+02.51.48.png"),
         ("Follow us grid 2", "1781311253587-5EWVHGY77VJGEB13RLB3/Screenshot+2024-09-04+at+17.34.53.jpg"),
         ("Follow us grid 3", "1781311253593-53HJG8AQTHFDY4GKPXUR/Screenshot+2024-10-02+at+06.46.47.png"),
         ("Follow us grid 4", "1781311253599-BUCC93D2MQ4DVZKA6PD7/Screenshot+2024-09-18+at+02.51.08.png"),
         ("sitemap-only (listed in sitemap for /home, not rendered)", "1781311253552-E7VQWCAUWR2H04DPYSJW/78.jpg"),
       ])),
  dict(slug="/home", nav="(none — duplicate of /)", type="Duplicate homepage", in_sitemap=True,
       title="N O Y A", meta="(same as /)", h1=None, headings=["(identical to /)"], ctas=["(identical to /, hrefs point to /home)"],
       forms=[("Inquire Privately", ENQ_FORM)], images=[], duplicate_of="/"),
  dict(slug="/what-we-do", nav="What We Do ▸ What We Do", type="Services hub", in_sitemap=True,
       title="What We Do — NOYA Concierge",
       meta="Private travel, villas, dining, access and lifestyle management, arranged by NOYA Concierge for private clients, families and corporate teams.",
       h1=None,
       headings=["H3 What We Do", "H2 Bespoke Travel", "H2 Hotels, Villas & Residences", "H2 Lifestyle services",
                 "H2 Exclusive Access", "H2 Yacht Charter and Private Aviation", "H2 Real estate (Coming Soon)", "H2 Inquire Privately"],
       ctas=["Make an Enquiry (href=/what-we-do — self-link)", "Explore private travel → /bespoke-travel",
             "Discover villas → /hotels-villas-and-residences",
             "'Coming soon' shown on Lifestyle, Exclusive Access, Yacht/Aviation, Real estate cards (pages for the first three ARE live)"],
       forms=[("Inquire Privately", ENQ_FORM)],
       images=imgs([
         ("hero", "1790533186665-4TX0S5YVWE5XYVLYLTL1/unsplash-image-JdQPgyry4ws.jpg"),
         ("card: Bespoke Travel", "1781311264157-TXFVCX7CY6PSLEZDWF0D/Screenshot+2026-01-20+at+04.17.48.png"),
         ("card: Hotels, Villas & Residences", "1781311264162-1IRHX91DUCBYFKMNYWBZ/67.jpg"),
         ("card: Lifestyle services", "1781311264167-CJ1UD65CDJ1IE22GNCT5/Screenshot+2024-09-18+at+02.59.18.png"),
         ("card: Exclusive Access (alt: Exclusive access arranged by NOYA Concierge)", "1781311264173-0N1JC0ZYMA70CFT1LQZZ/IMG_2641.png"),
         ("card: Yacht Charter and Private Aviation", "7b34cb8c-d659-4b19-8e5e-1ed4b9c64ff2/IMG_4968.jpg"),
         ("card: Real estate", "1781311264181-SDOTLDGX3X36VHU5YRJ1/78.jpg"),
       ])),
  dict(slug="/what-we-do-folder", nav="(mobile nav folder URL: 'Folder:What We Do')", type="Duplicate of /what-we-do", in_sitemap=False,
       title="What We Do — NOYA Concierge", meta="(same as /what-we-do)", h1=None, headings=["(identical to /what-we-do)"],
       ctas=["(identical)"], forms=[("Inquire Privately", ENQ_FORM)], images=[], duplicate_of="/what-we-do"),
  dict(slug="/bespoke-travel", nav="What We Do ▸ Bespoke Travel", type="Service page", in_sitemap=True,
       title="Bespoke Travel — NOYA Concierge",
       meta="Tailor-made private travel arranged end to end by NOYA Concierge: itineraries, hotels, villas, aviation and ground, with specialist execution in Egypt.",
       h1=None,
       headings=["H3 Your passport to a world of luxury, tailor-made travel", "H2 Tailor-Made Itineraries", "H2 Seamless Travel Logistics",
                 "H2 Destination Expertise & On-Ground Support", "H2 Access Exclusive First and Business Class Rates",
                 "H3 Coastal living - El Gouna, Red Sea", "H3 A winter escape in the alpines most luxurious destinations",
                 "H3 Luxor & Aswan - The Nile River", "H2 Inquire Privately"],
       ctas=["Make an Enquiry (href=/bespoke-travel — self-link)", "Make an Enquiry (href=/)"],
       forms=[("Inquire Privately", ENQ_FORM)],
       images=imgs([
         ("hero", "1781311249964-80PDMTSW07BFXVP5BT5Y/Screenshot+2024-09-18+at+02.51.48.png"),
         ("card: Tailor-Made Itineraries", "1781311249974-HNYHYWCIT795HXXSPFAG/12.png"),
         ("card: Seamless Travel Logistics", "1781311249980-Q5PY9A542XZMBKC8DMNR/Screenshot+2024-09-18+at+02.59.18.png"),
         ("card: Destination Expertise", "1781311249986-30USA66P378IV8A0ZAL3/1.png"),
         ("banner: First & Business Class", "1781311249991-T2DR2P77V7G7R9CL4TIB/Fly+web.jpg"),
         ("El Gouna 1", "1781311249997-L86ODU1GNWKX5V2C8PUD/IMG_0346.jpg"),
         ("El Gouna 2", "1781311250003-B9M3HPDIB1OWLF1QFHQT/Screenshot+2026-01-20+at+04.17.48.png"),
         ("El Gouna 3", "1781311250008-JP9EJCE45O1Q3DOZSVKI/IMG_0757.jpg"),
         ("Alps 1", "1781311250013-GIJMS5VZ3UFUSXZYVB11/23.jpg"),
         ("Alps 2", "1781311250020-GXKYSLLGMBN2QRROAZYR/26.jpg"),
         ("Alps 3", "1781311250026-BH0RGO70MUO5PPPPBNRN/7.jpg"),
         ("Luxor & Aswan 1", "1781311250033-7H6QW30FTRJN2HC8M1TQ/Temple+post.jpg"),
         ("Luxor & Aswan 2", "1781311250039-IBSGR9T4MGR24OK7OABM/5971bf58a4e98100785641.jpg"),
         ("Luxor & Aswan 3", "1781311250045-WASJ0FPDMHTZ93DJF9YJ/IMG_2284+4.PNG"),
       ])),
  dict(slug="/hotels-villas-and-residences", nav="What We Do ▸ Hotels, Villas and Residences", type="Service page + property showcase", in_sitemap=True,
       title="Hotels, Villas and Residences — NOYA Concierge",
       meta="Private villas, residences and hotel access sourced and arranged by NOYA Concierge, from Courchevel to the Red Sea.",
       h1=None,
       headings=["H3 Hotels, Private Villas and Residences", "H2 Luxury Hotels", "H2 Private Villas", "H2 Exclusive Residences",
                 "H3 Chalet Grenier, Courchevel 1850", "H3 Mykonos, Greece", "H3 Can Cielo, South East Ibiza, Spain", "H2 Inquire Privately"],
       ctas=["Make an Enquiry (href=/hotels-villas-and-residences — self-link)"],
       forms=[("Inquire Privately", ENQ_FORM)],
       images=imgs(
         [("hero (same as homepage hero)", "1781311257872-JW0NIO3W7UL0DJAZV29A/Edge-7.jpg"),
          ("card: Luxury Hotels", "1781311257881-30CUEVG2MLHE9RXIPW81/Screenshot+2026-01-20+at+04.17.48.png"),
          ("card: Private Villas", "1781311257888-Q7976LIRAD4YKX13LVM8/70.jpg"),
          ("card: Exclusive Residences", "1781311257894-MC1N1VYLQXD7UBK30QYU/6.jpg"),
          ("Chalet Grenier feature 1", "1781311257899-AI1508SSKCT466JDOBR1/Chalet-Le-Namaste-Courchevel-Consensio-Lounge-View.jpg"),
          ("Chalet Grenier feature 2", "1781311257904-I5HDP2N02K8YUMPX6QK1/Screenshot+2026-02-23+at+01.39.49.png"),
          ("Chalet Grenier feature 3", "1781311257909-E7WMQOD3YFGKBP4JPMWQ/Chalet-Le-Namaste-Courchevel-Consensio-Lounge.jpg")]
         + [("Chalet Grenier gallery", "1781311" + s) for s in [
            "257915-UU7PNMM9FG7BX7I33KC3/Chalet-Le-Namaste-Courchevel-Consensio-Dining-Room.jpg",
            "257921-CSI2C67U746E5RWMVKBS/Chalet-Le-Namaste-Courchevel-Consensio-Lounge-View.jpg",
            "257926-N7R3VNAKKL5PFDJKLAW2/Chalet-Le-Namaste-Courchevel-Consensio-Terrace-View.jpg",
            "257931-WQQ2UDW8RWYKDQOX1R6R/Chalet-Le-Namaste-Courchevel-Consensio-Balcony.jpg",
            "257936-7RCEA0Y9X8DQQV6F5PF4/Chalet-Le-Namaste-Courchevel-Consensio-Games-room.jpg",
            "257942-2WQVCDRU79ZNFDDFWADH/Chalet-Le-Namaste-Courchevel-Consensio-Boot-Room.jpg",
            "257947-H8MOU9Q3X5J3G4I26MHX/Chalet-Le-Namaste-Courchevel-Consensio-Sauna.jpg",
            "257953-792VFECG8VIG238OM6WA/Chalet-Le-Namaste-Courchevel-Consensio-Swimming-Pool.jpg",
            "257958-0WK9B2AJX39W1O1R7A8H/Chalet-Le-Namaste-Courchevel-Consensio-Gym.jpg",
            "257964-5EXZ85O6V3DPQ2NQIFXN/Chalet-Le-Namaste-Courchevel-Consensio-Massage-Room.jpg",
            "257970-6E69YVPO9QP4E1WMSB43/Chalet-Le-Namaste-Courchevel-Consensio-Bedroom-1jpg.jpg",
            "257974-5YSAZ51MCCX0EJGJAH1N/Chalet-Le-Namaste-Courchevel-Consensio-TV-snug.jpg",
            "257980-W73JXWFA4M329EGU00FB/Chalet-Le-Namaste-Courchevel-Consensio-Bathroom-1.jpg",
            "257985-VID1NGM8L24B46P5U6RN/Chalet-Le-Namaste-Courchevel-Consensio-Entrance.jpg",
            "257990-FCYFE8T6HNT49QBKQJD4/Chalet-Le-Namaste-Courchevel-Consensio-Champagne.jpg",
            "257995-F6708XYTKI9B5VJBHTDI/Chalet-Le-Namaste-Courchevel-Consensio-Bathroom-1.jpg",
            "258000-XC005W7YM4AEC66FHZYX/Chalet-Le-Namaste-Courchevel-Consensio-Bathroom-Bedroom-1.jpg",
            "258006-46GK7REBRHPC3ETBHH6Q/Chalet-Le-Namaste-Courchevel-Consensio-Bedroom-3.jpg",
            "258011-GF23JONSZY7V0PU8ZTBN/Chalet-Le-Namaste-Courchevel-Consensio-Bedroom-4.jpg",
            "258018-W210C65CH5D2J29KWI9N/Chalet-Le-Namaste-Courchevel-Consensio-Bedroom-5.jpg"]]
         + [("Mykonos feature", "1781311" + s) for s in [
            "258024-SPKKECIKLW0U8F8F9EHI/72.jpg", "258030-J8K0RKUGC824UKODUPRN/96.jpg", "258036-5E1MMO79HJ6EIHOWZSVF/70.jpg"]]
         + [("Mykonos gallery", "1781311" + s) for s in [
            "258042-8RQCZDS9KWHJGDKRMBNR/102.jpg", "258048-LVO51US5AGVR6PYSBEBT/67.jpg", "258054-LULI1QQNFSDH587DFTLE/75.jpg",
            "258059-QOKQD1OKTWFP7KRIDOJF/71.jpg", "258065-FGXEFRB1HZ8YNMW0792H/62.jpg", "258070-U230DN77HHR4GMS7JFGG/76.jpg",
            "258075-3MRPM5TNVNGO0ZDLJQIP/93.jpg", "258081-LVKQQ6IY56FI47ZWYLTJ/92.jpg", "258087-PLRCPHX3H0XSPNIWKBGE/100.jpg",
            "258093-KYL06WCQ35R9LG91O28E/90.jpg", "258099-TWF30KV0B7CGT6NN71WP/97.jpg", "258104-FLKI9ZM738WCW4SW8TAX/101.jpg",
            "258109-5EUR5KKYZYIBVWPXTOO6/59.jpg"]]
         + [("Can Cielo Ibiza feature", "1781311" + s) for s in [
            "258116-LYKJ1PAVQ9Y312T2EQF2/Screenshot+2026-02-21+at+15.44.03.png",
            "258122-IHO8CPT8DMSIGLGO14J2/Screenshot+2026-02-21+at+15.43.23.png",
            "258128-IG5K3I5LEIQL20YNFEEM/Screenshot+2026-02-21+at+15.52.34.png"]]
         + [("Can Cielo Ibiza gallery", "1781311" + s) for s in [
            "258134-5I0KQV0A80ERLYAZVM4Y/Screenshot+2026-02-21+at+15.44.48.png",
            "258140-PKG78KN30LDWUMU6ZUGF/Screenshot+2026-02-21+at+15.44.24.png",
            "258145-607N4IYRN3W3GD3SJ2FF/Screenshot+2026-02-21+at+15.50.53.png",
            "258151-8WSBKN63UHQRBYAO3BK2/Screenshot+2026-02-21+at+15.51.32.png",
            "258157-UIFH958EFI4GGNFAY6ID/Screenshot+2026-02-21+at+15.50.16.png",
            "258162-ZB7K5D7JZ52U6ODAKNLM/Screenshot+2026-02-21+at+15.44.38.png",
            "258168-W8L70B8465DHY9FCO7H4/Screenshot+2026-02-21+at+15.50.26.png",
            "258173-I7NI7MEDXSGRQ2EA35PO/Screenshot+2026-02-21+at+15.52.08.png"]]
       )),
  dict(slug="/lifestyle-services", nav="What We Do ▸ Lifestyle Services", type="Service page", in_sitemap=True,
       title="Lifestyle Services — NOYA Concierge",
       meta="Ongoing lifestyle management from NOYA Concierge: reservations, access, logistics and everyday support for private clients.",
       h1=None,
       headings=["H3 Live an extraordinary life – whatever that looks like to you", "H2 Fine dining and nightlife reservations",
                 "H2 Gifting and sourcing luxury items", "H2 Assisting with everyday requests", "H3 Fine dining and nightlife reservations",
                 "H3 Gifting and Personal Shopping", "H2 Inquire Privately"],
       ctas=["Make an Enquiry (href=/lifestyle-services — self-link)"],
       forms=[("Inquire Privately", ENQ_FORM)],
       images=imgs([
         ("hero", "1781311245315-S1ZRQH3WTHI7IA1VJDF4/Screenshot+2026-02-08+at+22.49.18.png"),
         ("card: Fine dining", "1781311245326-O0QBFX5KZFXGSLBFTP7B/carbone.jpg"),
         ("card: Gifting and sourcing", "1781311245332-77LJ1U026VIKNGEQYH19/hero-concierge.jpg.webp"),
         ("Fine dining feature 1", "1781311245340-7MF47QVHBJ8L4JDCBBT0/Tables-Girafe-250610-003.jpg"),
         ("Fine dining feature 2", "1781311245346-38CYM2PC57ZV3HHCEM3T/1.jpg"),
         ("Fine dining feature 3", "1781311245351-0WCJXZCOS9HE47YNF40E/DSC_2941-CHEF-IN-KITCHEN.jpg"),
         ("Gifting feature 1", "1781311245357-8AXIRXYSZQ6STQFU36I5/IMG_1913.png"),
         ("Gifting feature 2", "1781311245364-5JFTG2B49Z5B2WD085PE/Screenshot+2026-02-12+at+16.04.56.png"),
         ("Gifting feature 3", "1781311245370-0B45UAJ41OXDW8024IVM/Screenshot+2026-02-12+at+16.09.22.png"),
       ])),
  dict(slug="/yacht-charter-private-aviation", nav="What We Do ▸ Yacht Charter & Private Aviation", type="Service page", in_sitemap=True,
       title="Yacht Charter & Private Aviation — NOYA Concierge",
       meta="Yacht charter and private aviation arranged by NOYA Concierge, with vetted operators and full ground coordination.",
       h1=None,
       headings=["H3 Yacht Charter and Private Aviation", "H2 Yacht Charter", "H2 Private Aviation", "H2 Inquire Privately"],
       ctas=["Make an Enquiry (href=/yacht-charter-private-aviation — self-link)"],
       forms=[("Inquire Privately", ENQ_FORM)],
       images=imgs([
         ("hero", "1790534446928-BOXD416MEV0JDASAI8SK/unsplash-image-r1o0YEBIiEo.jpg"),
         ("card: Yacht Charter", "1790534312523-0BNVKMD7HUMX3IE0FS6Y/unsplash-image-bt-AYttMuww.jpg"),
         ("card: Private Aviation", "1790534388906-MHESF5AOQ9FLHDR34Z9J/unsplash-image-lU1pEjWZzXg.jpg"),
       ])),
  dict(slug="/exclusive-access", nav="What We Do ▸ Exclusive Access", type="Service page (member-only)", in_sitemap=True,
       title="Exclusive Access — NOYA Concierge", meta="", h1=None,
       headings=["H3 Front-row access to the world’s most sought-after events.", "H2 Attend member events", "H2 Unlock unrivalled access",
                 "H3 Paddock-club access at Formula One Grands Prix", "H3 Wimbledon Final hospitality - front row seats",
                 "H3 VIP Experience at Paris fashion week"],
       ctas=["Apply For Membership (href=/exclusive-access — self-link, should be /membership)"],
       forms=[],
       images=imgs([
         ("hero", "1781311248210-GARSNBUU6PM608CTK1DQ/Screenshot+2026-02-06+at+19.46.14.png"),
         ("card: Attend member events", "1781311248220-BAQI6DBEKBNJWXA5A1YR/Edge-42.jpg"),
         ("card: Unlock unrivalled access", "1781311248225-X27PY3QU21OS1FR9LMFQ/F1-2026-31.webp"),
         ("F1 banner", "1790534661377-8O844IW8KUW2HGQQVHJS/unsplash-image-gUtBDHvG_Pk.jpg"),
         ("F1 feature 1", "1790534585126-D4KS9REVNBBZJL6IVAU2/unsplash-image-JlY4UTcbUqw.jpg"),
         ("F1 feature 2", "1781311248237-GKU4XTTR8J2HJ5RBLLJB/31436-F1-Experiences-2018-Monaco-Paddock_Club-019-1-97068cea61a7b7b62cd1338b0f29e1da.jpg"),
         ("Wimbledon 1", "1781311248243-04EPLEO3079QX0CKG64Z/0x0.jpg.webp"),
         ("Wimbledon 2", "1781311248248-8WXNXPAW8SREH2SOAWXO/Skyview2+-+600x340.jpg"),
         ("Wimbledon 3", "1781311248255-EEUPOHLDA0P95AUXPHGD/b_celebrations_6701_12072019_tl.jpg"),
         ("Paris Fashion Week 1", "1790534994622-KCQZT1K9NB3XRA58FZGL/unsplash-image-KzXSDdRHA3g.jpg"),
         ("Paris Fashion Week 2", "1781311248264-P7XS6W1E8EPW3HSTM6KE/63e1896b69365c7816d0883a_tour-eiffel-podium-paris-fashion-week-chauffeur-driven-car-hires-dbsexperience.jpg"),
         ("Paris Fashion Week 3", "1790534934436-W05WW1QCXMUAEO9FYVVU/unsplash-image-7DUSkuGgLyM.jpg"),
       ])),
  dict(slug="/corporate-concierge", nav="Corporate Concierge", type="Service page (B2B)", in_sitemap=True,
       title="Corporate Concierge — NOYA Concierge", meta="", h1=None,
       headings=["H3 Corporate Concierge & Brand Experiences", "H2 Corporate Concierge", "H2 Private Brand Events & Corporate Experiences",
                 "H2 Brand Shoots, Production & Co-ordination", "H2 Inquire Privately"],
       ctas=["Make an Enquiry (href=/corporate-concierge — self-link)"],
       forms=[("Inquire Privately (corporate variant)", ["First Name*", "Last Name*", "Company Name*", "Email*", "Phone*",
               "Country of Residence*", "How did you hear about us?*", "Let us know how we can help you ?*"])],
       images=imgs([
         ("hero (same as Exclusive Access card)", "1781311248220-BAQI6DBEKBNJWXA5A1YR/Edge-42.jpg"),
         ("card: Corporate Concierge", "1790535245820-2169VRTR8RR20ID1QV39/unsplash-image-WuD-H9IQnfg.jpg"),
         ("card: Private Brand Events", "1781311247353-TAMA7Y4LOABRDJEWNFLB/Screenshot+2026-03-01+at+00.20.20.png"),
         ("card: Brand Shoots & Production", "1781311247359-WW3M9K6V4JYX7OEFU274/Edge-3.jpg"),
       ])),
  dict(slug="/about", nav="About us", type="About", in_sitemap=True,
       title="About us — NOYA Concierge", meta="", h1=None,
       headings=["H2 About us", "H2 Inquire Privately"], ctas=[],
       forms=[("Inquire Privately", ENQ_FORM)],
       images=imgs([
         ("feature image (two guests in NOYA robes)", "5411f6ae-e7ef-4196-9b1d-5eff01da0b7c/12.png"),
         ("sitemap-only (listed in sitemap for /about, not rendered)", "1781311243362-Z2XX7T2FZGA4AKZ9PWEV/Corporate+.jpg"),
       ])),
  dict(slug="/contact", nav="Contact", type="Contact", in_sitemap=True,
       title="Contact — NOYA Concierge",
       meta="Contact NOYA Concierge for private enquiries - bespoke travel, lifestyle services, and events. Every conversation is held in confidence.",
       h1=None, headings=["H2 Inquire Privately"], ctas=["Submit"],
       forms=[("Inquire Privately (contact variant)", ["First Name*", "Last Name*", "Email*", "Phone / WhatsApp", "Country of Residence",
               "How did you hear about us?", "Let us know how we can help you*"])],
       images=[]),
  dict(slug="/membership", nav="Become a member (header button)", type="Membership application", in_sitemap=True,
       title="Apply for Membership — NOYA Concierge", meta="", h1=None,
       headings=["H2 Membership, by application"], ctas=["Submit Application"],
       forms=[("Membership application", ["First Name*", "Last Name*", "Email*", "Phone / WhatsApp", "Country of Residence*",
               "How did you hear about us?", "What would you like NOYA to help you with?*",
               "Consent* — I have read and agree to the Privacy Policy and Terms & Conditions."])],
       images=[]),
  dict(slug="/privacy-policy", nav="Footer: Privacy Policy", type="Legal", in_sitemap=True,
       title="Privacy Policy — NOYA Concierge", meta="", h1="Privacy Policy",
       headings=["H1 Privacy Policy", "H2 What we collect", "H2 Why we use it", "H2 Who sees it", "H2 How long we keep it",
                 "H2 Your rights", "H2 Cookies", "H2 Security", "H2 Contact"],
       ctas=[], forms=[], images=[]),
  dict(slug="/terms-conditions", nav="Footer: Terms & Conditions", type="Legal", in_sitemap=True,
       title="Terms & Conditions — NOYA Concierge", meta="", h1="Terms & Conditions",
       headings=["H1 Terms & Conditions", "H2 1. Who we are", "H2 2. Our service", "H2 3. Membership", "H2 4. Enquiries and quotations",
                 "H2 5. Payment", "H2 6. Your responsibilities", "H2 7. Liability", "H2 8. Confidentiality",
                 "H2 9. Content and intellectual property", "H2 10. Changes to these terms", "H2 11. Governing law", "H2 12. Contact"],
       ctas=[], forms=[], images=[]),
  dict(slug="/cart", nav="Header '0' cart link (Squarespace commerce default)", type="System page (not crawled for content)", in_sitemap=False,
       title="(not crawled)", meta="", h1=None, headings=[], ctas=[], forms=[], images=[]),
]

# Third-party / licensing signals derived only from filenames.
RIGHTS = [
    (r"unsplash-image", "Unsplash stock (Unsplash licence — usable, not exclusive)"),
    (r"Chalet-Le-Namaste-Courchevel-Consensio", "Third-party agency imagery (Consensio / 'Chalet Le Namaste') — confirm licence; also name mismatch with 'Chalet Grenier' copy"),
    (r"F1-Experiences|F1-2026", "Likely Formula 1 / F1 Experiences imagery — confirm licence"),
    (r"dbsexperience", "Third-party image (dbsexperience) — confirm licence"),
    (r"b_celebrations|Skyview2|0x0\.jpg", "Likely third-party event/Wimbledon imagery — confirm licence"),
    (r"carbone|Tables-Girafe|hero-concierge|5971bf58", "Likely third-party (restaurant/press) imagery — confirm licence"),
    (r"Screenshot", "Screenshot upload — check source, quality and rights"),
]

def rights(url):
    for pat, note in RIGHTS:
        if re.search(pat, url):
            return note
    return "Presumed NOYA-owned / supplied — confirm"

def asset_id(url):
    m = re.search(r"/content/v1/[0-9a-f]+/([^/]+)/", url)
    return m.group(1) if m else url.rsplit("/", 2)[-2]

def filename(url):
    return urllib.parse.unquote_plus(url.rsplit("/", 1)[-1])

def main():
    os.makedirs(os.path.join(ROOT, "content"), exist_ok=True)
    os.makedirs(os.path.join(ROOT, "assets", "images"), exist_ok=True)

    manifest = {}
    for role, url in GLOBAL_ASSETS:
        manifest.setdefault(url, {"roles": [], "pages": []})
        manifest[url]["roles"].append(role); manifest[url]["pages"].append("(global)")
    for p in PAGES:
        for role, url in p["images"]:
            manifest.setdefault(url, {"roles": [], "pages": []})
            manifest[url]["roles"].append(role)
            if p["slug"] not in manifest[url]["pages"]:
                manifest[url]["pages"].append(p["slug"])

    rows = []
    for i, (url, d) in enumerate(manifest.items(), 1):
        local = f"{i:03d}__{asset_id(url)}__{filename(url)}".replace(" ", "_")
        rows.append({
            "n": i, "asset_id": asset_id(url), "original_filename": filename(url),
            "local_filename": local, "pages": " | ".join(d["pages"]), "roles": " | ".join(d["roles"]),
            "source_url": url, "rights_flag": rights(url),
            "download_status": "NOT DOWNLOADED — CDN host blocked by session network policy; run assets/download_assets.sh",
        })
    with open(os.path.join(ROOT, "assets", "images", "IMAGE_MANIFEST.csv"), "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0].keys())); w.writeheader(); w.writerows(rows)

    with open(os.path.join(ROOT, "assets", "download_assets.sh"), "w") as f:
        f.write("#!/usr/bin/env bash\n# Downloads every original legacy image at full resolution.\n"
                "# Run from noya-website/legacy-site/ on a machine that can reach images.squarespace-cdn.com.\n"
                "set -u\ncd \"$(dirname \"$0\")/images\"\nok=0; fail=0\n")
        for r in rows:
            src = r["source_url"]
            if "squarespace-cdn" in src and not src.endswith(".ico"):
                src += "?format=original"
            f.write(f"curl -fsSL -o '{r['local_filename']}' '{src}' && ok=$((ok+1)) || {{ echo 'FAILED {r['local_filename']}'; fail=$((fail+1)); }}\n")
        f.write('echo "downloaded=$ok failed=$fail"\n')
    os.chmod(os.path.join(ROOT, "assets", "download_assets.sh"), 0o755)

    out = []
    for p in PAGES:
        q = dict(p)
        q["url"] = SITE + p["slug"]
        q["images"] = [{"role": r, "url": u} for r, u in p["images"]]
        q["forms"] = [{"name": n, "fields": f} for n, f in p["forms"]]
        q["captured"] = CAPTURED
        q["source"] = "live crawl via Firecrawl (maxAge=0)"
        out.append(q)
    with open(os.path.join(ROOT, "content", "pages.json"), "w") as f:
        json.dump({"site": SITE, "captured": CAPTURED, "global_assets": [{"role": r, "url": u} for r, u in GLOBAL_ASSETS],
                   "pages": out}, f, indent=2, ensure_ascii=False)

    placements = sum(len(p["images"]) for p in PAGES)
    names = {filename(u) for u in manifest}
    print(f"pages={len(PAGES)} image_placements={placements} unique_image_urls={len(manifest)} "
          f"unique_filenames={len(names)} content_images={len(manifest)-len(GLOBAL_ASSETS)}")
    from collections import Counter
    print(Counter(r["rights_flag"].split(' (')[0].split(' —')[0] for r in rows))

if __name__ == "__main__":
    main()
