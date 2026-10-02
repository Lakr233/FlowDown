import { FadeIn, StaggerContainer, StaggerItem } from "@/components/animations";

function StarRating() {
  return (
    <div className="flex gap-0.5">
      {[...Array(5)].map((_, i) => (
        <svg key={i} className="w-4 h-4" viewBox="0 0 24 24" fill="#FFB800">
          <path d="M12 2l3.09 6.26L22 9.27l-5 4.87 1.18 6.88L12 17.77l-6.18 3.25L7 14.14 2 9.27l6.91-1.01L12 2z" />
        </svg>
      ))}
    </div>
  );
}

function Testimonial({
  text,
  author,
  source,
}: {
  text: string;
  author: string;
  source: string;
}) {
  return (
    <div className="flex gap-4">
      <div className="w-0.5 h-12 bg-[#1c1c1c] flex-shrink-0" />
      <div className="flex flex-col gap-2">
        <p className="text-xs leading-5 text-[#1c1c1c] max-w-[480px]">{text}</p>
        <StarRating />
        <p className="text-xs text-[#1c1c1c]">
          {author} <span className="text-[#b3b3b3]">from {source}</span>
        </p>
      </div>
    </div>
  );
}

export default function TestimonialsSection() {
  return (
    <section className="px-6 mt-[80px] md:mt-[120px] max-w-[1280px] mx-auto">
      <FadeIn>
        <h2 className="font-['Instrument_Serif'] text-[32px] md:text-[42px] text-[#242424] tracking-[-0.84px] mb-6 md:mb-10">
          LOVE FROM OUR USERS
        </h2>
      </FadeIn>

      <div className="flex flex-col md:flex-row md:justify-between gap-8 md:gap-12">
        {/* Left column */}
        <StaggerContainer className="flex flex-col gap-6 md:gap-8 flex-1">
          <StaggerItem>
            <Testimonial
              text="The performance of FlowDown is amazing! I was truly impressed by the rendering performance, even during the beta testing stage - it's significantly better than the native official ChatGPT app. I also hold a similar attitude with the developer (or project leader), toward the concept of native app & privacy. As someone who has been using this app since literally day one, I can really see the effort the team has put into it. The project leader is active in the Discord group, constantly working to fix bugs and add new features.

That said, there are still a few frustrating issues. I have to admit that the process to add a model from external service provider is way too complicated. I understand this is partly due to Apple's restrictions, but I really hope a more streamlined solution can be found. Also, the macOS app is not 'that' native. While the performance is solid, the user interface doesn't fully align with the desktop experience-especially the right-click menu and the settings page, which feel out of place."
              author="ChrisLloy"
              source="App Store"
            />
          </StaggerItem>
          <StaggerItem>
            <Testimonial
              text="FlowDown really is the most fluent LLM client I've ever used. The smoothness of the app experience cannot be matched by any other app. Developer's support response is remarkably fast compared to others on Discord. Overall, I do think it has great potential for more additional features in future updates. Truly having a great time with it."
              author="Veg-Soup"
              source="App Store"
            />
          </StaggerItem>
        </StaggerContainer>

        {/* Right column */}
        <StaggerContainer
          className="flex flex-col gap-6 md:gap-8 flex-1"
          delay={0.2}
        >
          <StaggerItem>
            <Testimonial
              text="Super easy to use It's really cool that the shortcut command can directly get the content of the reply, and you can do a lot of things. And it supports custom API, and basically can access all models, which is simply invincible."
              author="ねこにゃう"
              source="App Store (Translated)"
            />
          </StaggerItem>
          <StaggerItem>
            <Testimonial
              text="The best app on the market for using LLMs with multiple inference providers."
              author="wowlocal"
              source="App Store"
            />
          </StaggerItem>
          <StaggerItem>
            <Testimonial
              text="I am seeking for such app support mobile platform + web search + multiple providers + ChatGPT liked UI/UX (Concise + Native) for such a long time. Saw it on Twitter and bought it immediately. That’s exactly what I eager for. I am now being able to use it to alternate all kinds of Chat Apps on my iPhone since it provides all great features. Thanks"
              author="Danielzmeow"
              source="App Store"
            />
          </StaggerItem>
        </StaggerContainer>
      </div>
    </section>
  );
}
