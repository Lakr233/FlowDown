import Image from "next/image";
import Link from "next/link";
import { FadeIn, StaggerContainer, StaggerItem } from "@/components/animations";

function TeamCard({
  quote,
  name,
  role,
  imageSrc,
  github,
  twitter,
}: {
  quote: string;
  name: string;
  role: string;
  imageSrc: string;
  github: string;
  twitter: string;
}) {
  return (
    <div className="bg-white border border-[#e6e6e6] rounded-xl p-6 flex flex-col justify-between min-h-[220px] h-full">
      <p className="text-lg font-medium text-black leading-relaxed">{quote}</p>
      <div className="flex items-center gap-3 mt-4">
        <div className="w-[48px] h-[48px] relative rounded-full overflow-hidden shrink-0 border border-[#e6e6e6]">
          <Image src={imageSrc} alt={name} fill className="object-cover" />
        </div>
        <div className="flex flex-col">
          <p className="text-sm font-bold text-black">{name}</p>
          <p className="text-sm font-medium text-[#828282]">{role}</p>
        </div>
        <div className="flex gap-2 ml-auto items-center">
          {/* GitHub */}
          <Link
            href={github}
            target="_blank"
            className="text-[#aeaeae] hover:text-[#242424] transition-colors"
          >
            <svg className="w-5 h-5" fill="currentColor" viewBox="0 0 24 24">
              <path d="M12 0c-6.626 0-12 5.373-12 12 0 5.302 3.438 9.8 8.207 11.387.599.111.793-.261.793-.577v-2.234c-3.338.726-4.033-1.416-4.033-1.416-.546-1.387-1.333-1.756-1.333-1.756-1.089-.745.083-.729.083-.729 1.205.084 1.839 1.237 1.839 1.237 1.07 1.834 2.807 1.304 3.492.997.107-.775.418-1.305.762-1.604-2.665-.305-5.467-1.334-5.467-5.931 0-1.311.469-2.381 1.236-3.221-.124-.303-.535-1.524.117-3.176 0 0 1.008-.322 3.301 1.23.957-.266 1.983-.399 3.003-.404 1.02.005 2.047.138 3.006.404 2.291-1.552 3.297-1.23 3.297-1.23.653 1.653.242 2.874.118 3.176.77.84 1.235 1.911 1.235 3.221 0 4.609-2.807 5.624-5.479 5.921.43.372.823 1.102.823 2.222v3.293c0 .319.192.694.801.576 4.765-1.589 8.199-6.086 8.199-11.386 0-6.627-5.373-12-12-12z" />
            </svg>
          </Link>
          {/* Twitter/X */}
          <Link
            href={twitter}
            target="_blank"
            className="text-[#aeaeae] hover:text-[#242424] transition-colors"
          >
            <svg className="w-4 h-4" fill="currentColor" viewBox="0 0 24 24">
              <path d="M18.244 2.25h3.308l-7.227 8.26 8.502 11.24H16.17l-5.214-6.817L4.99 21.75H1.68l7.73-8.835L1.254 2.25H8.08l4.713 6.231zm-1.161 17.52h1.833L7.084 4.126H5.117z" />
            </svg>
          </Link>
        </div>
      </div>
    </div>
  );
}

export default function TeamSection() {
  return (
    <section className="px-6 mt-[120px] max-w-[1280px] mx-auto">
      <FadeIn>
        <div className="mb-10">
          <h2 className="font-['Instrument_Serif'] text-[42px] text-[#242424] tracking-[-0.84px]">
            MEET THE TEAM
          </h2>
          <p className="text-lg text-[#828282] mt-2">
            The talented people behind FlowDown
          </p>
        </div>
      </FadeIn>

      {/* Team cards row 1 */}
      <StaggerContainer className="grid grid-cols-1 md:grid-cols-3 gap-6 mb-6">
        <StaggerItem>
          <TeamCard
            quote="We build with passion and love."
            name="@Lakr233"
            role="Project Leader"
            imageSrc="/team/lakr.png"
            github="https://github.com/Lakr233"
            twitter="https://twitter.com/Lakr233"
          />
        </StaggerItem>
        <StaggerItem>
          <TeamCard
            quote="Core developer of FlowDown, shipping cutting-edge features."
            name="@ktiays"
            role="Developer"
            imageSrc="/team/ktiays.jpg"
            github="https://github.com/ktiays"
            twitter="https://twitter.com/ktiays"
          />
        </StaggerItem>
        <StaggerItem>
          <TeamCard
            quote="Core developer of FlowDown Text Rendering Engine."
            name="@unixzii"
            role="Developer"
            imageSrc="/team/unixzii.jpg"
            github="https://github.com/unixzii"
            twitter="https://twitter.com/unixzii"
          />
        </StaggerItem>
      </StaggerContainer>

      {/* Team cards row 2 */}
      <StaggerContainer
        className="grid grid-cols-1 md:grid-cols-3 gap-6"
        delay={0.2}
      >
        <StaggerItem>
          <TeamCard
            quote="Build our beautiful websites."
            name="@innei"
            role="Frontend Developer"
            imageSrc="/team/innei.jpg"
            github="https://github.com/innei"
            twitter="https://twitter.com/__oQuery"
          />
        </StaggerItem>
        <StaggerItem>
          <TeamCard
            quote="Design the beautiful icons for FlowDown."
            name="@hwwaanng"
            role="Icon Designer"
            imageSrc="/team/hwwaanng.png"
            github="https://github.com/hwangdev97"
            twitter="https://twitter.com/hwwaanng"
          />
        </StaggerItem>
        <StaggerItem>
          <TeamCard
            quote="Architecting state-of-the-art solutions, driven by passion."
            name="@at-wr"
            role="Developer"
            imageSrc="/team/at-wr.png"
            github="https://github.com/at-wr"
            twitter="https://twitter.com/Wr_Offi"
          />
        </StaggerItem>
      </StaggerContainer>
    </section>
  );
}
