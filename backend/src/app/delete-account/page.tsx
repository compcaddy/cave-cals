import type { Metadata } from 'next';

export const metadata: Metadata = { title: 'Delete your Cave Cals account' };

export default function DeleteAccount() {
  return <main>
    <p className="eyebrow"><a href="/">CAVE CALS</a></p>
    <h1>Delete your Cave Cals account</h1>
    <p>Cave Cals is operated by Claim727 LLC. An account is optional and is used for clans. You can request deletion without installing the app.</p>
    <h2>Request deletion by email</h2>
    <p>Email <a href="mailto:phil@claim727.com?subject=Cave%20Cals%20account%20deletion">phil@claim727.com</a> with the subject “Cave Cals account deletion.” Include the email address you used to sign in with Google or Apple and your Cave Cals display name. Send the request from that email address when possible. Do not send passwords, identity documents, your food diary, or health records. We will verify ownership before deleting the account and respond within a reasonable period.</p>
    <h2>Delete from the app</h2>
    <p>On Android, open Clans using the fire icon on Home, return to your list of clans, and choose <strong>Delete clan account</strong>. Confirm the deletion. On iPhone, open About You, open your account, and choose <strong>Delete account</strong>.</p>
    <h2>What is removed</h2>
    <p>Deletion removes your clan account and memberships, display name, email address, profile photo, sign-in records, sessions, shared daily reports, and notification registrations. Past challenge results retain their standings without your name. Reports are retained without your identity until reviewed. Operational backups and logs follow the limited retention described in our <a href="/privacy">Privacy Policy</a>.</p>
    <h2>Your diary and subscription</h2>
    <p>Your personal food diary, saved meals, weight history and progress photos are stored separately on your device. Deleting a clan account does not erase those local records or cancel a subscription. Delete local records in the app or through your device’s app-storage controls. iCloud, Android backup, Apple Health, and Health Connect copies follow the controls of those services.</p>
    <p>Cancel an Android subscription in Google Play → Payments &amp; subscriptions → Subscriptions. On iPhone, use Settings → your Apple Account → Subscriptions. Purchase, fraud-prevention, security and legally required records may be retained separately under our <a href="/privacy">Privacy Policy</a> and our providers’ retention policies.</p>
    <h2>Other deletion requests</h2>
    <p>You can also email <a href="mailto:phil@claim727.com?subject=Cave%20Cals%20data%20deletion">phil@claim727.com</a> to request deletion of other information held by Claim727 without deleting your clan account. Describe which records you want removed and provide only enough detail to locate them. We cannot access or erase a diary stored only on your device or in your private cloud backup.</p>
  </main>;
}
