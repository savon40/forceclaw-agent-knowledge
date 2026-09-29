# Financial Services Cloud (FSC) — data model and queries

## When this applies

Any request that touches Financial Services Cloud data: clients, households, financial accounts, balances, transactions, goals, financial plans, life events, meeting notes (interactions), insurance policies — or an Agentforce agent, prompt template, Prompt Flow, or report built on them ("prepare me for my meeting with the Smiths", "which clients have a delinquent loan?", "build an agent for our advisors").

Everything marked **verified** below was run against a real FSC org (standard FSC objects, API 67). Picklist values and some fields vary by org and license — `describe_object` before relying on one.

## Step 1 — detect which FSC data model the org has

FSC comes in two flavours with **different object and field names**. Never assume; never mix them.

| | **Standard FSC objects** (current) | **FinServ__ managed package** (older orgs) |
|---|---|---|
| Financial account | `FinancialAccount` | `FinServ__FinancialAccount__c` |
| Owner / role | `FinancialAccountParty` | `FinServ__FinancialAccountRole__c`, `FinServ__PrimaryOwner__c` field |
| Goal | `FinancialGoal` | `FinServ__FinancialGoal__c` |
| Life event | `PersonLifeEvent` | `FinServ__LifeEvent__c` |

`check_agentforce_readiness` reports the flavour ("standard FSC objects (no FinServ__ package)" or a count of `FinServ__` objects) and which FSC objects exist. Outside an agent task, check with `SELECT COUNT() FROM EntityDefinition WHERE QualifiedApiName LIKE 'FinServ__%'` (Tooling or standard SOQL) and `list_objects`.

**This doc covers the standard objects.** For a `FinServ__` org: `describe_object` every object before querying — the package names above are the common ones but UNVERIFIED here; don't carry field names across flavours.

## Step 2 — the standard data model (verified)

| Concept | Object | Key fields / notes |
|---|---|---|
| Client (person) | **Person Account** — `Account` with `IsPersonAccount = true`, record type `PersonAccount` | `FirstName`, `LastName`, `PersonEmail`, `PersonBirthdate`, `Phone`, **`PersonContactId`** (the Contact behind the person — life events and household membership point here) |
| Household | `Account`, record type **`Household`** | Members via `AccountContactRelation` (below). `PartyRelationshipGroup` also exists but may be empty — households live on Account in practice. |
| Household membership | **`AccountContactRelation`** (ACR) | `AccountId` = the household, `ContactId` = the person's `PersonContactId`, `IsPrimaryMember`, `Roles`. `Contact.AccountId` = the person account. |
| Business | `Account`, record type `Business` | |
| Financial account | **`FinancialAccount`** | Required: `Name`, `FinancialAccountNumber`, `Type`. `Type`: Savings, Checking, Credit Card, Mortgage, Automotive Loan, Automotive Lease, Loan, Investment Account, Home Equity Line of Credit. `Status`: Active, Closed, **Delinquent**, On Hold. Also `OpeningDate`, `PrincipalAmount`, `InterestRate`, `CreditLimit`, `PaymentDueDate`, `AmountDue`, `IsHeldAway`. **No balance field and no owner field.** |
| Owners | **`FinancialAccountParty`** | `FinancialAccountId`, **`AccountId`** (person account), `ContactId` (**often empty** — see gotchas), `Role` (Owner, Beneficiary, Leasee, Driver), `IsRoleActive` (computed, read-only), `RoleStartDate`/`RoleEndDate`. |
| Balances | **`FinancialAccountBalance`** (child) | Required: `FinancialAccountId`, `Type`. `Type`: Total Balance, Current Posted Balance, Principal Balance, Available Balance, Available Credit, Minimum Payment, Balance Last Statement, Cash Balance, Pending Deposit/Withdrawal, Lease Balance. `Amount`, `BalanceAsOfDate`. **Many rows per account — take the newest per `Type`.** |
| Transactions | `FinancialAccountTransaction` | Required: `FinancialAccountId`, `Amount`, `TransactionDate`, `DebitCreditIndicator` (Credit, Debit). `Status` (Pending, Booked), `Description`. |
| Goals | **`FinancialGoal`** + `FinancialGoalParty` | Goal: required `Name`, `Type` (Education, Emergency, Home, Pay off Debt, Retirement, Vacation, Vehicle, Other), `Status` (**NOT_STARTED, IN_PROGRESS, COMPLETED** — API values), `Priority` (LOW, MEDIUM, HIGH), `TargetAmount`, `ActualAmount`, `TargetDate`. Party: `FinancialGoalId`, `AccountId` (person) — **no ContactId**. |
| Financial plan | `FinancialPlan` | Required `Name`, `Type` (Education, Retirement, Other), `AccountId`, `Status` (**NotStarted, InProgress, Completed** — different casing from goals). |
| Life events | **`PersonLifeEvent`** | Required `Name`, **`PrimaryPersonId` → Contact** (the `PersonContactId`), `EventDate`, `EventType` (Birth, Graduation, Job, Marriage, Relocation, Car, Home, Baby, **Diagnosis**, Retirement). `EventDescription`, `IsTentative`, `IsExpired`. |
| Business events | `BusinessMilestone` | `PrimaryAccountId`, `MilestoneType`, `MilestoneDate`. |
| Meetings | **`Interaction`** + **`InteractionSummary`** | Interaction: `Name`, `AccountId`, **`StartTime` / `EndTime`** (not StartDateTime), `InteractionType` (Email, Phone Call, In Person, Conference). Summary: `AccountId`, `InteractionId`, `MeetingNotes`, `NextSteps`, `InteractionPurpose` (Deal Execution, Meet and Greet, Quarterly Check-In), `Status` (Draft, **Published**), `ConfidentialityType` (Confidential, Public). Prefer these over Tasks for meeting notes. |
| Insurance | `InsurancePolicy` | Required `Name`, `NameInsuredId` → Account. `PolicyType` (Home, Auto, Life, Annuity, …), `Status` (In Force, Lapsed, …), `PremiumAmount`, `RenewalDate`. |
| Securities | `FinancialSecurity` exists; **`FinancialHolding` may not** | No holdings object → no portfolio/allocation questions. Say so; don't estimate. |
| Referrals | `Referral` exists but is often unconfigured (Name only) | Treat as unavailable unless its fields are set up. |

