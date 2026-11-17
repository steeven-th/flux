import Foundation

/// Removes the query parameters that only tell a site or an ad network where a click came from.
enum CleanLink {
    private static let prefixes = ["utm_", "hsa_", "pk_", "mtm_", "__hs", "_hs"]

    private static let names: Set<String> = [
        // Ads and social networks
        "fbclid", "gclid", "gclsrc", "dclid", "gbraid", "wbraid", "msclkid", "yclid", "twclid",
        "ttclid", "li_fat_id", "igshid", "igsh", "epik", "rdt_cid", "scclid",
        // Mailing tools and marketing suites
        "mc_cid", "mc_eid", "mkt_tok", "_kx", "vero_id", "vero_conv", "oly_anon_id", "oly_enc_id",
        "ml_subscriber", "ml_subscriber_hash", "rb_clickid", "s_cid", "wickedid", "trk_contact",
        // Analytics
        "_ga", "_gl", "_openstat", "ga_source", "ga_medium", "ga_campaign", "ga_content", "ga_term",
    ]

    /// Parameters that track only on these sites, and may mean something elsewhere.
    private static let namesBySite: [String: Set<String>] = [
        "youtube.com": ["si", "pp", "feature"],
        "youtu.be": ["si", "feature"],
        "spotify.com": ["si"],
        "x.com": ["s", "t"],
        "twitter.com": ["s", "t", "ref_src", "ref_url"],
        "instagram.com": ["igshid", "igsh"],
        "amazon.com": ["ref", "ref_", "pd_rd_w", "pd_rd_r", "pd_rd_wg", "pf_rd_r", "pf_rd_p", "content-id"],
    ]

    static func cleaned(_ address: String) -> String {
        guard var components = URLComponents(string: address),
              let items = components.percentEncodedQueryItems, !items.isEmpty else { return address }
        let host = components.host?.lowercased() ?? ""
        let siteNames = namesBySite.first { site, _ in
            host == site || host.hasSuffix("." + site) || isAmazon(host, site)
        }?.value ?? []
        let kept = items.filter { item in
            let name = item.name.lowercased()
            return !names.contains(name) && !siteNames.contains(name)
                && !prefixes.contains { name.hasPrefix($0) }
        }
        guard kept.count != items.count else { return address }
        components.percentEncodedQueryItems = kept.isEmpty ? nil : kept
        return components.string ?? address
    }

    /// Amazon has a site per country: amazon.fr, amazon.co.uk...
    private static func isAmazon(_ host: String, _ site: String) -> Bool {
        site == "amazon.com" && (host.hasPrefix("amazon.") || host.contains(".amazon."))
    }
}
