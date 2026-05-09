import Link from "next/link";
import Navigation from "@/components/sections/Navigation";
import Footer from "@/components/sections/Footer";

export interface ResourceLink {
  label: string;
  href: string;
  description: string;
}

export interface ResourceSection {
  title: string;
  body?: string;
  items?: string[];
  links?: ResourceLink[];
}

interface ResourcePageProps {
  eyebrow: string;
  title: string;
  description: string;
  sections: ResourceSection[];
}

export default function ResourcePage({
  eyebrow,
  title,
  description,
  sections,
}: ResourcePageProps) {
  return (
    <div className="bg-[#f6f6f6] min-h-screen text-[#242424]">
      <Navigation />
      <main className="pt-[132px] px-6 max-w-[1120px] mx-auto">
        <p className="text-sm font-semibold uppercase tracking-[0.12em] text-[#6f6f6f] mb-4">
          {eyebrow}
        </p>
        <h1 className="font-['Instrument_Serif'] text-[52px] leading-tight mb-5">
          {title}
        </h1>
        <p className="text-lg leading-8 text-[#555] max-w-[780px]">
          {description}
        </p>

        <div className="grid gap-6 mt-12">
          {sections.map((section) => (
            <section
              key={section.title}
              className="border border-[#dedede] bg-white rounded-[8px] p-6"
            >
              <h2 className="font-['Instrument_Serif'] text-[34px] leading-tight mb-4">
                {section.title}
              </h2>
              {section.body && (
                <p className="text-base leading-7 text-[#555] mb-4">
                  {section.body}
                </p>
              )}
              {section.items && (
                <ul className="list-disc ml-5 space-y-2 text-[#4a4a4a] leading-7">
                  {section.items.map((item) => (
                    <li key={item}>{item}</li>
                  ))}
                </ul>
              )}
              {section.links && (
                <div className="grid gap-3 mt-4 md:grid-cols-2">
                  {section.links.map((link) => (
                    <Link
                      key={link.href}
                      href={link.href}
                      className="block border border-[#e2e2e2] rounded-[8px] p-4 hover:border-[#bfbfbf] transition-colors"
                    >
                      <span className="font-semibold text-[#242424]">
                        {link.label}
                      </span>
                      <span className="block text-sm leading-6 text-[#666] mt-1">
                        {link.description}
                      </span>
                    </Link>
                  ))}
                </div>
              )}
            </section>
          ))}
        </div>
      </main>
      <Footer />
    </div>
  );
}