## Step 3 — reading a household (verified, in this order)

This is the read path for "prepare me for my meeting with the Carters", a household summary, or a Prompt Flow / invocable action that feeds one.

```sql
-- 1. The household
SELECT Id, Name FROM Account WHERE Name = 'Carter Household' AND RecordType.DeveloperName = 'Household'

-- 2. Members: person account Id (Contact.AccountId) and PersonContactId (ContactId)
SELECT Contact.Name, Contact.AccountId, ContactId, IsPrimaryMember, Roles
FROM AccountContactRelation WHERE AccountId = :householdId

-- 3. Financial accounts — by the members' PERSON ACCOUNT Ids (not ContactId)
SELECT FinancialAccountId, FinancialAccount.Name, FinancialAccount.Type, FinancialAccount.Status,
       FinancialAccount.AmountDue, FinancialAccount.PaymentDueDate, Account.Name, Role
FROM FinancialAccountParty WHERE AccountId IN :personAccountIds AND IsRoleActive = true

-- 4. Balances — newest first; keep the first row per (account, Type)
SELECT FinancialAccount.Name, Type, Amount, BalanceAsOfDate
FROM FinancialAccountBalance WHERE FinancialAccountId IN :financialAccountIds ORDER BY BalanceAsOfDate DESC

-- 5. Recent transactions
SELECT FinancialAccount.Name, TransactionDate, Amount, DebitCreditIndicator, Description
FROM FinancialAccountTransaction WHERE FinancialAccountId IN :financialAccountIds ORDER BY TransactionDate DESC LIMIT 10

-- 6. Goals — by person account Ids; dedupe by goal
SELECT FinancialGoal.Name, FinancialGoal.Type, FinancialGoal.Status, FinancialGoal.TargetAmount,
       FinancialGoal.ActualAmount, FinancialGoal.TargetDate
FROM FinancialGoalParty WHERE AccountId IN :personAccountIds

-- 7. Life events — by PersonContactIds
SELECT Name, EventType, EventDate, IsTentative, EventDescription, PrimaryPerson.Name
FROM PersonLifeEvent WHERE PrimaryPersonId IN :personContactIds ORDER BY EventDate DESC

-- 8. Recent meetings — on the household, newest meeting first
SELECT Name, InteractionPurpose, Interaction.StartTime, MeetingNotes, NextSteps
FROM InteractionSummary WHERE AccountId = :householdId AND Status = 'Published'
ORDER BY Interaction.StartTime DESC LIMIT 3

-- 9. Insurance and open cases — by person account Ids
SELECT Name, PolicyType, Status, PremiumAmount, RenewalDate FROM InsurancePolicy WHERE NameInsuredId IN :personAccountIds
SELECT CaseNumber, Subject, Status FROM Case WHERE AccountId IN :personAccountIds AND IsClosed = false
```

