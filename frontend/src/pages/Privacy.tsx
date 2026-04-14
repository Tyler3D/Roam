export default function Privacy() {
  return (
    <div className="min-h-screen bg-roam-bg px-6 py-12">
      <div className="max-w-[680px] mx-auto">
        <div className="anim mb-10">
          <img
            src="/icon.png"
            alt="Roam"
            className="w-16 h-16 rounded-[18px] shadow-btn mx-auto mb-4"
          />
          <h1 className="font-display italic text-4xl text-roam-text leading-none mb-2 text-center">Roam</h1>
          <p className="font-mono text-[10px] text-roam-text-muted tracking-[1.5px] uppercase text-center">Privacy Policy</p>
        </div>

        <p className="anim d1 font-mono text-[11px] text-roam-text-muted tracking-[0.5px] mb-10">
          Last updated: April 13, 2026
        </p>

        <div className="anim d2 space-y-10">
          <section>
            <h2 className="font-mono text-[11px] text-roam-text-muted tracking-[1.5px] uppercase mb-3">Overview</h2>
            <p className="font-mono text-[13px] text-roam-text leading-relaxed">
              Roam ("we," "our," or "us") operates the Roam mobile application and related
              services (collectively, the "Service"). This Privacy Policy explains what information
              we collect, how we use it, and your rights with respect to that information. By using
              the Service, you agree to the collection and use of information in accordance with
              this policy. We collect only what is necessary to provide core functionality. We do
              not sell your personal data or use it for advertising purposes.
            </p>
          </section>

          <section>
            <h2 className="font-mono text-[11px] text-roam-text-muted tracking-[1.5px] uppercase mb-3">Information We Collect</h2>
            <div className="space-y-4">
              <div className="bg-roam-surface border border-roam-logan/20 rounded-[13px] p-4">
                <p className="font-mono text-[12px] text-roam-text mb-1">Account Information</p>
                <p className="font-mono text-[12px] text-roam-text-muted leading-relaxed">
                  When you create an account, we collect your email address and display name.
                  If you sign in using Google Sign-In or Sign in with Apple, we receive the name
                  and email address associated with that account, as permitted by your authorization.
                </p>
              </div>
              <div className="bg-roam-surface border border-roam-logan/20 rounded-[13px] p-4">
                <p className="font-mono text-[12px] text-roam-text mb-1">Reel URLs and Content</p>
                <p className="font-mono text-[12px] text-roam-text-muted leading-relaxed">
                  When you share a reel into Roam, we process the URL and associated metadata
                  including titles, captions, thumbnails, and video frames. This content is used
                  to extract places mentioned in the reel and is linked to your account.
                </p>
              </div>
              <div className="bg-roam-surface border border-roam-logan/20 rounded-[13px] p-4">
                <p className="font-mono text-[12px] text-roam-text mb-1">Location</p>
                <p className="font-mono text-[12px] text-roam-text-muted leading-relaxed">
                  With your permission, we access your device's precise location to display your
                  position on the map. Location data is used on-device for this display purpose
                  and is not stored on our servers. You may revoke location permission at any time
                  through your device settings.
                </p>
              </div>
              <div className="bg-roam-surface border border-roam-logan/20 rounded-[13px] p-4">
                <p className="font-mono text-[12px] text-roam-text mb-1">Device Identifiers</p>
                <p className="font-mono text-[12px] text-roam-text-muted leading-relaxed">
                  We collect a push notification token issued by Apple to deliver notifications
                  about your collections and shared maps. This token is associated with your
                  account and is used solely to deliver notifications you have enabled.
                </p>
              </div>
            </div>
          </section>

          <section>
            <h2 className="font-mono text-[11px] text-roam-text-muted tracking-[1.5px] uppercase mb-3">How We Use Your Information</h2>
            <p className="font-mono text-[13px] text-roam-text leading-relaxed mb-4">
              We use the information we collect for the following purposes:
            </p>
            <ul className="space-y-2">
              {[
                "To create and manage your account",
                "To process reels and extract places using our AI pipeline",
                "To display your saved ideas and maps within the Service",
                "To enable shared collections and collaboration with other users",
                "To send push notifications that you have opted into",
                "To improve the accuracy of our place extraction pipeline",
              ].map((item) => (
                <li key={item} className="font-mono text-[13px] text-roam-text flex gap-3">
                  <span className="text-roam-text-muted shrink-0">*</span>
                  <span>{item}</span>
                </li>
              ))}
            </ul>
          </section>

          <section>
            <h2 className="font-mono text-[11px] text-roam-text-muted tracking-[1.5px] uppercase mb-3">Third-Party Services</h2>
            <p className="font-mono text-[13px] text-roam-text leading-relaxed mb-4">
              Roam uses the following third-party services to provide the Service. Each third party
              has its own privacy practices governing the data it receives:
            </p>
            <div className="space-y-3">
              {[
                {
                  name: "Firebase (Google)",
                  use: "Authentication, push notifications, and backend infrastructure.",
                },
                {
                  name: "Google Maps and Places",
                  use: "Map display and place search and resolution.",
                },
                {
                  name: "Google Sign-In",
                  use: "Optional sign-in with your Google account.",
                },
                {
                  name: "Google Gemini",
                  use: "AI analysis of reel content to identify and extract places.",
                },
              ].map((s) => (
                <div key={s.name} className="bg-roam-surface border border-roam-logan/20 rounded-[13px] p-4">
                  <p className="font-mono text-[12px] text-roam-text mb-1">{s.name}</p>
                  <p className="font-mono text-[12px] text-roam-text-muted leading-relaxed">{s.use}</p>
                </div>
              ))}
            </div>
            <p className="font-mono text-[12px] text-roam-text-muted leading-relaxed mt-4">
              We encourage you to review the privacy policies of these third parties. We are not
              responsible for the privacy practices of third-party services.
            </p>
          </section>

          <section>
            <h2 className="font-mono text-[11px] text-roam-text-muted tracking-[1.5px] uppercase mb-3">Data Sharing</h2>
            <p className="font-mono text-[13px] text-roam-text leading-relaxed">
              We do not sell your personal data. We do not share your personal data with advertisers
              or data brokers. Your saved ideas are private by default and are only visible to other
              users when you explicitly share them via a collection. We may disclose your information
              if required to do so by law or in response to valid legal process.
            </p>
          </section>

          <section>
            <h2 className="font-mono text-[11px] text-roam-text-muted tracking-[1.5px] uppercase mb-3">Data Retention</h2>
            <p className="font-mono text-[13px] text-roam-text leading-relaxed">
              We retain your personal data for as long as your account remains active. Upon account
              deletion, your personal data is deleted within 30 days. Anonymized, non-identifiable
              place data may be retained to improve the accuracy of the place extraction pipeline.
            </p>
          </section>

          <section>
            <h2 className="font-mono text-[11px] text-roam-text-muted tracking-[1.5px] uppercase mb-3">Your Rights</h2>
            <p className="font-mono text-[13px] text-roam-text leading-relaxed mb-3">
              You have the right to access, correct, or delete your personal data at any time.
              To delete your account and associated data, navigate to Account Settings within
              the app. For all other requests regarding your personal data, please contact us
              using the information below.
            </p>
            <p className="font-mono text-[13px] text-roam-text leading-relaxed">
              If you are located in the European Economic Area or California, you may have
              additional rights under applicable data protection law, including the right to
              data portability and the right to lodge a complaint with a supervisory authority.
            </p>
          </section>

          <section>
            <h2 className="font-mono text-[11px] text-roam-text-muted tracking-[1.5px] uppercase mb-3">Children's Privacy</h2>
            <p className="font-mono text-[13px] text-roam-text leading-relaxed">
              The Service is not directed to individuals under the age of 13. We do not knowingly
              collect personal data from children under 13. If we become aware that we have
              collected personal data from a child under 13 without parental consent, we will
              take steps to delete that information promptly.
            </p>
          </section>

          <section>
            <h2 className="font-mono text-[11px] text-roam-text-muted tracking-[1.5px] uppercase mb-3">Changes to This Policy</h2>
            <p className="font-mono text-[13px] text-roam-text leading-relaxed">
              We may update this Privacy Policy from time to time. We will notify you of any
              material changes by posting the new policy on this page and updating the "Last
              updated" date. Your continued use of the Service after any changes constitutes
              your acceptance of the revised policy.
            </p>
          </section>

          <section>
            <h2 className="font-mono text-[11px] text-roam-text-muted tracking-[1.5px] uppercase mb-3">Contact</h2>
            <p className="font-mono text-[13px] text-roam-text leading-relaxed">
              If you have any questions or requests regarding this Privacy Policy, please contact
              us at{" "}
              <a
                href="mailto:tyler.manrique32@gmail.com"
                className="text-roam-text underline underline-offset-2"
              >
                tyler.manrique32@gmail.com
              </a>
            </p>
          </section>
        </div>

        <div className="mt-16 pt-8 border-t border-roam-logan/20">
          <p className="font-mono text-[11px] text-roam-text-muted tracking-[0.5px]">
            &copy; 2026 Roam. All rights reserved.
          </p>
        </div>
      </div>
    </div>
  );
}
