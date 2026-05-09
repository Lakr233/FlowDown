import {
  Navigation,
  HeroSection,
  FeaturesSection,
  FAQSection,
  AgentResourcesSection,
  TestimonialsSection,
  TeamSection,
  Footer,
} from "@/components/sections";

export default function LandingPage() {
  return (
    <div className="bg-[#f6f6f6] relative min-h-screen overflow-x-hidden">
      <Navigation />
      <HeroSection />
      <FeaturesSection />
      <FAQSection />
      <AgentResourcesSection />
      <TestimonialsSection />
      <TeamSection />
      <Footer />
    </div>
  );
}
