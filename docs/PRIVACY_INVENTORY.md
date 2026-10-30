# Personal data inventory (RA 10173)

What personal data SmartSumbong collects, why, where it is kept, who can see
it, how long it is kept, and who else handles it. It is drawn from the
database itself (`supabase/migrations`, up to 0149), the portal and the app,
as of 29 October 2026. It is the factual base for the Data Privacy Act
section of the paper and for the barangay's own privacy notice. It is not
legal advice: the legal bases below are the ones the team proposes, for the
barangay and the adviser to confirm.

## 1. Who is responsible

| Role under RA 10173 | Who |
|---|---|
| Personal Information Controller (decides what is collected and why) | Barangay 183, Zone 20, Villamor, Pasay City |
| Personal Information Processors (handle data on the barangay's behalf) | The services in section 5 |
| Data Protection Officer | Not yet named. The barangay names one (Sec. 21; NPC Circular 2022-04) |
| System developers | Group 12, until hand-over; afterwards the barangay's super admins (Sir Kiko) |

## 2. Whose data

- **Residents**: people who register in the app to file complaints.
- **Tanods**: barangay service personnel who take dispatches in the app.
- **Administrators**: barangay officials and staff who use the portal (super admin, committee, captain).
- **Third parties named in complaints**: whoever a complaint is about, written into its description or shown in its photos.

## 3. What is collected

### Residents

| Data | Why | Where (table) | Who can see it | Kept |
|---|---|---|---|---|
| Full name, mobile number | Identify the complainant; sign-in (the number is the login); SMS reset codes | `users` | The resident; administrators | While the account exists. Account deletion clears them (section 7) |
| Email | Optional sign-in address | `auth.users`, `users` | The resident; administrators | Same |
| Home address (free text) | "How to find your house" for the barangay | `users.address` | The resident; administrators | Same |
| Government ID photo, ID type | Verify that the resident is real and lives in the barangay | Cloudinary `ids/`; `users.id_image_url`, `id_type` | Administrators reviewing verification | Deleted from Cloudinary a week after nothing points to it (replaced, declined, account deleted) (0118) |
| Selfie, profile picture | Match the person to the ID; show in the portal | Cloudinary `selfies/`, `avatars/` | Administrators | Same as the ID photo |
| Name and number read from the ID (OCR) | Help the administrator check the ID; flag mismatches | `users.ocr_extracted_name`, `ocr_extracted_number`, `ocr_flags` | Administrators | While the account exists |
| Complaint: category, option picked, description, pin location, place name | The complaint itself | `reports`, `report_concerns` | The resident; administrators allowed to see that category (0145); the tanod dispatched to it | Never deleted: a removed complaint is hidden, not erased (barangay record) |
| Complaint photos and videos | Evidence | Cloudinary; `report_media` | Same as the complaint | Same as the complaint |
| Messages with the barangay | Follow-up on a complaint | `report_messages`, `detail_requests` | The resident; administrators | Same as the complaint |
| Rating and comment after resolution, "is it fixed?" answers | Service quality | `feedback`, `resolution_checks` | Administrators | Same as the complaint |
| Device push token | Send notifications to the phone | `device_tokens` | Nobody reads it; the push function uses it | Removed on sign-out and account deletion |
| Notification preferences, quiet hours | Respect the resident's choices | `users.muted_notification_kinds`, `push_*` | The resident | While the account exists |
| Notifications | Tell the resident what happened | `notifications` | The resident | Read ones 90 days, any 365 days (0115) |
| Failed sign-in count | Lock out password guessing | `login_attempts` | Nobody (the database) | Cleared on a successful sign-in |
| SMS reset code (hashed, never the code itself) | Forgot-password by SMS (0085) | `password_otps` | Nobody | **No automatic purge yet (gap, section 8)** |

**Anonymous complaints.** A resident can file anonymously. The name is hidden from the public and from published logs, but not from the barangay: the account stays bound to the complaint, so the resident still gets updates (use case Submit Complaint, alternative flow A1; panel ask 4).

**What others see.** If a resident publishes a complaint on the resident map, other residents see only its category, status, location and date. They never see a name, the words or the photos (0073). The public transparency page shows totals, and a heat map snapped to a ~44 m grid that drops any cell with fewer than 3 reports, so no single home can be pointed at (0043).

### Tanods

| Data | Why | Where | Who can see it | Kept |
|---|---|---|---|---|
| Name, mobile number, ID, selfie | As for residents; appointment as a tanod | `users`, Cloudinary | Administrators | As for residents |
| Last known location (one point, not a history) | Find the nearest tanod for a dispatch | `users.last_geom`, `last_location_at` | Administrators | Overwritten each update. The location history was removed (0072) |
| Duty status and attendance (with location at check-in) | Who is on duty | `users.duty_status`, `attendance` | Administrators | **No automatic purge yet (gap)** |
| Committees and the committee's role for them | Which committee a tanod works with (0153) | `tanod_committees`, `tanod_committee_log` | Super admins; that committee's admins; the tanod (their approved committees) | While the account exists; the log is kept as a record |
| Dispatch work: accept, steps, field notes, photos, escalations | The job record | `dispatches`, `dispatch_updates`, `dispatch_media`, `escalation_requests` | Administrators; the tanod | Same as the complaint |
| Retirement requests | Leaving the service | `retirement_requests` | Administrators | Kept as a record |

### Administrators

| Data | Why | Where | Who can see it | Kept |
|---|---|---|---|---|
| Name, email, mobile number, tier, committee, official role | Sign-in; what each may see and do (0145) | `users` | Other super admins | While the account exists |
| Actions on cases (status changes, remarks, who handled what) | Accountability | `status_logs`, `case_handler_log`, `account_audit` | Administrators | Never: the audit trail is hash-chained and cannot be edited (0114) |
| Portal sign-in and sign-out times (Kagawads and staff only), and the cases they touched each day | The punch card: accountability for who worked which cases (0153) | `admin_punches`; the case history above | The person; their Kagawad; super admins and captains | **No automatic purge yet (gap)**; nothing is recorded for super admins or captains |
| Browser push subscription | Portal notifications | `web_push_subscriptions` | Nobody reads it | Removed when the administrator turns portal alerts off; at most 10 per person are kept |
| Staff details (birthday, leave, credentials, shift check-ins, team posts, game scores) | The Workspace (switched off until after the defense, 0144) | `staff_*`, `shift_checkins`, `team_posts`, `game_scores` | Administrators | **No automatic purge yet (gap)** |

### Third parties named in complaints

A complaint's words and photos can identify a neighbour, a vendor or a vehicle. The app tells residents what the system is for and is not for (the scope note on the category screen). A sensitive case (VAWC and the like) is marked `is_sensitive` and gets its own status and handling (panel ask 5). Everything in the complaint follows the complaint's rules above.

## 4. Sensitive personal information (Sec. 3(l))

- **Government ID photos and the ID number read from them** count as sensitive personal information (government-issued identifiers). They are only used for verification. Only administrators can read them, through row level security, and the photos are deleted a week after nothing uses them.
- **Complaints marked sensitive** (violence, abuse) can carry information about a person's health, family or offences. They are marked, shown in their own colour, and can be referred to the right office.
- No biometrics are processed. The selfie is compared by a person, not by face recognition. OCR reads the printed text on the ID only.

## 5. Who else handles the data (processors)

| Service | What it receives | Where | Why |
|---|---|---|---|
| Supabase (database, sign-in, realtime, functions) | Everything in section 3 except the photo files | Mumbai, India | The system's database |
| Cloudinary | ID photos, selfies, profile pictures, complaint and dispatch photos and videos | Cloudinary's storage (check the account's region) | Image storage |
| Render | The portal's pages as they are served, administrators' IP addresses in its logs | Singapore | Portal hosting |
| Render (engine, when deployed) | ID photos, to read their text (OCR) | Singapore | The server engine (0137) |
| Google Firebase | Device push tokens, notification text; crash reports (device model, OS, error), with no user id attached | Google | Push notifications, crash reports |
| Semaphore | Mobile number and a one-time code | Philippines | SMS for forgotten passwords (0085) |
| Cloudflare Turnstile | A browser check at registration (IP, browser signals) | Cloudflare | Stop automated sign-ups |
| OpenStreetMap Nominatim | A complaint's coordinates, sent from the portal's server, and the text a resident types into the place search | OpenStreetMap Foundation | Street names for complaints |
| Map tile and weather services | The barangay's area only (no person's data); the viewer's IP address, as any web request | Various | Maps, rain and flood layers |

