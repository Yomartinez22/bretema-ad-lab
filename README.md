# Building a tiered Active Directory for a small automotive supplier

> Part of a personal identity lab (stage E1 of 4). Spanish overview: [docs/lab-overview.es.md](docs/lab-overview.es.md). The scripts are in [scripts/](scripts/).

## TL;DR

In one sentence: I built a tiered Active Directory for a fictional car-parts supplier, to control
privileged access and limit the damage of a stolen credential. It has three tiers, three GPOs
tested by prediction, a PingCastle before-and-after (Privileged Accounts from 50 down to 20), and
two PowerShell scripts that onboard and offboard users safely from an HR ticket.

What this does NOT cover: backups, LAPS, a second domain controller, and the cloud side, which is
the next stage.

## 1. The scenario

Brétema Componentes is a fictional tier-2 automotive supplier with about 40 employees in Vigo,
Spain. Its customers, German car manufacturers, require TISAX certification, and that forces the
company to control privileged access: who can administer what, and from where.

That is why I built this project: a tiered Active Directory that controls privileged access and
limits the damage of a stolen credential.

## 2. The design: tiers, OUs and groups

I designed the domain in three tiers, from the most privileged to the least:

- **Tier 0** controls the whole domain: the domain controller and the domain admins.
- **Tier 1** is for servers (empty for now).
- **Tier 2** is for users and their workstations.

The rule: **an account from a higher tier never logs on to a machine in a lower tier.** If a Tier 0
account logs on to a Tier 2 workstation, it leaves its credentials behind. If an attacker
compromises that workstation, they can steal those credentials, reach the domain controller and
take over the whole domain.

Each tier has its own organizational units (OUs):

```
corp.lab
├── Domain Controllers      ← DC01 (Tier 0 by definition)
└── Bretema
    ├── Tier0 ─ Accounts · Groups
    ├── Tier1 ─ Accounts · Groups · Servers
    └── Tier2 ─ Accounts · Groups · Workstations · Users
```

**OU vs group:** the OU decides which rules (policies) apply to you; the group decides what you can
access. That is why the rules are linked to OUs and the permissions are given to groups.

**People and accounts.** Marta, the IT manager, has three accounts, one per tier, and each one is
only used in its own tier. Diego, the support technician, has no Tier 0 account: his job does not
need it, so, by least privilege, he does not get one.

## 3. The rules (GPOs) and how I tested them

**GPO 1 · Tier 0 does not log on to Tier 2.** Linked to the Tier 2 workstations OU, it denies
Domain Admins, Enterprise Admins and Schema Admins the right to log on locally and through Remote
Desktop. It is a rule about *which machines* an account can log on to, so it goes on the
workstations OU.
*Test:* I tried to log on to the Tier 2 workstation with a domain admin account, and it was
blocked. Before applying it, I predicted the result for four accounts and got all four right. One
of them, `adm0-miglesias`, is not a direct member of Domain Admins, only through a nested group
(`T0-Admins`), and it was still blocked: the logon token carries every group, nested ones included.

**GPO 2 · Passwords.** The domain policy requires a minimum of 12 characters. NIST SP 800-63B-4
asks for 15 when the password is the only factor; I kept 12 in the lab as a documented exception,
because I manage many test accounts, and I would use 15 in a real environment. Tier 0 accounts get
more through a fine-grained password policy (PSO): a minimum of 20 characters. A GPO applies one
password policy to the whole domain; to ask more of one group, you need a PSO.
*Test:* creating a user with an 8-character password was rejected by Active Directory, and so was
a reset to 10 characters.

**GPO 3 · Audit.** Linked to the Domain Controllers OU, it logs credential validation, Kerberos,
logons, and changes to accounts and groups in the security log.
*Test:* creating a test account produced event **4720**, with who created it, when, and which
account. Creating accounts is a common persistence technique (MITRE ATT&CK T1136), and this event
is how you detect it.

## 4. Before and after: PingCastle

PingCastle is a free tool that audits Active Directory and gives it a risk score from 0 to 100:
the higher the score, the worse the configuration; the lower, the more secure.

| Category | Baseline | After the tiers and GPOs | After the fixes |
|---|---|---|---|
| Stale Objects | 30 | 30 | 30 |
| Privileged Accounts | 40 | **50** ⬆️ | **20** ⬇️ |
| Trusts | 0 | 0 | 0 |
| Anomalies | 60 | **50** ⬇️ | 50 |
| **Overall** | **60** | **50** | **50** |

My first audit gave an overall score of 60, with Privileged Accounts at 40. After building the
tiers, the accounts and the GPOs, the overall score went down to 50, but, to my surprise,
Privileged Accounts went **up** to 50. At the beginning I only had one admin account; the tier
model added more admin accounts, and every new privileged account is more attack surface to
protect. PingCastle flags it when two or more privileged accounts are outside the Protected Users
group.

