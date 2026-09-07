export default function Privacy() {
  return <main><p className="eyebrow">CAVE CALS</p><h1>Your food diary.</h1>
    <p>Your diary and daily goals are stored on your devices and, when enabled, in your private iCloud storage. AI logging does not upload your full diary.</p>
    <h2>Photo and voice estimates</h2><p>When you choose to analyze a photo or recording, the selected media is uploaded to private temporary storage and sent to OpenAI. Voice recordings are transcribed before foods and calories are estimated. You review and edit the result before adding it to your diary.</p>
    <p>Our backend attempts to delete media immediately after processing. Temporary estimates and upload records expire after 24 hours and are removed by scheduled cleanup, normally within 48 hours. Failed cleanup can delay deletion. OpenAI’s own data retention policies also apply; we request that identification responses are not stored as retrievable Responses API objects.</p>
    <h2>Purchases and service access</h2><p>We store an anonymous internal identifier, device verification credentials, Apple purchase identifiers, and usage counters to verify paid access and prevent abuse. No email or password is required. Apple handles payment information. RevenueCat manages subscription offerings and paywalls and receives the anonymous identifier, purchase information, and paywall interactions to support purchases and measure paywall performance. We do not use this data for advertising tracking.</p>
    <h2>Other services</h2><p>Product searches and barcodes are sent to Open Food Facts. Vercel hosts the API and temporary production media; Neon stores service records. Infrastructure providers may keep operational logs. We do not intentionally log photos, recordings, transcripts, or food estimates in application logs.</p>
    <p>Calorie estimates may be inaccurate. Correct the portions and calories before saving. You can use manual logging without sending media to AI.</p>
    <p className="muted">Before public release, the app publisher must add their legal identity, support contact, and data deletion contact to this page.</p>
  </main>;
}