Starting from a **person** instead of a household: their households are
`SELECT Account.Name FROM AccountContactRelation WHERE ContactId = :personContactId AND Account.RecordType.DeveloperName = 'Household'`.

## Gotchas (all verified)

- **`FinancialAccountParty.ContactId` is often empty.** Salesforce-created and imported owner rows frequently set only `AccountId` (the person account). Always join owners on `AccountId`. A query on `ContactId` silently misses those accounts.
- **Semi-joins are limited.** `WHERE AccountId IN (SELECT Contact.AccountId FROM AccountContactRelation …)` fails ("inner select field cannot have more than one level of relationships"), and a semi-join inside a semi-join fails ("Nesting of semi join sub-selects is not supported"). Get the members first (step 2), then query by the Id list.
- **Joint accounts return one party row per owner, and goals one row per member.** Group by `FinancialAccountId` / goal before counting or summing — never double-count a joint balance.
- **Balances are history.** There are several rows per account and type. Report the newest per type, with its as-of date. Summing all rows is wrong.
- **Goal status is `IN_PROGRESS`, plan status is `InProgress`.** Use the API values in filters and DML; show labels to users.
- **`Interaction` dates are `StartTime` / `EndTime`.** Order meetings by `Interaction.StartTime`, not `CreatedDate`.
- **`Account.Description` (and other long text fields) can't be filtered in SOQL.**
- **`IsRoleActive` is computed** — don't set it on insert.
- **Person Account fields:** create with `RecordTypeId` = the PersonAccount record type plus `FirstName` / `LastName` (no `Name`). Life events and household membership need the **`PersonContactId`**, which only exists after the insert — query it back.

## Writing FSC data

- Create in dependency order: household and person accounts → `AccountContactRelation` (household ↔ `PersonContactId`) → financial accounts → parties (set **`AccountId`**, and `ContactId` if you have it) → balances / transactions → goals → goal parties → life events → interactions → interaction summaries.
- Money writes (balances, transactions, account status) are system-of-record data, usually fed by a core-banking integration. Only write them for test/seed data or when the user explicitly asks — and confirm first.

## Guardrails for anything client-facing (briefs, agents, templates)

- **Never invent figures.** Every balance, amount, date, rate and goal percentage must come from a query or action result. If it isn't in the data, say it isn't recorded.
- **Say how current a balance is** ("as of Sep 27").
- **Don't show internal record Ids** to advisors or clients.
- **Delinquent / overdue** status is sensitive: state the fact (amount due, days late) plainly, without judgement, and point to next steps from the notes.
- **`Diagnosis` life events are health information.** Don't include them in summaries, briefs or agent replies unless the user explicitly asks for that client's health-related events.
- **No advice.** Don't recommend products, allocations or actions beyond what's in the recorded next steps. Anything that reads like a recommendation or suitability note ends with: "Draft for advisor review — not a substitute for compliance review."
- **No holdings object → no portfolio analysis.** Say the org doesn't track holdings.

## Building FSC agents and prompts

Use the Agentforce skills (`16-agentforce-agent-script.md`, `17-agentforce-prompts-and-actions.md`) for the agent itself. FSC-specific design:

- **The household read path above is several queries with Id lists in between.** A Prompt Flow can do it (Get Records on ACR, then Get Records "In" the collected Ids), or an invocable Apex action can build the whole snapshot and return it as text — Apex is simpler to keep correct for multi-object household data (errors returned, not thrown; `with sharing`).
- **Pick the household deterministically.** When the advisor names a client ("the Carters"), resolve the name with an action (a Flow/Apex lookup), and if more than one household matches, list them and ask — don't pick one.
- **Test with real seeded households** covering: a joint household, a single client, a household with a delinquent account, a client with no meetings or goals (empty sections must say "none recorded", not be invented), a non-household record, and no record at all.