To bring it down to 20, I added my Tier 0 admin account (`adm0-miglesias`) to the Protected Users
group, and marked the built-in Administrator as "sensitive and cannot be delegated". I kept
Administrator out of Protected Users on purpose, as the emergency account.

**The lesson:** the overall score stayed at 50, because the overall score is the worst of the four
categories. The real improvement, 30 points in Privileged Accounts, does not show in the overall
score. To lower it, you have to work on the worst category, which is Anomalies.

## 5. Automating joiners and leavers

I wrote two PowerShell scripts that onboard and offboard users in Active Directory from an HR
ticket. Every action is logged with the date, who ran it and the ticket number, and the password is
never logged.

- **The joiner script** creates the user in Active Directory and adds it to its department group.
- **The leaver script** refuses to touch admin accounts, **disables the account first**, records
  and removes its groups, and moves it to the `Bajas` (leavers) OU.

Both are idempotent: rerunning them is safe and changes nothing that is already done.

**If something fails:**
- If Active Directory rejects the password, the joiner **rolls back**: it deletes the half-created
  account and logs the real reason.
- If the leaver fails halfway, the account is already disabled, so it **fails safe**: no new
  sign-ins are possible (sessions already open stay open until they expire).

**One decision:** I chose to force a password change at first logon instead of keeping a password
set by the admin, because this way the user sets their own password, and the admin never knows the
password that is actually in use.

Full details and the test table: [docs/jml-scripts.es.md](docs/jml-scripts.es.md).

## 6. What went wrong, and what I learned

**1 · The clock on DC01.** The domain controller's clock was 13.6 hours off. The first thing I
checked was the time zone, and that was one of the main problems: the English ISO had set it to
California. I changed it to Romance Standard Time (Madrid), synchronized the DC with an external NTP
server and restarted it. The second cause was resuming the VM from a saved state, which freezes the
clock, so I now always shut it down cleanly.
*Lesson:* the DC is the time source for the whole domain, and Kerberos fails with more than five
minutes of difference.

**2 · A password that created half an account.** With an 8-character password, the joiner script
said "Created", but the account was disabled: Active Directory created it and then rejected the
password, and the error did not stop the script. I fixed it with `-ErrorAction Stop`, a
`try/catch`, and a rollback that deletes the half-created account.
*Lesson:* a success message is not proof; check the real state.

**3 · A typo in the UPN suffix** (`bretemacorp.com` instead of `bretemacomp.com`). I caught it
before creating any users, by checking the forest configuration.

**4 · A full disk.** VirtualBox stopped with `VERR_DISK_FULL`: the workstation VM had been created
in the default folder, on the small SSD. I moved it to the larger disk with `VBoxManage movevm`.

**5 · DC01 went back to an old snapshot** and lost the workstation's computer account, so the
workstation could no longer log on to the domain. I pre-created the computer account in its OU and
repaired the trust relationship with `Test-ComputerSecureChannel -Repair`.

## 7. What this does NOT cover, and what comes next

What this does NOT cover:

- **Credential theft itself.** The tier model does not prevent credentials from being stolen, for
  example by phishing; it limits what a stolen credential can reach.
- **The remaining Anomalies in PingCastle:** there is no backup of Active Directory, no LAPS (unique
  local admin passwords on each machine), and only one domain controller, so if it fails,
  everything fails.
- **The other logon types.** GPO 1 blocks local and Remote Desktop logons, but not network logons,
  scheduled tasks or services, and it does not block Tier 1 accounts on workstations.
- **Password exceptions,** accepted on purpose and written down: a 12-character minimum instead of
  15, and no check against lists of leaked passwords yet.

- **Movers.** The scripts cover joiners and leavers, not movers: when someone changes department,
  nothing removes their old groups. That is privilege creep, and access reviews are the safety net.
- **The initial password does not expire.** If a new hire starts late, the password set by the admin
  stays valid until first logon. In Entra, a Temporary Access Pass solves this: single-use and
  time-limited.
- **Cloud sessions.** The leaver script works on Active Directory. Revoking Entra sessions is a
  separate cloud step, and an already-issued token keeps working until it expires.

## Update, October 2026: stage E2 has started

- **Done:** a Microsoft Entra ID tenant with `bretemacomp.com` verified, and Microsoft Entra Connect
  Sync on the domain controller with **password hash sync** and **OU-scoped sync**: only the Tier 2
  users and groups go to the cloud; Tier 0, Tier 1, admin accounts and the leavers OU stay out. I
  validated the scope in **staging mode** before the first export.
- **A side effect I designed for:** moving a leaver to the leavers OU takes the account out of the
  sync scope, so Entra soft-deletes it on the next sync cycle.
- **Lab exception, written down:** Entra Connect runs on the domain controller because the lab has
  limited RAM. In production it belongs on a dedicated Tier 0 server, because its sync account has
  directory replication rights.
- **Next:** Conditional Access (MFA plus a compliant device), PIM for admin roles, and an access
  review.