Cross-border transfer: the database is in India and the portal in Singapore. Under Sec. 21 (accountability) the barangay stays responsible for data it sends abroad. A data sharing or processing agreement with each service, or at least a record of their terms, belongs in the barangay's privacy file.

## 6. Proposed legal bases (for the barangay to confirm)

- **Complaints and their handling**: the barangay's mandate to keep the peace and deliver basic services (Local Government Code, Sec. 389 and 391), so processing needed for a public authority's function (Sec. 12(e)). For sensitive information, Sec. 13(b) and (f).
- **Identity verification (ID, selfie)**: consent at registration (Sec. 12(a), 13(a)). The resident agrees to the Terms and Privacy Policy before the account is made.
- **Notifications, preferences, published complaints**: consent. Each can be switched off in the app.
- **Staff and tanod work records**: the barangay's function as the employer and appointing office (Sec. 12(c), (e)).

## 7. Rights of the people in the data

| Right | How it works today |
|---|---|
| To be informed | Terms and Privacy Policy in the app (a draft prepared for the barangay to adopt); the scope note on the category screen |
| To access | A resident sees their profile, complaints, messages and notifications in the app |
| To correct | Profile edits; a name or ID change goes to the barangay as a profile request (`profile_requests`) |
| To erase | Delete account in the app (0045). With no complaints filed, the account is deleted. With complaints filed, the complaints stay (barangay record) and the name, number, address, photos and sign-in are removed |
| To object | Notifications can be muted; a published complaint can be unpublished |
| To data portability | Not offered in the app; the barangay can export a resident's complaints from the portal on request |

## 8. Security measures (Sec. 20)

- Row level security on every table. Administrators see only what their tier and committee allow (0145).
- An immutable, hash-chained audit trail of every status change and account action (0114).
- Sessions stored in the Android Keystore. The portal uses only the publishable key, with every request carrying the administrator's own token.
- Strict content security policy and CSRF tokens in the portal; sign-in lockout; reset codes stored hashed.
- Identity photos deleted when unused. Notifications purged on a schedule.
- Secrets kept encrypted (age) in a private vault, never in the code.

## 9. Gaps to close before going live

1. **Name a Data Protection Officer** for the barangay, and register with the NPC if required.
2. **Adopt the Privacy Policy**. The app's text is a draft for the barangay to review and approve.
3. **Retention for what has none**: SMS reset codes (`password_otps`), attendance, Workspace staff data, `account_audit`. The team proposes 30 days for codes and a period the barangay sets for the rest.
4. **Record the processors' terms** (section 5) and check Cloudinary's storage region.
5. **Breach procedure**: who is told, and how fast (72 hours to the NPC, Sec. 20(f); NPC Circular 16-03).
6. **Complaint records**: decide how long complaints are kept, in line with the barangay's records schedule. Today they are kept indefinitely.
