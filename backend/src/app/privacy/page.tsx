export default function Privacy() {
  return <main>
    <p className="eyebrow">CAVE CALS</p>
    <h1>Privacy Policy</h1>
    <p><strong>Effective date: September 9, 2026</strong></p>
    <p>Claim727 LLC ("Claim727," "we," "us," or "our") operates Cave Cals, a food and calorie tracking app. This policy explains what information Cave Cals processes, why we process it, when it is shared, and the choices available to you.</p>
    <h2>Information stored on your devices and iCloud</h2>
    <p>Your profile, calorie goals, food diary, saved foods, saved meals, and widget data are stored on your device and, when iCloud is enabled, in your private iCloud account using Apple CloudKit. We do not receive your iCloud credentials or control Apple's storage and security practices.</p>
    <h2>Information sent to our services</h2>
    <p>When you search for a food or scan a barcode, your search term or barcode is sent to Open Food Facts to return product information. When you choose AI meal photo or voice logging, the selected photo, video, or audio recording is uploaded to our backend and sent to OpenAI to identify foods, transcribe audio, and estimate portions and calories. When you import a meal from a link, the public URL is sent to our backend and OpenAI so the page can be searched and converted into editable meal items. AI results are estimates; review and edit them before saving.</p>
    <p>Our services process an anonymous internal identifier, device verification credentials, Apple purchase identifiers, subscription status, usage counters, request timestamps, and technical logs needed for security, quotas, troubleshooting, and purchase validation. We do not require an email address, password, or social account to use Cave Cals.</p>
    <h2>Purchases and third parties</h2>
    <p>Apple processes payments and provides subscription transaction information. RevenueCat provides subscription offerings, paywall services, entitlement status, and purchase restoration; it receives an anonymous app identifier, purchase information, and paywall interactions. Vercel hosts our web and API services, Neon hosts service records, OpenAI processes selected AI media and public meal links, and Open Food Facts provides product data. Each provider processes information under its own terms and privacy policy.</p>
    <h2>Retention and deletion</h2>
    <p>We request deletion of uploaded media after processing. Temporary uploads, estimates, and upload records expire after 24 hours and scheduled cleanup normally removes them within 48 hours. Operational backups and logs may persist for a limited period for security and reliability. OpenAI, Apple, RevenueCat, Vercel, Neon, and Open Food Facts may retain information under their own policies.</p>
    <p>Because Cave Cals does not require an account, we cannot identify a diary stored only on your device or private iCloud account. You can delete that data from the app or Apple device/iCloud controls. To request deletion of information held by Claim727, email <a href="mailto:phil@claim727.com">phil@claim727.com</a> and include enough detail to locate your records. We will verify the request and respond within a reasonable period.</p>
    <h2>Choices and permissions</h2>
    <p>Camera and microphone access are requested only when you use those features. You can deny or revoke permissions in iOS Settings. You can use manual food and calorie logging without sending media to AI. You can manage or cancel subscriptions through your Apple ID subscription settings.</p>
    <h2>Security</h2>
    <p>We use encrypted transport, signed Apple purchase verification, device attestation, access-controlled temporary storage, and limited retention. No method of transmission or storage is guaranteed to be completely secure.</p>
    <h2>Children</h2>
    <p>Cave Cals is not directed to children under 13, and we do not knowingly collect personal information from children under 13. If you believe a child has provided information, contact us so we can investigate and delete it where appropriate.</p>
    <h2>Changes and contact</h2>
    <p>We may update this policy as Cave Cals changes. We will post the current version and effective date at this URL. Questions, privacy requests, and support requests can be sent to <a href="mailto:phil@claim727.com">phil@claim727.com</a>.</p>
    <p><strong>Claim727 LLC</strong><br /><a href="mailto:phil@claim727.com">phil@claim727.com</a></p>
  </main>;
}
