import type { Metadata, Viewport } from "next";
import { Inter, Instrument_Serif } from "next/font/google";
import "./globals.css";

const inter = Inter({
  subsets: ["latin"],
  variable: "--font-inter",
  display: "swap",
});

const instrumentSerif = Instrument_Serif({
  weight: "400",
  subsets: ["latin"],
  variable: "--font-instrument-serif",
  display: "swap",
  style: ["normal", "italic"],
});

export const metadata: Metadata = {
  metadataBase: new URL("https://flowdown.ai"),
  title: "FlowDown - AI That Works Even Without Us",
  description:
    "You can OWN a blazing fast and smooth Agent app. Switch between your AI services or use local models on your device.",
  alternates: {
    canonical: "/",
  },
  keywords: [
    "AI",
    "Chat",
    "iOS",
    "macOS",
    "Privacy",
    "LLM",
    "MLX",
    "OpenAI",
    "Claude",
    "Local AI",
    "FlowDown",
    "Agent",
    "Swift",
    "Apple Silicon",
  ],
  authors: [{ name: "FlowDown Team" }],
  icons: {
    icon: "/favicon.png",
    shortcut: "/favicon.png",
    apple: "/favicon.png",
  },
  openGraph: {
    title: "FlowDown - AI That Works Even Without Us",
    description:
      "You can OWN a blazing fast and smooth Agent app. Switch between your AI services or use local models on your device.",
    type: "website",
    locale: "en_US",
    images: [
      {
        url: "/og-Image.png",
        width: 1200,
        height: 630,
        alt: "FlowDown - AI That Works Even Without Us",
      },
    ],
  },
  twitter: {
    card: "summary_large_image",
    title: "FlowDown - AI That Works Even Without Us",
    description:
      "You can OWN a blazing fast and smooth Agent app. Switch between your AI services or use local models on your device.",
    images: ["/og-Image.png"],
  },
  robots: {
    index: true,
    follow: true,
  },
};

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  themeColor: "#f6f6f6",
};

const structuredData = [
  {
    "@context": "https://schema.org",
    "@type": "Organization",
    "@id": "https://flowdown.ai/#organization",
    name: "FlowDown AI",
    url: "https://flowdown.ai",
    logo: "https://flowdown.ai/icon-primary.png",
    email: "flowdownapp@qaq.wiki",
    contactPoint: [
      {
        "@type": "ContactPoint",
        email: "flowdownapp@qaq.wiki",
        contactType: "customer support",
        availableLanguage: ["en"],
        areaServed: "Worldwide",
      },
    ],
    address: {
      "@type": "PostalAddress",
      name: "Distributed open-source project",
    },
    sameAs: [
      "https://github.com/Lakr233/FlowDown",
      "https://apps.apple.com/us/app/flowdown-open-fast-ai/id6740553198",
      "https://discord.gg/UHKMRyJcgc",
    ],
  },
  {
    "@context": "https://schema.org",
    "@type": "SoftwareApplication",
    "@id": "https://flowdown.ai/#software",
    name: "FlowDown AI",
    alternateName: "FlowDown",
    applicationCategory: "ProductivityApplication",
    operatingSystem: "iOS, iPadOS, macOS",
    url: "https://flowdown.ai",
    downloadUrl:
      "https://apps.apple.com/us/app/flowdown-open-fast-ai/id6740553198",
    codeRepository: "https://github.com/Lakr233/FlowDown",
    license: "https://github.com/Lakr233/FlowDown/blob/main/LICENSE",
    offers: {
      "@type": "Offer",
      price: "0",
      priceCurrency: "USD",
      availability: "https://schema.org/InStock",
      url: "https://flowdown.ai/pricing",
      validFrom: "2026-06-10",
    },
    featureList: [
      "Native iOS, iPadOS, and macOS AI workspace",
      "OpenAI-compatible cloud model configuration",
      "Local MLX and Apple Intelligence workflows",
      "MCP client support",
      "Apple Shortcuts automation",
      "Local-first storage with optional iCloud sync",
    ],
    sameAs: [
      "https://github.com/Lakr233/FlowDown",
      "https://apps.apple.com/us/app/flowdown-open-fast-ai/id6740553198",
    ],
  },
  {
    "@context": "https://schema.org",
    "@type": "WebSite",
    "@id": "https://flowdown.ai/#website",
    name: "FlowDown AI",
    url: "https://flowdown.ai",
    description:
      "FlowDown AI is a privacy-first native AI workspace for iOS, iPadOS, and macOS with local models, OpenAI-compatible providers, MCP client support, and Shortcuts automation.",
    publisher: {
      "@id": "https://flowdown.ai/#organization",
    },
    speakable: {
      "@type": "SpeakableSpecification",
      cssSelector: ["h1", "#features h2", "#faq h2"],
    },
  },
  {
    "@context": "https://schema.org",
    "@type": "FAQPage",
    mainEntity: [
      {
        "@type": "Question",
        name: "What is FlowDown AI?",
        acceptedAnswer: {
          "@type": "Answer",
          text: "FlowDown AI is a native AI workspace for iPhone, iPad, and Mac with OpenAI-compatible providers, local model support, MCP client integration, web search, attachments, memory, and Shortcuts automation.",
        },
      },
      {
        "@type": "Question",
        name: "Is FlowDown AI free?",
        acceptedAnswer: {
          "@type": "Answer",
          text: "FlowDown AI has a scheduled pricing step-down. The base app reaches a zero-dollar US storefront price on June 10, 2026. Regional App Store pricing remains the final purchase source.",
        },
      },
      {
        "@type": "Question",
        name: "How do users configure a custom API key?",
        acceptedAnswer: {
          "@type": "Answer",
          text: "Users add an OpenAI-compatible model profile inside FlowDown, enter the provider endpoint, token, optional headers, and additional request body fields, then verify the model configuration.",
        },
      },
    ],
  },
];

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html
      lang="en"
      suppressHydrationWarning
      className={`${inter.variable} ${instrumentSerif.variable}`}
    >
      <body className="min-h-screen antialiased">
        <script
          type="application/ld+json"
          dangerouslySetInnerHTML={{ __html: JSON.stringify(structuredData) }}
        />
        {children}
      </body>
    </html>
  );
}
