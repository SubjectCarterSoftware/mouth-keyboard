import Foundation

/// Whether a pack groups corrections by job role or by industry. Only role packs
/// ship today; the `industry` case keeps the catalog open for later additions
/// without a structural change.
enum ReplacementPackKind: String, Codable, Sendable {
    case role
    case industry
}

/// A curated bundle of word replacements that fixes the jargon, tool names, and
/// brand names a given role tends to dictate. Catalog rules carry no stable UUID —
/// fresh IDs are minted when the pack is copied into a user's dictionary.
struct ReplacementPack: Identifiable, Sendable {
    let id: String
    let title: String
    let kind: ReplacementPackKind
    let symbolName: String
    let subtitle: String
    let replacements: [WordReplacement]
}

enum ReplacementPackCatalog {
    static let all: [ReplacementPack] = [
        softwareDeveloper,
        designer,
        productManager,
        dataScientist,
        marketer
    ]

    static var roles: [ReplacementPack] {
        all.filter { $0.kind == .role }
    }

    static func pack(id: String) -> ReplacementPack? {
        all.first { $0.id == id }
    }

    // MARK: - Role packs

    private static let softwareDeveloper = ReplacementPack(
        id: "role.software-developer",
        title: "Software Developer",
        kind: .role,
        symbolName: "chevron.left.forwardslash.chevron.right",
        subtitle: "Languages, frameworks, and dev tools",
        replacements: [
            r(["type script"], "TypeScript"),
            r(["java script"], "JavaScript"),
            r(["node js", "node.js"], "Node.js"),
            r(["next js", "next.js"], "Next.js"),
            r(["nuxt"], "Nuxt"),
            r(["svelte", "svelt", "svelte kit"], "Svelte"),
            r(["vercel", "versel"], "Vercel"),
            r(["net lify"], "Netlify"),
            r(["post gres", "postgres", "post gres ql"], "Postgres"),
            r(["my sql"], "MySQL"),
            r(["no sql"], "NoSQL"),
            r(["mongo db"], "MongoDB"),
            r(["redis", "red is"], "Redis"),
            r(["kubernetes", "kubernetis", "cooper netes"], "Kubernetes"),
            r(["docker"], "Docker"),
            r(["nginx", "engine x"], "nginx"),
            r(["graph ql"], "GraphQL"),
            r(["o auth", "oauth"], "OAuth"),
            r(["json"], "JSON"),
            r(["yaml"], "YAML"),
            r(["tail wind"], "Tailwind"),
            r(["web pack"], "webpack"),
            r(["es lint"], "ESLint"),
            r(["git hub"], "GitHub"),
            r(["git lab"], "GitLab"),
            r(["x code"], "Xcode"),
            r(["swift ui"], "SwiftUI"),
            r(["cocoa pods"], "CocoaPods"),
            r(["c sharp"], "C#"),
            r(["c plus plus"], "C++"),
            r(["dot net"], ".NET"),
            r(["localhost", "local host"], "localhost"),
            r(["reg ex", "regex"], "regex")
        ]
    )

    private static let designer = ReplacementPack(
        id: "role.designer",
        title: "Designer",
        kind: .role,
        symbolName: "paintbrush.pointed",
        subtitle: "Design tools and visual terms",
        replacements: [
            r(["fig ma", "figma"], "Figma"),
            r(["web flow"], "Webflow"),
            r(["framer"], "Framer"),
            r(["in design"], "InDesign"),
            r(["photo shop"], "Photoshop"),
            r(["light room"], "Lightroom"),
            r(["after effects"], "After Effects"),
            r(["auto layout"], "Auto Layout"),
            r(["lottie"], "Lottie"),
            r(["mid journey"], "Midjourney"),
            r(["cmyk"], "CMYK"),
            r(["rgba"], "RGBA"),
            r(["svg"], "SVG"),
            r(["ui"], "UI"),
            r(["ux"], "UX")
        ]
    )

    private static let productManager = ReplacementPack(
        id: "role.product-manager",
        title: "Product Manager",
        kind: .role,
        symbolName: "list.bullet.clipboard",
        subtitle: "Planning tools and product metrics",
        replacements: [
            r(["jira", "jura"], "Jira"),
            r(["confluence"], "Confluence"),
            r(["notion"], "Notion"),
            r(["road map"], "roadmap"),
            r(["kpi"], "KPI"),
            r(["kpis"], "KPIs"),
            r(["okr"], "OKR"),
            r(["okrs"], "OKRs"),
            r(["mvp"], "MVP"),
            r(["b2b"], "B2B"),
            r(["b2c"], "B2C"),
            r(["mix panel"], "Mixpanel"),
            r(["amplitude"], "Amplitude"),
            // Shared with the Designer pack — kept until both packs are disabled.
            r(["fig ma", "figma"], "Figma")
        ]
    )

    private static let dataScientist = ReplacementPack(
        id: "role.data-scientist",
        title: "Data Scientist / ML",
        kind: .role,
        symbolName: "chart.xyaxis.line",
        subtitle: "ML libraries and data tools",
        replacements: [
            r(["pie torch", "pi torch"], "PyTorch"),
            r(["tensor flow"], "TensorFlow"),
            r(["num py", "numb pie"], "NumPy"),
            r(["sci kit learn", "scikit learn"], "scikit-learn"),
            r(["mat plot lib"], "Matplotlib"),
            r(["cuda", "cooda"], "CUDA"),
            r(["hugging face"], "Hugging Face"),
            r(["data frame"], "DataFrame"),
            r(["big query"], "BigQuery"),
            r(["data set"], "dataset"),
            r(["llm"], "LLM"),
            r(["llms"], "LLMs"),
            r(["gpt"], "GPT")
        ]
    )

    private static let marketer = ReplacementPack(
        id: "role.marketer",
        title: "Marketer",
        kind: .role,
        symbolName: "megaphone",
        subtitle: "Channels, platforms, and acronyms",
        replacements: [
            r(["seo"], "SEO"),
            r(["sem"], "SEM"),
            r(["ctr"], "CTR"),
            r(["cta"], "CTA"),
            r(["crm"], "CRM"),
            r(["roas"], "ROAS"),
            r(["utm"], "UTM"),
            r(["hub spot"], "HubSpot"),
            r(["sales force"], "Salesforce"),
            r(["mail chimp"], "Mailchimp"),
            r(["google analytics"], "Google Analytics"),
            r(["click through"], "click-through")
        ]
    )

    // MARK: - Helpers

    private static func r(_ originals: [String], _ replacement: String) -> WordReplacement {
        WordReplacement(originals: originals, replacement: replacement)
    }
}
